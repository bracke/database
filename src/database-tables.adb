with Database.Rows;
with Database.Schema;
with Database.Transactions;
with Database.Predicates;
with Database.Status;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Database.Catalog;
with Database.Constraints;
with Database.Storage.Table_Heap;
with Database.Storage.Pages;
with Database.Values;
with Database.Types;
with Database.Indexes;
with Database.Indexes.BTree;
with Database.Queries;
with Database.Cursors;
with Database.Versioning;
with Database.Visibility;
with Database.Expressions;
with Database.Foreign_Keys;
with Database.Check_Constraints;
with Database.Generated_Columns;
with Database.Full_Text;

package body Database.Tables is
   use type Database.Indexes.Index_Id;
   use type Database.Predicates.Predicate_Kind;
   use type Database.Foreign_Keys.Foreign_Key_Action;
   package body Typed is
      use type Database.Types.Value_Kind;
      use type Database.Status.Status_Code;
      use type Ada.Containers.Count_Type;
      type Versioned_Row is record
         Item : Row_Type;
         Metadata : Database.Versioning.Row_Version_Metadata;
      end record;

      package All_Rows is new Ada.Containers.Indefinite_Vectors (Natural, Versioned_Row);
      Memory : All_Rows.Vector;

      function Future_Commit_Version (DB : Database.Handle) return Natural is
      begin
         return Database.Commit_Version (DB) + 1;
      end Future_Commit_Version;

      function Visible_To
        (Tx : Database.Transactions.Transaction;
         V  : Versioned_Row) return Boolean is
      begin
         return Database.Visibility.Is_Visible (Tx, V.Metadata);
      end Visible_To;

      function Read_Tx_Ok (Tx : Database.Transactions.Transaction) return Boolean is
      begin
         return Database.Transactions.Can_Read (Tx);
      end Read_Tx_Ok;

      function Write_Tx_Ok (Tx : Database.Transactions.Transaction) return Boolean is
      begin
         return Database.Transactions.Can_Write (Tx);
      end Write_Tx_Ok;

      function Read_Only_Write_Error return Database.Status.Result is
      begin
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction, "write attempted in read-only transaction");
      end Read_Only_Write_Error;

      function Current_Schema
        (DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema) return Database.Schema.Table_Schema is
         S : Database.Schema.Table_Schema := Schema;
         R : Database.Status.Result;
      begin
         R := Database.Catalog.Find_By_Name
           (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Schema.Name), S);
         if not Database.Status.Is_Ok (R) then
            return Schema;
         end if;
         return S;
      end Current_Schema;

      function Register
        (DB     : in out Database.Handle;
         Schema : in out Database.Schema.Table_Schema) return Database.Status.Result is
         Existing : Database.Schema.Table_Schema;
         R : Database.Status.Result;
      begin
         R := Database.Catalog.Find_By_Name  (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Schema.Name),
           Existing);
         if Database.Status.Is_Ok (R) then
            if Database.Schema.Column_Count (Existing) /= Database.Schema.Column_Count (Schema) then
               return Database.Status.Failure (Database.Status.Schema_Mismatch,
                 "registered table schema has different column count");
            end if;
            if Database.Schema.Column_Count (Schema) > 0 then
               for I in 0 .. Database.Schema.Column_Count (Schema) - 1 loop
                  declare
                     A : constant Database.Schema.Column := Existing.Columns.Element (I);
                     B : constant Database.Schema.Column := Schema.Columns.Element (I);
                  begin
                     if A.Id /= B.Id

                       or else Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (A.Name)
                         /= Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (B.Name)
                       or else A.Kind /= B.Kind
                       or else A.Nullable /= B.Nullable
                       or else A.Primary_Key /= B.Primary_Key then
                        return Database.Status.Failure (Database.Status.Schema_Mismatch,
                          "registered table schema is incompatible");
                     end if;
                  end;
               end loop;
            end if;
            Schema := Existing;
            return Database.Status.Success;
         elsif R.Code /= Database.Status.Not_Found then
            return R;
         end if;
         return Database.Catalog.Register (DB, Schema);
      end Register;

      function Register
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : in out Database.Schema.Table_Schema) return Database.Status.Result is
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         return Register (DB, Schema);
      end Register;

      function Column_Exists
        (S      : Database.Schema.Table_Schema;
         Column : Natural;
         Kind   : out Database.Types.Value_Kind) return Boolean is
      begin
         for C of S.Columns loop
            if C.Id = Column then
               Kind := C.Kind;
               return True;
            end if;
         end loop;
         return False;
      end Column_Exists;

      function Index_Value
        (Schema    : Database.Schema.Table_Schema;
         Row_Value : Database.Rows.Row;
         Column    : Natural) return Database.Values.Value is
         Pos : constant Natural := Database.Schema.Find_Column_Id_Position (Schema, Column);
      begin
         if Pos = Natural'Last then
            return Database.Values.Null_Value;
         end if;
         return Database.Rows.Get (Row_Value, Pos);
      exception
         when others => return Database.Values.Null_Value;
      end Index_Value;

      function Matching_Index
        (Schema : Database.Schema.Table_Schema;
         Column : Natural) return Database.Indexes.Index_Metadata is
         PK_Pos : constant Natural := Database.Schema.Primary_Key_Index (Schema);
         IX : Database.Indexes.Index_Metadata;
      begin
         if PK_Pos /= Natural'Last and then Schema.Columns.Element (PK_Pos).Id = Column
           and then Schema.Primary_Index_Root /= 0
         then
            IX.Id := 1;
            IX.Table_Id := Schema.Table_Id;
            IX.Kind := Database.Indexes.Primary_Key_Index;
            IX.Root_Page := Database.Storage.Pages.Page_Id (Schema.Primary_Index_Root);
            IX.Unique := True;
            IX.Column_Id := Column;
            IX.Key_Kind := Schema.Columns.Element (PK_Pos).Kind;
            return IX;
         end if;
         for Existing_IX of Schema.Indexes loop
            if Existing_IX.Column_Id = Column then
               return Existing_IX;
            end if;
         end loop;
         return (others => <>);
      end Matching_Index;

      function Catalog_Row_Id
        (S         : Database.Schema.Table_Schema;
         Row_Value : Database.Rows.Row) return Natural is
         Rows : constant Database.Foreign_Keys.Row_Vectors.Vector  :=
           Database.Catalog.Rows_For_Table (S.Table_Id);
         Wanted : constant Key_Type := Key_Of (From_Row (Row_Value));
      begin
         if Rows.Length = 0 then
            return 0;
         end if;
         for I in 0 .. Natural (Rows.Length) - 1 loop
            if Key_Of (From_Row (Rows.Element (I))) = Wanted then
               return I + 1;
            end if;
         end loop;
         return 0;
      exception
         when others =>
            return 0;
      end Catalog_Row_Id;

      function Indexable_Predicate
        (Schema : Database.Schema.Table_Schema;
         P      : Database.Predicates.Predicate;
         Found  : out Boolean) return Database.Predicates.Predicate is
         LF, RF : Boolean := False;
         L, R   : Database.Predicates.Predicate;
      begin
         Found := False;
         if (Database.Predicates.Kind (P) in
           Database.Predicates.Equals | Database.Predicates.Less_Than |
           Database.Predicates.Less_Or_Equal | Database.Predicates.Greater_Than |
           Database.Predicates.Greater_Or_Equal)
           and then Database.Predicates.Literal_Value (P).Kind /= Database.Types.Null_Value
         then
            declare
               IX : constant Database.Indexes.Index_Metadata  :=
                 Matching_Index (Schema, Database.Predicates.Column_Index (P));
            begin
               if IX.Id /= 0 or else IX.Column_Id = Database.Predicates.Column_Index (P) then
                  Found := True;
                  return P;
               end if;
            end;
         elsif Database.Predicates.Kind (P) = Database.Predicates.And_Predicate then
            L := Indexable_Predicate (Schema, Database.Predicates.Left (P), LF);
            if LF then
               Found := True;
               return L;
            end if;
            R := Indexable_Predicate (Schema, Database.Predicates.Right (P), RF);
            if RF then
               Found := True;
               return R;
            end if;
         end if;
         return P;
      end Indexable_Predicate;

      procedure Bounds_For
        (P    : Database.Predicates.Predicate;
         Low  : out Database.Indexes.BTree.Range_Bound;
         High : out Database.Indexes.BTree.Range_Bound) is
      begin
         Low := (Kind => Database.Indexes.BTree.Unbounded, Key => Database.Values.Null_Value);
         High := (Kind => Database.Indexes.BTree.Unbounded, Key => Database.Values.Null_Value);
         case Database.Predicates.Kind (P) is
            when Database.Predicates.Equals =>
               Low := (Kind => Database.Indexes.BTree.Inclusive, Key => Database.Predicates.Literal_Value (P));
               High := Low;
            when Database.Predicates.Less_Than =>
               High := (Kind => Database.Indexes.BTree.Exclusive, Key => Database.Predicates.Literal_Value (P));
            when Database.Predicates.Less_Or_Equal =>
               High := (Kind => Database.Indexes.BTree.Inclusive, Key => Database.Predicates.Literal_Value (P));
            when Database.Predicates.Greater_Than =>
               Low := (Kind => Database.Indexes.BTree.Exclusive, Key => Database.Predicates.Literal_Value (P));
            when Database.Predicates.Greater_Or_Equal =>
               Low := (Kind => Database.Indexes.BTree.Inclusive, Key => Database.Predicates.Literal_Value (P));
            when others =>
               null;
         end case;
      end Bounds_For;

      function Visible_Ref_For_Key
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Root   : Database.Storage.Pages.Page_Id;
         Key    : Database.Values.Value;
         Ref    : out Database.Indexes.Row_Reference) return Database.Status.Result is
         Refs : Database.Indexes.BTree.Row_Reference_Vectors.Vector;
         Row_Value : Database.Rows.Row;
         R : Database.Status.Result;
         Cursor : Database.Storage.Table_Heap.Heap_Cursor;
         PK_Pos : Natural;
         PK_Col : Natural;
         Bound : constant Database.Indexes.BTree.Range_Bound  :=
           (Kind => Database.Indexes.BTree.Inclusive, Key => Key);
      begin
         Ref := Database.Indexes.Invalid_Row_Reference;
         if Root = Database.Storage.Pages.Invalid_Page_Id or else Root = 0 then
            return Database.Status.Failure (Database.Status.Not_Found, "row not found");
         end if;
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

         PK_Pos := Database.Schema.Primary_Key_Index (Schema);
         if PK_Pos /= Natural'Last and then Schema.Heap_First_Page /= 0 then
            PK_Col := Schema.Columns.Element (PK_Pos).Id;
            R := Database.Storage.Table_Heap.Scan_First
              (Tx,
               DB.File,
               Database.Storage.Pages.Page_Id (Schema.Heap_First_Page),
               Schema,
               Cursor);
            while Database.Status.Is_Ok (R) and then Cursor.Has_Row loop
               if Database.Values.Equal
                    (Index_Value (Schema, Cursor.Row, PK_Col), Key)
               then
                  Ref :=
                    (Page        => Cursor.Current_Page,
                     Slot_Offset => Cursor.Slot_Offset);
                  return Database.Status.Success;
               end if;
               R := Database.Storage.Table_Heap.Scan_Next
                 (Tx, DB.File, Schema, Cursor);
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
         Key    : Database.Values.Value) return Boolean is
         Ref : Database.Indexes.Row_Reference;
         R : Database.Status.Result;
      begin
         R := Visible_Ref_For_Key (Tx, DB, Schema, Root, Key, Ref);
         return Database.Status.Is_Ok (R);
      end Any_Visible_Key;

      function Populate_From_Index
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         C : in out Cursor) return Database.Status.Result is
         Found : Boolean := False;
         Chosen : Database.Predicates.Predicate := Indexable_Predicate (Schema, Predicate, Found);
         IX : Database.Indexes.Index_Metadata;
         Refs : Database.Indexes.BTree.Row_Reference_Vectors.Vector;
         Row_Value : Database.Rows.Row;
         R : Database.Status.Result;
         Low, High : Database.Indexes.BTree.Range_Bound;
      begin
         C.Uses_Materialized := False;
         if not Found then
            return Database.Status.Failure (Database.Status.Not_Found, "no usable index");
         end if;
         IX := Matching_Index (Schema, Database.Predicates.Column_Index (Chosen));
         if IX.Root_Page = Database.Storage.Pages.Invalid_Page_Id then
            return Database.Status.Failure (Database.Status.Not_Found, "index has no root page");
         end if;
         Bounds_For (Chosen, Low, High);
         R := Database.Indexes.BTree.Range_Find (DB.File, IX.Root_Page, Low, High, Refs);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         C.Uses_Materialized := True;
         for Ref of Refs loop
            R := Database.Storage.Table_Heap.Read_At (Tx, DB.File, Ref, Schema, Row_Value);
            if Database.Status.Is_Ok (R) and then Database.Predicates.Matches (Predicate, Row_Value) then
               C.In_Memory_Rows.Append (From_Row (Row_Value));
            elsif not Database.Status.Is_Ok (R) and then R.Code /= Database.Status.Not_Found then
               return R;
            end if;
         end loop;
         if C.In_Memory_Rows.Length > 0 then
            C.Current := C.In_Memory_Rows.Element (0);
            C.Has_Current := True;
         end if;
         return Database.Status.Success;
      end Populate_From_Index;

      function Visible_Rows_For_Table
        (Tx       : in out Database.Transactions.Transaction;
         DB       : in out Database.Handle;
         Table_Id : Natural) return Database.Foreign_Keys.Row_Vectors.Vector is
         S : Database.Schema.Table_Schema;
         R : Database.Status.Result;
         C : Database.Storage.Table_Heap.Heap_Cursor;
         Rows : Database.Foreign_Keys.Row_Vectors.Vector;
      begin
         if Database.Backend (DB) /= Database.Persistent_Backend then
            return Database.Catalog.Rows_For_Table (Table_Id);
         end if;
         R := Database.Catalog.Find_By_Id (Table_Id, S);
         if not Database.Status.Is_Ok (R) then
            return Rows;
         end if;
         R := Database.Storage.Table_Heap.Scan_First
           (Tx, DB.File, Database.Storage.Pages.Page_Id (S.Heap_First_Page), S, C);
         while Database.Status.Is_Ok (R) and then C.Has_Row loop
            Rows.Append (C.Row);
            R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, S, C);
         end loop;
         return Rows;
      end Visible_Rows_For_Table;

      function Apply_Generated_And_Checks
        (S   : Database.Schema.Table_Schema;
         Row : in out Database.Rows.Row) return Database.Status.Result is
         R : Database.Status.Result;
      begin
         R := Database.Generated_Columns.Recompute_Stored
           (Database.Catalog.Generated_Columns_For_Table (S.Table_Id), S, Row);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         return Database.Check_Constraints.Validate_All
           (Database.Catalog.Check_Constraints_For_Table (S.Table_Id), S, Row, False);
      end Apply_Generated_And_Checks;

      function Enforce_Foreign_Key_Insert_Update
        (Tx  : in out Database.Transactions.Transaction;
         DB  : in out Database.Handle;
         S   : Database.Schema.Table_Schema;
         Row : Database.Rows.Row) return Database.Status.Result is
         FKs : constant Database.Foreign_Keys.Foreign_Key_Vectors.Vector  :=
           Database.Catalog.Foreign_Keys_For_Referencing_Table (S.Table_Id);
         Parent_Schema : Database.Schema.Table_Schema;
         Parent_Rows : Database.Foreign_Keys.Row_Vectors.Vector;
         R : Database.Status.Result;
      begin
         for FK of FKs loop
            if not FK.Deferred
              and then FK.Referencing_Table /= FK.Referenced_Table
            then
               R := Database.Catalog.Find_By_Id (FK.Referenced_Table, Parent_Schema);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               Parent_Rows := Visible_Rows_For_Table (Tx, DB, FK.Referenced_Table);
               R := Database.Foreign_Keys.Validate_Insert_Or_Update
                 (FK, S, Parent_Schema, Row, Parent_Rows);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end if;
         end loop;
         return Database.Status.Success;
      end Enforce_Foreign_Key_Insert_Update;

      function Apply_Referential_Delete_Actions
        (Tx  : in out Database.Transactions.Transaction;
         DB  : in out Database.Handle;
         S   : Database.Schema.Table_Schema;
         Row : Database.Rows.Row) return Database.Status.Result is
         FKs : constant Database.Foreign_Keys.Foreign_Key_Vectors.Vector  :=
           Database.Catalog.Foreign_Keys_For_Referenced_Table (S.Table_Id);
         Child_Schema : Database.Schema.Table_Schema;
         Child_Rows : Database.Foreign_Keys.Row_Vectors.Vector;
         R : Database.Status.Result;
      begin
         for FK of FKs loop
            R := Database.Catalog.Find_By_Id (FK.Referencing_Table, Child_Schema);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Child_Rows := Visible_Rows_For_Table (Tx, DB, FK.Referencing_Table);
            if FK.On_Delete = Database.Foreign_Keys.Restrict then
               R := Database.Foreign_Keys.Validate_Referenced_Delete
                 (FK, Child_Schema, S, Row, Child_Rows);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            elsif FK.On_Delete = Database.Foreign_Keys.Cascade then
               for Child of Child_Rows loop
                  if Database.Foreign_Keys.Rows_Match
                    (Child_Schema, Child, FK.Referencing_Cols, S, Row, FK.Referenced_Cols)
                  then
                     if Database.Backend (DB) = Database.Persistent_Backend then
                        declare
                           C : Database.Storage.Table_Heap.Heap_Cursor;
                           Scan_R : Database.Status.Result := Database.Storage.Table_Heap.Scan_First
                              (Tx,
                               DB.File,
                               Database.Storage.Pages.Page_Id (Child_Schema.Heap_First_Page),
                               Child_Schema,
                               C);
                        begin
                           while Database.Status.Is_Ok (Scan_R) and then C.Has_Row loop
                              if Database.Foreign_Keys.Rows_Match
                                (Child_Schema, C.Row, FK.Referencing_Cols, S, Row, FK.Referenced_Cols)
                              then
                                 Scan_R := Database.Storage.Table_Heap.Delete_At (Tx, DB.File, C);
                                 if not Database.Status.Is_Ok (Scan_R) then
                                    return Scan_R;
                                 end if;
                              end if;
                              Scan_R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Child_Schema, C);
                           end loop;
                           if not Database.Status.Is_Ok (Scan_R) then
                              return Scan_R;
                           end if;
                        end;
                     else
                        Database.Catalog.Remove_Row (FK.Referencing_Table, Child_Schema, Child);
                     end if;
                  end if;
               end loop;
            elsif FK.On_Delete = Database.Foreign_Keys.Set_Null then
               for Child of Child_Rows loop
                  if Database.Foreign_Keys.Rows_Match
                    (Child_Schema, Child, FK.Referencing_Cols, S, Row, FK.Referenced_Cols)
                  then
                     declare
                        New_Child : Database.Rows.Row := Child;
                     begin
                        Database.Foreign_Keys.Apply_Set_Null (FK, Child_Schema, New_Child);
                        R := Apply_Generated_And_Checks (Child_Schema, New_Child);
                        if not Database.Status.Is_Ok (R) then
                           return R;
                        end if;
                        if Database.Backend (DB) = Database.Persistent_Backend then
                           declare
                              First : Database.Storage.Pages.Page_Id  :=
                                Database.Storage.Pages.Page_Id (Child_Schema.Heap_First_Page);
                              Ref : Database.Indexes.Row_Reference;
                              Append_Result : Database.Status.Result;
                           begin
                              --  MVCC append-new-version/delete-old-version fallback.
                              --  Existing secondary indexes are rebuilt by integrity/vacuum tools.
                              Append_Result := Database.Storage.Table_Heap.Append_Row  (Tx,
                                DB.File,
                                DB.Page_Allocator,
                                First,
                                Child_Schema,
                                New_Child,
                                Ref);
                              if not Database.Status.Is_Ok (Append_Result) then
                                 return Append_Result;
                              end if;
                           end;
                        else
                           Database.Catalog.Replace_Row (FK.Referencing_Table, Child_Schema, Child, New_Child);
                        end if;
                     end;
                  end if;
               end loop;
            end if;
         end loop;
         return Database.Status.Success;
      end Apply_Referential_Delete_Actions;

      function Create_Index
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Name   : Wide_Wide_String;
         Column : Natural;
         Unique : Boolean := False) return Database.Status.Result is
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         Kind : Database.Types.Value_Kind := Database.Types.Null_Value;
         Root : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
         R : Database.Status.Result;
         C : Database.Storage.Table_Heap.Heap_Cursor;
         Existing : Database.Indexes.Row_Reference;
         IX : Database.Indexes.Index_Metadata;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         for Existing_IX of S.Indexes loop
            if Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Existing_IX.Name) = Name then
               return Database.Status.Failure (Database.Status.Already_Exists, "index name already exists");
            end if;
            if Existing_IX.Column_Id = Column and then Existing_IX.Unique = Unique then
               return Database.Status.Failure (Database.Status.Already_Exists, "duplicate index definition");
            end if;
         end loop;
         if not Column_Exists (S, Column, Kind) then
            return Database.Status.Failure (Database.Status.Invalid_Argument, "indexed column does not exist");
         end if;
         if not Database.Indexes.Supports_Key (Kind) then
            return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "unsupported index column type");
         end if;
         if Database.Backend (DB) = Database.Persistent_Backend then
            R := Database.Indexes.BTree.Create (Tx, DB.File, DB.Page_Allocator, Root);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            R := Database.Storage.Table_Heap.Scan_First  (DB.File,
              Database.Storage.Pages.Page_Id (S.Heap_First_Page),
              S,
              C);
            while Database.Status.Is_Ok (R) and then C.Has_Row loop
               declare K : constant Database.Values.Value := Index_Value  (S,
                 C.Row,
                 Column);
                 Ref : constant Database.Indexes.Row_Reference := (Page => C.Current_Page,
                 Slot_Offset => C.Slot_Offset);
                 begin
                  R := Database.Indexes.Validate_Secondary_Key (K);
                  if not Database.Status.Is_Ok (R) then
                     return R;
                  end if;
                  if K.Kind /= Database.Types.Null_Value then
                     if Unique then
                        R := Database.Indexes.BTree.Find (DB.File, Root, K, Existing);
                        if Database.Status.Is_Ok (R) then
                           return Database.Status.Failure (Database.Status.Duplicate_Key,
                             "duplicate value for unique index");
                        elsif R.Code /= Database.Status.Key_Not_Found then
                           return R;
                           end if;
                        R := Database.Indexes.BTree.Insert (Tx, DB.File, DB.Page_Allocator, Root, K, Ref);
                     else
                        R := Database.Indexes.BTree.Insert_Duplicate (Tx, DB.File, DB.Page_Allocator, Root, K, Ref);
                     end if;
                     if not Database.Status.Is_Ok (R) then
                        return R;
                     end if;
                  end if;
               end;
               R := Database.Storage.Table_Heap.Scan_Next (DB.File, S, C);
            end loop;
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end if;
         IX.Id := Database.Indexes.Index_Id (Natural (S.Indexes.Length) + 1);
         IX.Table_Id := S.Table_Id;
         IX.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Name);
         IX.Kind := (if Unique then Database.Indexes.Unique_Index else Database.Indexes.Secondary_Index);
         IX.Root_Page := Root;
         IX.Unique := Unique;
         IX.Column_Id := Column;
         IX.Key_Kind := Kind;
         S.Indexes.Append (IX);
         return Database.Catalog.Update_Table (DB, S);
      end Create_Index;

      function Rebuild_Index
        (Tx       : in out Database.Transactions.Transaction;
         DB       : in out Database.Handle;
         Schema   : Database.Schema.Table_Schema;
         Index_Id : Database.Indexes.Index_Id) return Database.Status.Result is
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         Target : Database.Indexes.Index_Metadata;
         Position : Natural := 0;
         Found : Boolean := False;
         Root : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
         R : Database.Status.Result;
         C : Database.Storage.Table_Heap.Heap_Cursor;
         Existing : Database.Indexes.Row_Reference;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         if S.Indexes.Length > 0 then
            for I in 0 .. Natural (S.Indexes.Length) - 1 loop
               if S.Indexes.Element (I).Id = Index_Id then
                  Target := S.Indexes.Element (I);
                  Position := I;
                  Found := True;
                  exit;
               end if;
            end loop;
         end if;
         if not Found then
            return Database.Status.Failure (Database.Status.Not_Found, "index not found");
         end if;
         if Database.Backend (DB) /= Database.Persistent_Backend then
            return Database.Status.Success;
         end if;
         R := Database.Indexes.BTree.Create (Tx, DB.File, DB.Page_Allocator, Root);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         R := Database.Storage.Table_Heap.Scan_First  (DB.File,
           Database.Storage.Pages.Page_Id (S.Heap_First_Page),
           S,
           C);
         while Database.Status.Is_Ok (R) and then C.Has_Row loop
            declare K : constant Database.Values.Value := Index_Value  (S,
              C.Row,
              Target.Column_Id);
              Ref : constant Database.Indexes.Row_Reference := (Page => C.Current_Page,
              Slot_Offset => C.Slot_Offset);
              begin
               if K.Kind /= Database.Types.Null_Value then
                  if Target.Unique then
                     R := Database.Indexes.BTree.Find (DB.File, Root, K, Existing);
                     if Database.Status.Is_Ok (R) then
                        return Database.Status.Failure (Database.Status.Duplicate_Key,
                          "duplicate value for unique index");
                     elsif R.Code /= Database.Status.Key_Not_Found then
                        return R;
                        end if;
                     R := Database.Indexes.BTree.Insert (Tx, DB.File, DB.Page_Allocator, Root, K, Ref);
                  else
                     R := Database.Indexes.BTree.Insert_Duplicate (Tx, DB.File, DB.Page_Allocator, Root, K, Ref);
                  end if;
                  if not Database.Status.Is_Ok (R) then
                     return R;
                  end if;
               end if;
            end;
            R := Database.Storage.Table_Heap.Scan_Next (DB.File, S, C);
         end loop;
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         Target.Root_Page := Root;
         S.Indexes.Replace_Element (Position, Target);
         return Database.Catalog.Update_Table (DB, S);
      end Rebuild_Index;

      function Create_Composite_Index
        (Tx      : in out Database.Transactions.Transaction;
         DB      : in out Database.Handle;
         Schema  : Database.Schema.Table_Schema;
         Name    : Wide_Wide_String;
         Columns : Database.Indexes.Column_Id_Vectors.Vector;
         Unique  : Boolean := False) return Database.Status.Result is
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         IX : Database.Indexes.Index_Metadata;
         Kind : Database.Types.Value_Kind := Database.Types.Null_Value;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         if Columns.Length = 0 then
            return Database.Status.Failure (Database.Status.Invalid_Argument,
              "composite index requires at least one column");
         end if;
         for C of Columns loop
            if not Column_Exists (S, C, Kind) then
               return Database.Status.Failure (Database.Status.Invalid_Argument,
                 "composite index column does not exist");
            end if;
            if not Database.Indexes.Supports_Key (Kind) then
               return Database.Status.Failure (Database.Status.Unsupported_Key_Type,
                 "unsupported composite index column type");
            end if;
         end loop;
         IX.Id := Database.Indexes.Index_Id (Natural (S.Indexes.Length) + 1);
         IX.Table_Id := S.Table_Id;
         IX.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Name);
         IX.Kind := (if Unique then Database.Indexes.Unique_Index else Database.Indexes.Secondary_Index);
         IX.Unique := Unique;
         IX.Column_Ids := Columns;
         IX.Column_Id := Columns.Element (0);
         IX.Key_Kind := Kind;
         S.Indexes.Append (IX);
         return Database.Catalog.Update_Table (DB, S);
      end Create_Composite_Index;

      function Create_Partial_Index
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Name      : Wide_Wide_String;
         Column    : Natural;
         Predicate : Database.Predicates.Predicate;
         Unique    : Boolean := False) return Database.Status.Result is
         pragma Unreferenced (Predicate);
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         IX : Database.Indexes.Index_Metadata;
         Kind : Database.Types.Value_Kind := Database.Types.Null_Value;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         if not Column_Exists (S, Column, Kind) then
            return Database.Status.Failure (Database.Status.Invalid_Argument, "partial index column does not exist");
         end if;
         if not Database.Indexes.Supports_Key (Kind) then
            return Database.Status.Failure (Database.Status.Unsupported_Key_Type,
              "unsupported partial index column type");
         end if;
         IX.Id := Database.Indexes.Index_Id (Natural (S.Indexes.Length) + 1);
         IX.Table_Id := S.Table_Id;
         IX.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Name);
         IX.Kind := Database.Indexes.Partial_Index;
         IX.Unique := Unique;
         IX.Column_Id := Column;
         IX.Key_Kind := Kind;
         IX.Has_Predicate := True;
         S.Indexes.Append (IX);
         return Database.Catalog.Update_Table (DB, S);
      end Create_Partial_Index;

      function Create_Expression_Index
        (Tx         : in out Database.Transactions.Transaction;
         DB         : in out Database.Handle;
         Schema     : Database.Schema.Table_Schema;
         Name       : Wide_Wide_String;
         Expression : Database.Expressions.Expression;
         Key_Kind   : Database.Types.Value_Kind;
         Unique     : Boolean := False) return Database.Status.Result is
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         IX : Database.Indexes.Index_Metadata;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         if not Database.Expressions.Is_Deterministic (Expression) then
            return Database.Status.Failure (Database.Status.Invalid_Argument,
              "expression index requires deterministic expression");
         end if;
         if not Database.Indexes.Supports_Key (Key_Kind) then
            return Database.Status.Failure (Database.Status.Unsupported_Key_Type,
              "unsupported expression index key type");
         end if;
         IX.Id := Database.Indexes.Index_Id (Natural (S.Indexes.Length) + 1);
         IX.Table_Id := S.Table_Id;
         IX.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Name);
         IX.Kind := Database.Indexes.Expression_Index;
         IX.Unique := Unique;
         IX.Key_Kind := Key_Kind;
         IX.Has_Expression := True;
         S.Indexes.Append (IX);
         return Database.Catalog.Update_Table (DB, S);
      end Create_Expression_Index;

      function Insert
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Item   : Row_Type) return Database.Status.Result is
         Row_Value : Database.Rows.Row := To_Row (Item);
         Stored_Item : Row_Type;
         V : Database.Status.Result;
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         First : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Page_Id (S.Heap_First_Page);
         Root  : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Page_Id (S.Primary_Index_Root);
         Key   : Database.Values.Value;
         Ref   : Database.Indexes.Row_Reference;
         Existing : Database.Indexes.Row_Reference;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         V := Apply_Generated_And_Checks (S, Row_Value);
         if not Database.Status.Is_Ok (V) then
            return V;
         end if;
         V := Database.Constraints.Validate_Row (S, Row_Value);
         if not Database.Status.Is_Ok (V) then
            return V;
         end if;
         V := Enforce_Foreign_Key_Insert_Update (Tx, DB, S, Row_Value);
         if not Database.Status.Is_Ok (V) then
            return V;
         end if;
         Stored_Item := From_Row (Row_Value);
         Key := Key_Value (Key_Of (Stored_Item));
         V := Database.Indexes.Validate_Key (Key);
         if not Database.Status.Is_Ok (V) then
            return V;
         end if;
         if Database.Backend (DB) = Database.Persistent_Backend then
            if Root = Database.Storage.Pages.Invalid_Page_Id then
               V := Database.Indexes.BTree.Create (Tx, DB.File, DB.Page_Allocator, Root);
               if not Database.Status.Is_Ok (V) then
                  return V;
               end if;
               S.Primary_Index_Root := Natural (Root);
               V := Database.Catalog.Update_Table (DB, S);
               if not Database.Status.Is_Ok (V) then
                  return V;
               end if;
            else
               if Any_Visible_Key (Tx, DB, S, Root, Key) then
                  return Database.Status.Failure (Database.Status.Duplicate_Key, "duplicate primary key");
               end if;
            end if;
            for IX of S.Indexes loop
               if IX.Unique then
                  declare K : constant Database.Values.Value := Index_Value  (S,
                    Row_Value,
                    IX.Column_Id);
                    Existing_Secondary : Database.Indexes.Row_Reference;
                    begin
                     V := Database.Indexes.Validate_Secondary_Key (K);
                     if not Database.Status.Is_Ok (V) then
                        return V;
                     end if;
                     if K.Kind /= Database.Types.Null_Value then
                        if Any_Visible_Key (Tx, DB, S, IX.Root_Page, K) then
                           return Database.Status.Failure (Database.Status.Duplicate_Key,
                             "duplicate value for unique index");
                        end if;
                     end if;
                  end;
               end if;
            end loop;
            V := Database.Storage.Table_Heap.Append_Row (Tx, DB.File, DB.Page_Allocator, First, S, Row_Value, Ref);
            if not Database.Status.Is_Ok (V) then
               return V;
            end if;
            if Natural (First) /= S.Heap_First_Page then
               S.Heap_First_Page := Natural (First);
               V := Database.Catalog.Update_Table (DB, S);
               if not Database.Status.Is_Ok (V) then
                  return V;
               end if;
            end if;
            V := Database.Indexes.BTree.Insert_Duplicate (Tx, DB.File, DB.Page_Allocator, Root, Key, Ref);
            if not Database.Status.Is_Ok (V) then
               return V;
            end if;
            for IX of S.Indexes loop
               declare K : constant Database.Values.Value := Index_Value  (S,
                 Row_Value,
                 IX.Column_Id);
                 Existing_Secondary : Database.Indexes.Row_Reference;
                 begin
                  V := Database.Indexes.Validate_Secondary_Key (K);
                  if not Database.Status.Is_Ok (V) then
                     return V;
                  end if;
                  if K.Kind /= Database.Types.Null_Value then
                     if IX.Unique then
                        if Any_Visible_Key (Tx, DB, S, IX.Root_Page, K) then
                           return Database.Status.Failure (Database.Status.Duplicate_Key,
                             "duplicate value for unique index");
                        end if;
                        declare
                           IX_Root : Database.Storage.Pages.Page_Id := IX.Root_Page;
                        begin
                           V := Database.Indexes.BTree.Insert_Duplicate (Tx, DB.File, DB.Page_Allocator, IX_Root,
                             K, Ref);
                        end;
                     else
                        declare
                           IX_Root : Database.Storage.Pages.Page_Id := IX.Root_Page;
                        begin
                           V := Database.Indexes.BTree.Insert_Duplicate (Tx, DB.File, DB.Page_Allocator, IX_Root,
                             K, Ref);
                        end;
                     end if;
                     if not Database.Status.Is_Ok (V) then
                        return V;
                     end if;
                  end if;
               end;
            end loop;
            if Natural (Root) /= S.Primary_Index_Root then
               S.Primary_Index_Root := Natural (Root);
               V := Database.Catalog.Update_Table (DB, S);
            end if;
            if Database.Status.Is_Ok (V) then
               Database.Catalog.Register_Row (S.Table_Id, Row_Value);
               Database.Full_Text.Maintain_Insert  (Tx,
                 S,
                 Natural (Database.Catalog.Rows_For_Table (S.Table_Id).Length),
                 Row_Value);
            end if;
            return V;
         else
            for Existing_Item of Memory loop
               if Visible_To (Tx, Existing_Item)
                 and then Key_Of (Existing_Item.Item) = Key_Of (Stored_Item)
               then
                  return Database.Status.Failure (Database.Status.Duplicate_Key, "duplicate primary key");
               end if;
            end loop;
            Memory.Append
              (Versioned_Row'
                 (Item     => Stored_Item,
                  Metadata => Database.Versioning.New_Uncommitted
                    (Database.Transactions.Id (Tx), Future_Commit_Version (DB))));
            Database.Catalog.Register_Row (S.Table_Id, Row_Value);
            Database.Full_Text.Maintain_Insert  (Tx,
              S,
              Natural (Database.Catalog.Rows_For_Table (S.Table_Id).Length),
              Row_Value);
            return Database.Status.Success;
         end if;
      end Insert;

      function Find
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Key    : Key_Type;
         Item   : out Row_Type) return Database.Status.Result is
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         Key_Value_For_Find : constant Database.Values.Value := Key_Value (Key);
         Ref : Database.Indexes.Row_Reference;
         Row_Value : Database.Rows.Row;
         R : Database.Status.Result;
      begin
         if not Read_Tx_Ok (Tx) then
            return Database.Status.Failure (Database.Status.Transaction_Error, "transaction required");
         end if;
         if Database.Schema.Primary_Key_Index (S) = Natural'Last then
            return Database.Status.Failure (Database.Status.Schema_Mismatch, "missing primary key");
         end if;
         if Database.Backend (DB) = Database.Persistent_Backend then
            if S.Primary_Index_Root = 0 then
               return Database.Status.Failure (Database.Status.Not_Found, "row not found");
            end if;
            R := Visible_Ref_For_Key
              (Tx, DB, S, Database.Storage.Pages.Page_Id (S.Primary_Index_Root),
               Key_Value_For_Find, Ref);
            if not Database.Status.Is_Ok (R) then
               if R.Code = Database.Status.Not_Found or else R.Code = Database.Status.Key_Not_Found then
                  return Database.Status.Failure (Database.Status.Not_Found, "row not found");
               end if;
               return R;
            end if;
            R := Database.Storage.Table_Heap.Read_At (Tx, DB.File, Ref, S, Row_Value);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Item := From_Row (Row_Value);
            return Database.Status.Success;
         else
            for Existing_Item of Memory loop
               if Visible_To (Tx, Existing_Item)
                 and then Key_Of (Existing_Item.Item) = Key
               then
                  Item := Existing_Item.Item;
                  return Database.Status.Success;
               end if;
            end loop;
            return Database.Status.Failure (Database.Status.Not_Found, "row not found");
         end if;
      end Find;

      function Delete
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Key    : Key_Type) return Database.Status.Result is
         S : Database.Schema.Table_Schema := Current_Schema (DB, Schema);
         K : constant Database.Values.Value := Key_Value (Key);
         Ref : Database.Indexes.Row_Reference;
         C : Database.Storage.Table_Heap.Heap_Cursor;
         Row_Value : Database.Rows.Row;
         R : Database.Status.Result;
      begin
         if not Write_Tx_Ok (Tx) then
            return Read_Only_Write_Error;
         end if;
         if Database.Backend (DB) = Database.Persistent_Backend then
            if S.Primary_Index_Root = 0 then
               return Database.Status.Failure (Database.Status.Not_Found, "row not found");
            end if;
            R := Visible_Ref_For_Key
              (Tx, DB, S, Database.Storage.Pages.Page_Id (S.Primary_Index_Root), K, Ref);
            if not Database.Status.Is_Ok (R) then
               if R.Code = Database.Status.Key_Not_Found or else R.Code = Database.Status.Not_Found then
                  return Database.Status.Failure (Database.Status.Not_Found, "row not found");
               end if;
               return R;
            end if;
            R := Database.Storage.Table_Heap.Read_At (Tx, DB.File, Ref, S, Row_Value);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            R := Apply_Referential_Delete_Actions (Tx, DB, S, Row_Value);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            C := (Current_Page => Ref.Page, Slot_Offset => Ref.Slot_Offset, Has_Row => True, Row => Row_Value);
            R := Database.Storage.Table_Heap.Delete_At (Tx, DB.File, C);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Database.Full_Text.Maintain_Delete (Tx, S, Row_Value);
            Database.Catalog.Remove_Row (S.Table_Id, S, Row_Value);
            return Database.Status.Success;
         else
            if Memory.Length > 0 then
               for I in 0 .. Natural (Memory.Length) - 1 loop
                  declare
                     Existing_Item : Versioned_Row := Memory.Element (I);
                  begin
                     if Visible_To (Tx, Existing_Item)
                       and then Key_Of (Existing_Item.Item) = Key
                     then
                        Row_Value := To_Row (Existing_Item.Item);
                        R := Apply_Referential_Delete_Actions (Tx, DB, S, Row_Value);
                        if not Database.Status.Is_Ok (R) then
                           return R;
                        end if;
                        Database.Versioning.Mark_Deleted
                          (Existing_Item.Metadata,
                           Database.Transactions.Id (Tx),
                           Future_Commit_Version (DB));
                        Memory.Replace_Element (I, Existing_Item);
                        Database.Full_Text.Maintain_Delete (Tx, S, Row_Value);
                        Database.Catalog.Remove_Row (S.Table_Id, S, Row_Value);
                        return Database.Status.Success;
                     end if;
                  end;
               end loop;
            end if;
            return Database.Status.Failure (Database.Status.Not_Found, "row not found");
         end if;
      end Delete;

      function Update
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Item   : Row_Type) return Database.Status.Result is
         R : Database.Status.Result;
      begin
         R := Delete (Tx, DB, Schema, Key_Of (Item));
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         return Insert (Tx, DB, Schema, Item);
      end Update;

      function Scan
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         C : out Cursor) return Database.Status.Result is
         R : Database.Status.Result;
      begin
         if not Read_Tx_Ok (Tx) then
            return Database.Status.Failure (Database.Status.Transaction_Error, "transaction required");
         end if;
         C.Has_Current := False;
         C.Owner_Tx_Id := Database.Transactions.Id (Tx);
         C.Owner_Snapshot := Database.Transactions.Snapshot_Version (Tx);
         C.In_Memory_Index := 0;
         C.In_Memory_Rows.Clear;
         C.Uses_Materialized := False;
         if Database.Backend (DB) = Database.Persistent_Backend then
            declare
               S : constant Database.Schema.Table_Schema := Current_Schema (DB, Schema);
            begin
               R := Populate_From_Index (Tx, DB, S, Predicate, C);
               if Database.Status.Is_Ok (R) and then C.Uses_Materialized then
                  return Database.Status.Success;
               elsif C.Uses_Materialized then
                  return R;
               end if;
            end;
            R := Database.Storage.Table_Heap.Scan_First  (Tx,
              DB.File,
              Database.Storage.Pages.Page_Id (Current_Schema (DB,
              Schema).Heap_First_Page),
              Current_Schema (DB,
              Schema),
              C.Heap);
            while Database.Status.Is_Ok (R) and then C.Heap.Has_Row loop
               if Database.Predicates.Matches (Predicate, C.Heap.Row) then
                  C.Current := From_Row (C.Heap.Row);
                  C.Has_Current := True;
                  return Database.Status.Success;
               end if;
               R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Current_Schema (DB, Schema), C.Heap);
            end loop;
            return R;
         else
            for Item of Memory loop
               if Visible_To (Tx, Item)
                 and then Database.Predicates.Matches (Predicate, To_Row (Item.Item))
               then
                  C.In_Memory_Rows.Append (Item.Item);
               end if;
            end loop;
            if C.In_Memory_Rows.Length > 0 then
               C.Current := C.In_Memory_Rows.Element (0);
               C.Has_Current := True;
            end if;
            return Database.Status.Success;
         end if;
      end Scan;

      function Scan_Query
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         Query     : out Database.Queries.Query) return Database.Status.Result is
         C : Cursor;
         R : Database.Status.Result;
      begin
         Query := Database.Queries.Empty;
         R := Scan (Tx, DB, Schema, Predicate, C);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         while Has_Element (C) loop
            Database.Queries.Append (Query, To_Row (Element (C)));
            R := Next (Tx, DB, Schema, Predicate, C);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end loop;
         return Database.Status.Success;
      end Scan_Query;

      function Has_Element (C : Cursor) return Boolean is (C.Has_Current);
      function Element (C : Cursor) return Row_Type is (C.Current);

      function Next
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         C : in out Cursor) return Database.Status.Result is
         R : Database.Status.Result;
      begin
         if not Read_Tx_Ok (Tx) then
            return Database.Status.Failure (Database.Status.Transaction_Error, "transaction required");
         end if;
         declare
            State : constant Database.Cursors.Cursor_State  :=
              Database.Cursors.Validate_Owner
                (Tx, C.Owner_Tx_Id, C.Owner_Snapshot, True);
         begin
            if not Database.Cursors.Is_Valid (State) then
               return Database.Cursors.To_Result (State);
            end if;
         end;
         C.Has_Current := False;
         if Database.Backend (DB) = Database.Persistent_Backend and then not C.Uses_Materialized then
            R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Current_Schema (DB, Schema), C.Heap);
            while Database.Status.Is_Ok (R) and then C.Heap.Has_Row loop
               if Database.Predicates.Matches (Predicate, C.Heap.Row) then
                  C.Current := From_Row (C.Heap.Row);
                  C.Has_Current := True;
                  return Database.Status.Success;
               end if;
               R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Current_Schema (DB, Schema), C.Heap);
            end loop;
            return R;
         else
            C.In_Memory_Index := C.In_Memory_Index + 1;
            if C.In_Memory_Index < Natural (C.In_Memory_Rows.Length) then
               C.Current := C.In_Memory_Rows.Element (C.In_Memory_Index);
               C.Has_Current := True;
            end if;
            return Database.Status.Success;
         end if;
      end Next;
   end Typed;
end Database.Tables;
