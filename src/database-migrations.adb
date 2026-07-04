with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Catalog;
with Database.Foreign_Keys;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;
with Database.Storage.Table_Heap;
with Database.Indexes;
with Database.Indexes.BTree;
with Database.Transactions;

package body Database.Migrations is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;
   use type Database.Status.Status_Code;
   use type Database.Types.Value_Kind;
   use type Database.Storage.Pages.Page_Id;

   type Schema_Snapshot is record
      Transaction_Id : Natural := 0;
      Schema         : Database.Schema.Table_Schema;
   end record;

   package Snapshot_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Schema_Snapshot);

   Snapshots : Snapshot_Vectors.Vector;

   procedure Remember_Schema
     (Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema) is
      Id : constant Natural := Natural (Database.Transactions.Id (Tx));
   begin
      if Snapshots.Length > 0 then
         for Existing of Snapshots loop
            if Existing.Transaction_Id = Id
              and then Existing.Schema.Table_Id = S.Table_Id
            then
               return;
            end if;
         end loop;
      end if;
      Snapshots.Append
        (Schema_Snapshot'(Transaction_Id => Id, Schema => S));
   end Remember_Schema;

   procedure Commit_Transaction (Transaction_Id : Natural) is
   begin
      if Snapshots.Length > 0 then
         for I in reverse 0 .. Natural (Snapshots.Length) - 1 loop
            if Snapshots.Element (I).Transaction_Id = Transaction_Id then
               Snapshots.Delete (I);
            end if;
         end loop;
      end if;
   end Commit_Transaction;

   procedure Rollback_Transaction
     (Transaction_Id : Natural;
      DB             : in out Database.Handle) is
      R : Database.Status.Result;
      pragma Unreferenced (R);
   begin
      if Snapshots.Length > 0 then
         for I in reverse 0 .. Natural (Snapshots.Length) - 1 loop
            if Snapshots.Element (I).Transaction_Id = Transaction_Id then
               R := Database.Catalog.Stage_Update_Table
                 (DB, Snapshots.Element (I).Schema);
               Snapshots.Delete (I);
            end if;
         end loop;
      end if;
   end Rollback_Transaction;

   function Write_Tx_Ok
     (Tx : Database.Transactions.Transaction) return Boolean is
   begin
      return Database.Transactions.Can_Write (Tx);
   end Write_Tx_Ok;

   function Type_Matches
     (Kind : Database.Types.Value_Kind;
      V    : Database.Values.Value) return Boolean is
   begin
      return V.Kind = Database.Types.Null_Value or else V.Kind = Kind;
   end Type_Matches;

   function Primary_Key_Value
     (S   : Database.Schema.Table_Schema;
      Row : Database.Rows.Row) return Database.Values.Value is
      Pos : constant Natural := Database.Schema.Primary_Key_Index (S);
   begin
      if Pos = Natural'Last then
         return Database.Values.Null_Value;
      end if;
      return Database.Rows.Get (Row, Pos);
   exception
      when others =>
         return Database.Values.Null_Value;
   end Primary_Key_Value;

   function Update_Catalog_Row_Cache
     (Old_Schema : Database.Schema.Table_Schema;
      New_Schema : Database.Schema.Table_Schema;
      Default_Value : Database.Values.Value) return Database.Status.Result is
      Rows : constant Database.Foreign_Keys.Row_Vectors.Vector :=
        Database.Catalog.Rows_For_Table (Old_Schema.Table_Id);
   begin
      if Rows.Length > 0 then
         for Old_Row of Rows loop
            declare
               New_Row : Database.Rows.Row := Old_Row;
            begin
               Database.Rows.Append (New_Row, Default_Value);
               Database.Catalog.Replace_Row
                 (Old_Schema.Table_Id, Old_Schema, Old_Row, New_Row);
            end;
         end loop;
      end if;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.Migration_Error, "failed to update cached rows");
   end Update_Catalog_Row_Cache;

   function Backfill_Persistent_Rows
     (Tx            : in out Database.Transactions.Transaction;
      Old_Schema    : Database.Schema.Table_Schema;
      New_Schema    : Database.Schema.Table_Schema;
      Default_Value : Database.Values.Value) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      type Row_Ref_Pair is record
         Row : Database.Rows.Row;
         Ref : Database.Indexes.Row_Reference;
      end record;
      package Pair_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Natural, Element_Type => Row_Ref_Pair);
      Pairs : Pair_Vectors.Vector;
      C  : Database.Storage.Table_Heap.Heap_Cursor;
      R  : Database.Status.Result;
   begin
      if DB = null or else Database.Backend (DB.all) /= Database.Persistent_Backend then
         return Database.Status.Success;
      end if;

      R := Database.Storage.Table_Heap.Scan_First
        (DB.File,
         Database.Storage.Pages.Page_Id (Old_Schema.Heap_First_Page),
         Old_Schema,
         C);
      while Database.Status.Is_Ok (R) and then C.Has_Row loop
         Pairs.Append
           (Row_Ref_Pair'
              (Row => C.Row,
               Ref => (Page => C.Current_Page, Slot_Offset => C.Slot_Offset)));
         R := Database.Storage.Table_Heap.Scan_Next (DB.File, Old_Schema, C);
      end loop;
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      if Pairs.Length > 0 then
         for Pair of Pairs loop
            declare
            Old_Row : constant Database.Rows.Row := Pair.Row;
            New_Row : Database.Rows.Row := Pair.Row;
            Old_Cursor : constant Database.Storage.Table_Heap.Heap_Cursor :=
              (Current_Page => Pair.Ref.Page,
               Slot_Offset  => Pair.Ref.Slot_Offset,
               Has_Row      => True,
               Row          => Pair.Row);
            Ref : Database.Indexes.Row_Reference;
            First : Database.Storage.Pages.Page_Id :=
              Database.Storage.Pages.Page_Id (New_Schema.Heap_First_Page);
            Key : constant Database.Values.Value :=
              Primary_Key_Value (Old_Schema, Old_Row);
            Root : Database.Storage.Pages.Page_Id :=
              Database.Storage.Pages.Page_Id (New_Schema.Primary_Index_Root);
         begin
            Database.Rows.Append (New_Row, Default_Value);
            R := Database.Storage.Table_Heap.Delete_At (Tx, DB.File, Old_Cursor);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            R := Database.Storage.Table_Heap.Append_Row
              (Tx, DB.File, DB.Page_Allocator, First, New_Schema, New_Row, Ref);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            if Root /= Database.Storage.Pages.Invalid_Page_Id
              and then Key.Kind /= Database.Types.Null_Value
            then
               R := Database.Indexes.BTree.Insert_Duplicate
                 (Tx, DB.File, DB.Page_Allocator, Root, Key, Ref);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end if;
            end;
         end loop;
      end if;
      return Database.Status.Success;
   end Backfill_Persistent_Rows;

   function Add_Column
        (Tx            : in out Database.Transactions.Transaction;
         Table_Name    : Wide_Wide_String;
         Column_Name   : Wide_Wide_String;
         Type_Info     : Database.Types.Type_Descriptor;
         Default_Value : Database.Values.Value) return Database.Status.Result is
   begin
      return Add_Column
        (Tx,
         Table_Name,
         Column_Name,
         Type_Info,
         Nullable => Default_Value.Kind = Database.Types.Null_Value,
         Default_Value => Default_Value);
   end Add_Column;

   function Add_Column
        (Tx            : in out Database.Transactions.Transaction;
         Table_Name    : Wide_Wide_String;
         Column_Name   : Wide_Wide_String;
         Type_Info     : Database.Types.Type_Descriptor;
         Nullable      : Boolean;
         Default_Value : Database.Values.Value) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      Old_Schema : Database.Schema.Table_Schema;
      New_Schema : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      New_Column : Database.Schema.Column;
   begin
      if not Write_Tx_Ok (Tx) then
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "write attempted in read-only transaction");
      end if;
      if DB = null then
         return Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction has no database");
      end if;
      if Type_Info.Kind = Database.Types.Null_Value then
         return Database.Status.Failure
           (Database.Status.Invalid_Schema, "column type cannot be null");
      end if;
      if not Type_Matches (Type_Info.Kind, Default_Value) then
         return Database.Status.Failure
           (Database.Status.Schema_Mismatch, "default value kind does not match column type");
      end if;
      if (not Nullable) and then Default_Value.Kind = Database.Types.Null_Value then
         return Database.Status.Failure
           (Database.Status.Constraint_Error, "non-null column requires a default");
      end if;

      R := Database.Catalog.Find_By_Name (Table_Name, Old_Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Database.Schema.Contains_Column_Name (Old_Schema, Column_Name) then
         return Database.Status.Failure
           (Database.Status.Already_Exists, "column already exists");
      end if;

      Remember_Schema (Tx, Old_Schema);
      New_Schema := Old_Schema;
      New_Column.Id := New_Schema.Next_Column_Id;
      New_Column.Name := To_Unbounded_Wide_Wide_String (Column_Name);
      New_Column.Kind := Type_Info.Kind;
      New_Column.Type_Info := Type_Info;
      New_Column.Nullable := Nullable;
      New_Column.Primary_Key := False;
      New_Schema.Columns.Append (New_Column);
      New_Schema.Next_Column_Id := New_Schema.Next_Column_Id + 1;
      New_Schema.Schema_Version := New_Schema.Schema_Version + 1;

      R := Backfill_Persistent_Rows (Tx, Old_Schema, New_Schema, Default_Value);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Update_Catalog_Row_Cache (Old_Schema, New_Schema, Default_Value);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Database.Catalog.Stage_Update_Table (DB.all, New_Schema);
   end Add_Column;

   function Rename_Column
        (Tx         : in out Database.Transactions.Transaction;
         Table_Name : Wide_Wide_String;
         Old_Name   : Wide_Wide_String;
         New_Name   : Wide_Wide_String) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      S : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      Pos : Natural;
      C : Database.Schema.Column;
   begin
      if not Write_Tx_Ok (Tx) then
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "write attempted in read-only transaction");
      end if;
      if DB = null then
         return Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction has no database");
      end if;
      R := Database.Catalog.Find_By_Name (Table_Name, S);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Pos := Database.Schema.Find_Column_Position (S, Old_Name);
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "column not found");
      end if;
      if Database.Schema.Contains_Column_Name (S, New_Name) then
         return Database.Status.Failure
           (Database.Status.Already_Exists, "target column already exists");
      end if;
      Remember_Schema (Tx, S);
      C := S.Columns.Element (Pos);
      C.Name := To_Unbounded_Wide_Wide_String (New_Name);
      S.Columns.Replace_Element (Pos, C);
      S.Schema_Version := S.Schema_Version + 1;
      return Database.Catalog.Stage_Update_Table (DB.all, S);
   end Rename_Column;

   function Drop_Column
        (Tx          : in out Database.Transactions.Transaction;
         Table_Name  : Wide_Wide_String;
         Column_Name : Wide_Wide_String) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      S : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      Pos : Natural;
   begin
      if not Write_Tx_Ok (Tx) then
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "write attempted in read-only transaction");
      end if;
      if DB = null then
         return Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction has no database");
      end if;
      R := Database.Catalog.Find_By_Name (Table_Name, S);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Pos := Database.Schema.Find_Column_Position (S, Column_Name);
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "column not found");
      end if;
      if S.Columns.Element (Pos).Primary_Key then
         return Database.Status.Failure
           (Database.Status.Unsupported_Migration, "cannot drop primary key column");
      end if;
      Remember_Schema (Tx, S);
      S.Columns.Delete (Pos);
      S.Schema_Version := S.Schema_Version + 1;
      return Database.Catalog.Stage_Update_Table (DB.all, S);
   end Drop_Column;

   function Change_Nullability
        (Tx          : in out Database.Transactions.Transaction;
         Table_Name  : Wide_Wide_String;
         Column_Name : Wide_Wide_String;
         Nullable    : Boolean) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      S : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      Pos : Natural;
      C : Database.Schema.Column;
   begin
      if not Write_Tx_Ok (Tx) then
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "write attempted in read-only transaction");
      end if;
      if DB = null then
         return Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction has no database");
      end if;
      R := Database.Catalog.Find_By_Name (Table_Name, S);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Pos := Database.Schema.Find_Column_Position (S, Column_Name);
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "column not found");
      end if;
      C := S.Columns.Element (Pos);
      if C.Primary_Key and then Nullable then
         return Database.Status.Failure
           (Database.Status.Unsupported_Migration, "primary key cannot be nullable");
      end if;
      Remember_Schema (Tx, S);
      C.Nullable := Nullable;
      S.Columns.Replace_Element (Pos, C);
      S.Schema_Version := S.Schema_Version + 1;
      return Database.Catalog.Stage_Update_Table (DB.all, S);
   end Change_Nullability;

end Database.Migrations;
