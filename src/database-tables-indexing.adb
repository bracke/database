with Database.Catalog;
with Database.Indexes.BTree;
with Database.Storage.Table_Heap;
with Database.Types;

package body Database.Tables.Indexing is
   use type Database.Types.Value_Kind;

   function Index_Value
     (Schema    : Database.Schema.Table_Schema;
      Row_Value : Database.Rows.Row;
      Column    : Natural) return Database.Values.Value is
      Pos : constant Natural := Database.Schema.Find_Column_Id_Position (Schema, Column);
   begin
      --  A row stored before its column was added holds no value for it.
      if Pos = Natural'Last or else Pos >= Database.Rows.Column_Count (Row_Value) then
         return Database.Values.Null_Value;
      end if;
      return Database.Rows.Get (Row_Value, Pos);
   end Index_Value;

   --  The column a table's primary index is keyed on, or Natural'Last for a table without a primary key.
   function Primary_Column (Schema : Database.Schema.Table_Schema) return Natural is
     (if Database.Schema.Primary_Key_Index (Schema) = Natural'Last then Natural'Last
      else Schema.Columns.Element (Database.Schema.Primary_Key_Index (Schema)).Id);

   --  The row visible to Tx whose Column equals Key, found through the index at Root. A built index is
   --  authoritative; an unbuilt one (see BTree.Is_Built) is bypassed by scanning the table.
   function Visible_Ref_For_Key
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Root   : Database.Storage.Pages.Page_Id;
      Key    : Database.Values.Value;
      Column : Natural;
      Ref    : out Database.Indexes.Row_Reference) return Database.Status.Result is
      Refs : Database.Indexes.BTree.Row_Reference_Vectors.Vector;
      Row_Value : Database.Rows.Row;
      R : Database.Status.Result;
      Cursor : Database.Storage.Table_Heap.Heap_Cursor;
      Bound : constant Database.Indexes.BTree.Range_Bound  :=
        (Kind => Database.Indexes.BTree.Inclusive, Key => Key);
   begin
      Ref := Database.Indexes.Invalid_Row_Reference;
      if Root = Database.Storage.Pages.Invalid_Page_Id then
         return Database.Status.Failure (Database.Status.Not_Found, "row not found");
      end if;
      if Database.Indexes.BTree.Is_Built (DB.File, Root) then
         R := Database.Indexes.BTree.Range_Find (DB.File, Root, Bound, Bound, Refs);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         for Candidate of Refs loop
            R := Database.Storage.Table_Heap.Read_At (Tx, DB.File, Candidate, Schema, Row_Value);
            if Database.Status.Is_Ok (R) then
               Ref := Candidate;
               return Database.Status.Success;
            elsif R.Code /= Database.Status.Not_Found then
               return R;
            end if;
         end loop;
         return Database.Status.Failure (Database.Status.Not_Found, "row not found");
      end if;
      if Schema.Heap_First_Page /= 0 then
         R := Database.Storage.Table_Heap.Scan_First
           (Tx, DB.File, Database.Storage.Pages.Page_Id (Schema.Heap_First_Page), Schema, Cursor);
         while Database.Status.Is_Ok (R) and then Cursor.Has_Row loop
            if Database.Values.Equal (Index_Value (Schema, Cursor.Row, Column), Key) then
               Ref := (Page => Cursor.Current_Page, Slot_Offset => Cursor.Slot_Offset);
               return Database.Status.Success;
            end if;
            R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Schema, Cursor);
         end loop;
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      return Database.Status.Failure (Database.Status.Not_Found, "row not found");
   end Visible_Ref_For_Key;

   function Any_Visible_Key
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Root   : Database.Storage.Pages.Page_Id;
      Key    : Database.Values.Value;
      Column : Natural) return Boolean is
      Ref : Database.Indexes.Row_Reference;
      R : Database.Status.Result;
   begin
      R := Visible_Ref_For_Key (Tx, DB, Schema, Root, Key, Column, Ref);
      return Database.Status.Is_Ok (R);
   end Any_Visible_Key;

   function Fill
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Root   : Database.Storage.Pages.Page_Id;
      Column : Natural;
      Unique : Boolean) return Database.Status.Result
   is
      Target : Database.Storage.Pages.Page_Id := Root;
      C      : Database.Storage.Table_Heap.Heap_Cursor;
      R      : Database.Status.Result;
   begin
      if Schema.Heap_First_Page = 0 then
         return Database.Status.Success;
      end if;
      R := Database.Storage.Table_Heap.Scan_First
        (DB.File, Database.Storage.Pages.Page_Id (Schema.Heap_First_Page), Schema, C);
      while Database.Status.Is_Ok (R) and then C.Has_Row loop
         declare
            K   : constant Database.Values.Value := Index_Value (Schema, C.Row, Column);
            Ref : constant Database.Indexes.Row_Reference := (Page => C.Current_Page, Slot_Offset => C.Slot_Offset);
         begin
            R := Database.Indexes.Validate_Secondary_Key (K);
            if Database.Status.Is_Ok (R) and then K.Kind /= Database.Types.Null_Value then
               if Unique then
                  R := Database.Indexes.BTree.Insert (Tx, Target, K, Ref);
                  if R.Code = Database.Status.Duplicate_Key then
                     R := Database.Status.Failure (Database.Status.Duplicate_Key, "duplicate value for unique index");
                  end if;
               else
                  R := Database.Indexes.BTree.Insert_Duplicate (Tx, Target, K, Ref);
               end if;
            end if;
         end;
         exit when not Database.Status.Is_Ok (R);
         R := Database.Storage.Table_Heap.Scan_Next (DB.File, Schema, C);
      end loop;
      return R;
   end Fill;

   --  Build the index at Root when it is unbuilt. A root an earlier version allocated and never wrote is filled in
   --  place. A file written before the catalog was rolled back with its transaction can name a root whose page the
   --  rollback removed or another table reused; such a root is replaced, and Replaced is set.
   function Ensure_Index
     (Tx       : in out Database.Transactions.Transaction;
      DB       : in out Database.Handle;
      Schema   : Database.Schema.Table_Schema;
      Root     : in out Database.Storage.Pages.Page_Id;
      Column   : Natural;
      Replaced : in out Boolean) return Database.Status.Result
   is
      R : Database.Status.Result;
   begin
      if Root = Database.Storage.Pages.Invalid_Page_Id or else Database.Indexes.BTree.Is_Built (DB.File, Root) then
         return Database.Status.Success;
      elsif Database.Indexes.BTree.Is_Unwritten (DB.File, Root) then
         R := Database.Indexes.BTree.Clear (Tx, Root);
      else
         R := Database.Indexes.BTree.Create (Tx, Root);
         Replaced := True;
      end if;
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      --  Uniqueness was enforced when the rows were written; a repair must not fail on them.
      return Fill (Tx, DB, Schema, Root, Column, Unique => False);
   end Ensure_Index;

   function Ensure_Indexes
     (Tx : in out Database.Transactions.Transaction;
      DB : in out Database.Handle;
      S  : in out Database.Schema.Table_Schema) return Database.Status.Result
   is
      Replaced : Boolean := False;
      Root     : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Page_Id (S.Primary_Index_Root);
      R        : Database.Status.Result := Ensure_Index (Tx, DB, S, Root, Primary_Column (S), Replaced);
   begin
      S.Primary_Index_Root := Natural (Root);
      for I in 0 .. Natural (S.Indexes.Length) - 1 loop
         exit when not Database.Status.Is_Ok (R);
         declare
            IX : Database.Indexes.Index_Metadata := S.Indexes.Element (I);
         begin
            R := Ensure_Index (Tx, DB, S, IX.Root_Page, IX.Column_Id, Replaced);
            S.Indexes.Replace_Element (I, IX);
         end;
      end loop;
      if Database.Status.Is_Ok (R) and then Replaced then
         R := Database.Catalog.Update_Table (DB, S);
      end if;
      return R;
   end Ensure_Indexes;

end Database.Tables.Indexing;
