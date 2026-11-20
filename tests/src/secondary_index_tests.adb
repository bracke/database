with Ada.Characters.Conversions;
with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Catalog;
with Database.Check;
with Database.Diagnostics;
with Database.Indexes.BTree;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Status; use Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Vacuum;
with Database.Values;

package body Secondary_Index_Tests is
   use AUnit.Assertions;

   type User_Row is record
      Id    : Integer;
      Name  : Wide_Wide_String (1 .. 16);
      Email : Wide_Wide_String (1 .. 24);
      Age   : Integer;
   end record;

   function To_Row (U : User_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (U.Id));
      Database.Rows.Append (R, Database.Values.From_Text (U.Name));
      Database.Rows.Append (R, Database.Values.From_Text (U.Email));
      Database.Rows.Append (R, Database.Values.From_Integer (U.Age));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return User_Row is
      use Ada.Strings.Wide_Wide_Unbounded;
      N : Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      E : Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 2).Text);
      U : User_Row :=
        (Id    => Database.Rows.Get (R, 0).Int,
         Name  => (others => ' '),
         Email => (others => ' '),
         Age   => Database.Rows.Get (R, 3).Int);
   begin
      for I in 1 .. Integer'Min (16, N'Length) loop
         U.Name (I) := N (N'First + I - 1);
      end loop;
      for I in 1 .. Integer'Min (24, E'Length) loop
         U.Email (I) := E (E'First + I - 1);
      end loop;
      return U;
   end From_Row;

   function Key_Of (U : User_Row) return Integer
   is (U.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));
   package Users is new
     Database.Tables.Typed
       (User_Row,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("secondary and unique indexes");
   end Name;

   procedure Add_User_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (S, "email", Database.Types.Text_Value, True);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
   end Add_User_Schema;

   procedure Create_Secondary_And_Unique_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      Path : constant Wide_Wide_String := "secondary_metadata.database";
   begin
      if Ada.Directories.Exists ("secondary_metadata.database") then
         Ada.Directories.Delete_File ("secondary_metadata.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      Assert (Database.Status.Is_Ok (R), "create unique index failed");
      R := Users.Create_Index (Tx, DB, S, "age_index", 3, False);
      Assert (Database.Status.Is_Ok (R), "create secondary index failed");
      R := Users.Create_Index (Tx, DB, S, "age_index", 3, False);
      Assert
        (R.Code = Database.Status.Already_Exists,
         "duplicate index name accepted");
      R := Users.Create_Index (Tx, DB, S, "bad_column", 99, False);
      Assert
        (R.Code = Database.Status.Invalid_Argument,
         "invalid index column accepted");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "reopen failed");
      R := Database.Catalog.Find_By_Name
             (Database.Catalog_State_Key (DB), "users", S);
      Assert (Database.Status.Is_Ok (R), "catalog read failed");
      Assert
        (Natural (S.Indexes.Length) = 2,
         "secondary index metadata was not persisted");
      Database.Close (DB);
      if Ada.Directories.Exists ("secondary_metadata.database") then
         Ada.Directories.Delete_File ("secondary_metadata.database");
      end if;
   end Create_Secondary_And_Unique_Metadata;

   procedure Unique_And_Non_Unique_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      Tx    : Database.Transactions.Transaction;
      S     : Database.Schema.Table_Schema;
      R     : Database.Status.Result;
      U1    : User_Row :=
        (Id    => 1,
         Name  => "Bent            ",
         Email => "bent@example.test       ",
         Age   => 42);
      U2    : User_Row :=
        (Id    => 2,
         Name  => "Aage            ",
         Email => "aage@example.test       ",
         Age   => 42);
      U3    : User_Row :=
        (Id    => 3,
         Name  => "Dup             ",
         Email => "bent@example.test       ",
         Age   => 43);
      C     : Users.Cursor;
      Count : Natural := 0;
      Path  : constant Wide_Wide_String := "secondary_behavior.database";
   begin
      if Ada.Directories.Exists ("secondary_behavior.database") then
         Ada.Directories.Delete_File ("secondary_behavior.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      Assert (Database.Status.Is_Ok (R), "unique index create failed");
      R := Users.Create_Index (Tx, DB, S, "age_index", 3, False);
      Assert (Database.Status.Is_Ok (R), "secondary index create failed");
      R := Users.Insert (Tx, DB, S, U1);
      Assert (Database.Status.Is_Ok (R), "insert U1 failed");
      R := Users.Insert (Tx, DB, S, U2);
      Assert (Database.Status.Is_Ok (R), "non-unique duplicate age rejected");
      R := Users.Insert (Tx, DB, S, U3);
      Assert
        (R.Code = Database.Status.Duplicate_Key,
         "duplicate unique email accepted");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "reopen failed");
      R := Database.Catalog.Find_By_Name
             (Database.Catalog_State_Key (DB), "users", S);
      Assert (Database.Status.Is_Ok (R), "catalog reopen failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Users.Scan
          (Tx,
           DB,
           S,
           Database.Predicates.Column_Equals
             (3, Database.Values.From_Integer (42)),
           C);
      Assert (Database.Status.Is_Ok (R), "age scan failed");
      while Users.Has_Element (C) loop
         Count := Count + 1;
         R :=
           Users.Next
             (Tx,
              DB,
              S,
              Database.Predicates.Column_Equals
                (3, Database.Values.From_Integer (42)),
              C);
         Assert (Database.Status.Is_Ok (R), "age scan next failed");
      end loop;
      Assert
        (Count = 2,
         "non-unique indexed values were not preserved across reopen");
      R := Users.Delete (Tx, DB, S, 1);
      Assert (Database.Status.Is_Ok (R), "delete indexed row failed");
      R := Users.Insert (Tx, DB, S, U3);
      Assert
        (Database.Status.Is_Ok (R),
         "unique secondary entry was not removed on delete");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
      if Ada.Directories.Exists ("secondary_behavior.database") then
         Ada.Directories.Delete_File ("secondary_behavior.database");
      end if;
   end Unique_And_Non_Unique_Behavior;

   procedure Rebuild_Existing_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      U1   : User_Row :=
        (Id    => 1,
         Name  => "Bent            ",
         Email => "bent@example.test       ",
         Age   => 42);
      Path : constant Wide_Wide_String := "secondary_rebuild.database";
   begin
      if Ada.Directories.Exists ("secondary_rebuild.database") then
         Ada.Directories.Delete_File ("secondary_rebuild.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, U1);
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      Assert
        (Database.Status.Is_Ok (R), "create index over existing row failed");
      R := Database.Catalog.Find_By_Name
             (Database.Catalog_State_Key (DB), "users", S);
      Assert (Database.Status.Is_Ok (R), "catalog refresh failed");
      R := Users.Rebuild_Index (Tx, DB, S, S.Indexes.Element (0).Id);
      Assert (Database.Status.Is_Ok (R), "rebuild failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
      if Ada.Directories.Exists ("secondary_rebuild.database") then
         Ada.Directories.Delete_File ("secondary_rebuild.database");
      end if;
   end Rebuild_Existing_Index;

   --  Numbered test users: a unique email per row and one of 50 ages.
   function Numbered (Id : Integer) return User_Row is
      Image : constant Wide_Wide_String := Integer'Wide_Wide_Image (Id);
      Email : Wide_Wide_String (1 .. 24) := (others => ' ');
      Text  : constant Wide_Wide_String := "user" & Image (Image'First + 1 .. Image'Last) & "@example.test";
   begin
      Email (1 .. Text'Length) := Text;
      return (Id => Id, Name => "Numbered        ", Email => Email, Age => Id mod 50);
   end Numbered;

   function Count_Where
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      S      : Database.Schema.Table_Schema;
      Column : Natural;
      Value  : Database.Values.Value) return Natural
   is
      Predicate : constant Database.Predicates.Predicate := Database.Predicates.Column_Equals (Column, Value);
      C         : Users.Cursor;
      Count     : Natural := 0;
      R         : Database.Status.Result := Users.Scan (Tx, DB, S, Predicate, C);
   begin
      Assert (Database.Status.Is_Ok (R), "indexed scan failed");
      while Users.Has_Element (C) loop
         Count := Count + 1;
         R := Users.Next (Tx, DB, S, Predicate, C);
         Assert (Database.Status.Is_Ok (R), "indexed scan next failed");
      end loop;
      return Count;
   end Count_Where;

   --  Inspect a closed database's index through its file, opened read-only.
   function Index_Pages (Path : Wide_Wide_String; Root : Database.Storage.Pages.Page_Id) return Natural is
      F     : Database.Storage.File_IO.File_Handle;
      Pages : Database.Indexes.BTree.Page_Id_Vectors.Vector;
      R     : Database.Status.Result := Database.Storage.File_IO.Open_Read_Only (F, Path);
   begin
      Assert (Database.Status.Is_Ok (R), "read-only open failed");
      R := Database.Indexes.BTree.Pages_Of (F, Root, Pages);
      Assert (Database.Status.Is_Ok (R), "index pages unreadable");
      R := Database.Storage.File_IO.Close (F);
      return Natural (Pages.Length);
   end Index_Pages;

   function Built (Path : Wide_Wide_String; Root : Database.Storage.Pages.Page_Id) return Boolean is
      F      : Database.Storage.File_IO.File_Handle;
      R      : Database.Status.Result := Database.Storage.File_IO.Open_Read_Only (F, Path);
      Result : Boolean;
   begin
      Assert (Database.Status.Is_Ok (R), "read-only open failed");
      Result := Database.Indexes.BTree.Is_Built (F, Root);
      R := Database.Storage.File_IO.Close (F);
      return Result;
   end Built;

   --  Count the primary index's entries within Low .. High, through the closed database's file.
   function Range_Count
     (Path      : Wide_Wide_String;
      Root      : Database.Storage.Pages.Page_Id;
      Low, High : Database.Indexes.BTree.Range_Bound;
      Code      : out Database.Status.Status_Code) return Natural
   is
      F    : Database.Storage.File_IO.File_Handle;
      Refs : Database.Indexes.BTree.Row_Reference_Vectors.Vector;
      R    : Database.Status.Result := Database.Storage.File_IO.Open_Read_Only (F, Path);
   begin
      Assert (Database.Status.Is_Ok (R), "read-only open failed");
      R := Database.Indexes.BTree.Range_Find (F, Root, Low, High, Refs);
      Code := R.Code;
      R := Database.Storage.File_IO.Close (F);
      return Natural (Refs.Length);
   end Range_Count;

   function Valid (Path : Wide_Wide_String; Root : Database.Storage.Pages.Page_Id) return Boolean is
      F      : Database.Storage.File_IO.File_Handle;
      R      : Database.Status.Result := Database.Storage.File_IO.Open_Read_Only (F, Path);
      Result : Boolean;
   begin
      Assert (Database.Status.Is_Ok (R), "read-only open failed");
      Result := Database.Status.Is_Ok (Database.Indexes.BTree.Validate (F, Root));
      R := Database.Storage.File_IO.Close (F);
      return Result;
   end Valid;

   procedure Expect_Healthy (DB : in out Database.Handle; Message : String) is
      Tx : Database.Transactions.Transaction;
      CR : Database.Check.Check_Result;
      R  : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (DB, Tx);
      CR := Database.Check.Check_Database (Tx);
      Assert (CR.Success, Message & (if CR.Success then "" else ": " & Database.Check.Check_Error_Kind'Image
                (CR.Errors.First_Element.Kind) & " " & Ada.Characters.Conversions.To_String
                  (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (CR.Errors.First_Element.Message)) &
                Database.Storage.Pages.Page_Id'Image (CR.Errors.First_Element.Page)));
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");
   end Expect_Healthy;

   procedure Remove_Files (Name : String) is
      procedure Remove (File : String) is
      begin
         if Ada.Directories.Exists (File) then
            Ada.Directories.Delete_File (File);
         end if;
      end Remove;
   begin
      Remove (Name);
      Remove (Name & ".wal");
      Remove (Name & ".fts");
   end Remove_Files;

   --  Thousands of rows split every index into several pages; lookups, duplicates, and deletes stay exact after the
   --  database is reopened, and every index page is reachable.
   procedure Persistent_Tree_Across_Reopen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name  : constant String := "secondary_tree.database";
      Path  : constant Wide_Wide_String := "secondary_tree.database";
      Rows  : constant := 4_000;
      DB    : Database.Handle;
      Tx    : Database.Transactions.Transaction;
      S     : Database.Schema.Table_Schema;
      R     : Database.Status.Result;
   begin
      Remove_Files (Name);
      Database.Create (DB, Path);
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      Assert (Database.Status.Is_Ok (R), "unique index create failed");
      R := Users.Create_Index (Tx, DB, S, "age_index", 3, False);
      Assert (Database.Status.Is_Ok (R), "secondary index create failed");
      R := Database.Transactions.Commit (Tx);
      for Batch in 0 .. Rows / 500 - 1 loop
         Database.Transactions.Begin_Write (DB, Tx);
         for Id in Batch * 500 + 1 .. Batch * 500 + 500 loop
            R := Users.Insert (Tx, DB, S, Numbered (Id));
            Assert (Database.Status.Is_Ok (R), "insert failed");
         end loop;
         R := Database.Transactions.Commit (Tx);
         Assert (Database.Status.Is_Ok (R), "commit failed");
      end loop;
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Database.Close (DB);
      Assert (Index_Pages (Path, Database.Storage.Pages.Page_Id (S.Primary_Index_Root)) > 2,
              "the primary index spans several pages");
      for IX of S.Indexes loop
         Assert (Index_Pages (Path, IX.Root_Page) > 2, "each secondary index spans several pages");
         Assert (Valid (Path, IX.Root_Page), "each secondary index is structurally valid");
      end loop;
      declare
         use Database.Indexes.BTree;
         Root : constant Database.Storage.Pages.Page_Id := Database.Storage.Pages.Page_Id (S.Primary_Index_Root);
         Code : Database.Status.Status_Code;
      begin
         Assert (Valid (Path, Root), "the primary index is structurally valid");
         Assert (Range_Count (Path, Root, (Exclusive, Database.Values.From_Integer (100)),
                              (Inclusive, Database.Values.From_Integer (2_100)), Code) = 2_000
                 and then Code = Database.Status.Ok, "a bounded range crosses leaves");
         Assert (Range_Count (Path, Root, (Kind => Unbounded, others => <>),
                              (Exclusive, Database.Values.From_Integer (11)), Code) = 10
                 and then Code = Database.Status.Ok, "an exclusive upper bound stops before its key");
         Assert (Range_Count (Path, Root, (Kind => Unbounded, others => <>),
                              (Inclusive, Database.Values.From_Text ("x")), Code) = 0
                 and then Code = Database.Status.Unsupported_Key_Type,
                 "a bound that cannot be compared with the keys is an error, not an empty range");
      end;

      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Assert (Database.Status.Is_Ok (R), "catalog reopen failed");
      Expect_Healthy (DB, "a large indexed table passes the integrity check");
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 3, Database.Values.From_Integer (7)) = Rows / 50,
              "a non-unique key spans leaves after reopen");
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (3_999).Email)) = 1,
              "a unique key is found after reopen");
      R := Users.Insert (Tx, DB, S, (Numbered (2_000) with delta Id => Rows + 1));
      Assert (R.Code = Database.Status.Duplicate_Key, "a duplicate unique key is rejected after reopen");
      for Id in 1 .. Rows loop
         if Id mod 50 = 7 then
            R := Users.Delete (Tx, DB, S, Id);
            Assert (Database.Status.Is_Ok (R), "delete failed");
         end if;
      end loop;
      Assert (Count_Where (Tx, DB, S, 3, Database.Values.From_Integer (7)) = 0, "deleted rows are gone");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "delete commit failed");
      Expect_Healthy (DB, "the table passes the integrity check after deletes");

      --  A rebuild empties the tree in place and frees its other pages, which the next rebuild reuses.
      declare
         Root  : constant Database.Storage.Pages.Page_Id := S.Indexes.Element (0).Root_Page;
         Pages : Natural := 0;
      begin
         for Round in 1 .. 2 loop
            Database.Transactions.Begin_Write (DB, Tx);
            R := Users.Rebuild_Index (Tx, DB, S, S.Indexes.Element (0).Id);
            Assert (Database.Status.Is_Ok (R), "rebuild failed");
            if Round = 2 then
               Assert (Database.Diagnostics.Page_Count (Tx) = Pages, "a rebuild reuses the pages it freed");
            end if;
            Pages := Database.Diagnostics.Page_Count (Tx);
            R := Database.Transactions.Commit (Tx);
            Assert (Database.Status.Is_Ok (R), "rebuild commit failed");
         end loop;
         R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
         Assert (S.Indexes.Element (0).Root_Page = Root, "a rebuild keeps the index root");
      end;
      Expect_Healthy (DB, "a rebuilt index leaves no orphan pages");
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (3_999).Email)) = 1,
              "the rebuilt index finds its rows");
      R := Database.Transactions.Commit (Tx);
      Database.Close (DB);
      Remove_Files (Name);
   end Persistent_Tree_Across_Reopen;

   --  An index whose root page was allocated but never written, as earlier versions left every index, is bypassed
   --  by lookups and rebuilt from the table by the next change.
   procedure Unbuilt_Index_Is_Rebuilt
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name : constant String := "secondary_unbuilt.database";
      Path : constant Wide_Wide_String := "secondary_unbuilt.database";
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      Root : Database.Storage.Pages.Page_Id;
   begin
      Remove_Files (Name);
      Database.Create (DB, Path);
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      --  Few enough rows for the index to fit its root, as an earlier version's index root never had children.
      for Id in 1 .. 50 loop
         R := Users.Insert (Tx, DB, S, Numbered (Id));
         Assert (Database.Status.Is_Ok (R), "insert failed");
      end loop;
      R := Database.Transactions.Commit (Tx);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Root := S.Indexes.Element (0).Root_Page;
      Database.Close (DB);
      --  Leave the root as an earlier version did: an allocated, never written leaf page.
      declare
         F    : Database.Storage.File_IO.File_Handle;
         Page : Database.Storage.Pages.Page;
      begin
         R := Database.Storage.File_IO.Open (F, Path);
         Database.Storage.Pages.Initialize (Page, Root, Database.Storage.Pages.BTree_Leaf_Page);
         R := Database.Storage.File_IO.Write_Page (F, Page);
         Assert (Database.Status.Is_Ok (R), "root reset failed");
         R := Database.Storage.File_IO.Close (F);
      end;

      Assert (not Built (Path, Root), "the index starts unbuilt");
      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (30).Email)) = 1,
              "a lookup in an unbuilt index scans the table");
      R := Users.Insert (Tx, DB, S, (Numbered (30) with delta Id => 1_000));
      Assert (R.Code = Database.Status.Duplicate_Key,
              "an unbuilt unique index still rejects a duplicate of the indexed column");
      for Id in 51 .. 450 loop
         R := Users.Insert (Tx, DB, S, Numbered (Id));
         Assert (Database.Status.Is_Ok (R), "insert after reopen failed");
      end loop;
      R := Database.Transactions.Commit (Tx);
      Database.Close (DB);
      Assert (Built (Path, Root), "the next change rebuilt the index");
      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (30).Email)) = 1,
              "the rebuilt index holds the earlier rows");
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (400).Email)) = 1,
              "and the later ones");
      R := Database.Transactions.Commit (Tx);
      Expect_Healthy (DB, "a rebuilt index passes the integrity check");
      Database.Close (DB);
      Remove_Files (Name);
   end Unbuilt_Index_Is_Rebuilt;

   --  Index pages change with their transaction: a rolled-back insert leaves no index entry behind.
   procedure Rollback_Restores_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name : constant String := "secondary_rollback.database";
      Path : constant Wide_Wide_String := "secondary_rollback.database";
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
   begin
      Remove_Files (Name);
      Database.Create (DB, Path);
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      R := Users.Insert (Tx, DB, S, Numbered (1));
      R := Database.Transactions.Commit (Tx);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, Numbered (2));
      Assert (Database.Status.Is_Ok (R), "insert before rollback failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (2).Email)) = 0,
              "a rolled-back row is not found through the index");
      R := Users.Insert (Tx, DB, S, (Numbered (2) with delta Id => 3));
      Assert (Database.Status.Is_Ok (R), "a rolled-back key can be used again");
      R := Database.Transactions.Commit (Tx);
      Expect_Healthy (DB, "the database passes the integrity check after a rollback");
      Database.Close (DB);
      Remove_Files (Name);
   end Rollback_Restores_Index;

   --  A rollback undoes catalog changes and returns the pages the transaction allocated, so the next transaction
   --  extends the file without a gap.
   procedure Rollback_Restores_Catalog
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name : constant String := "secondary_rollback_catalog.database";
      Path : constant Wide_Wide_String := "secondary_rollback_catalog.database";
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
   begin
      Remove_Files (Name);
      Database.Create (DB, Path);
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "email_unique", 2, True);
      R := Users.Insert (Tx, DB, S, Numbered (1));
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "setup commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "age_index", 3, False);
      Assert (Database.Status.Is_Ok (R), "index create failed");
      for Id in 2 .. 600 loop
         R := Users.Insert (Tx, DB, S, Numbered (Id));
         Assert (Database.Status.Is_Ok (R), "insert failed");
      end loop;
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Assert (Natural (S.Indexes.Length) = 1, "a rolled-back index is not in the catalog");
      Expect_Healthy (DB, "a rollback leaves no orphan or missing pages");

      Database.Transactions.Begin_Write (DB, Tx);
      for Id in 2 .. 600 loop
         R := Users.Insert (Tx, DB, S, Numbered (Id));
         Assert (Database.Status.Is_Ok (R), "insert after rollback failed");
      end loop;
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit after rollback failed");
      Expect_Healthy (DB, "pages allocated after a rollback continue the file");
      Database.Close (DB);
      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 2, Database.Values.From_Text (Numbered (450).Email)) = 1,
              "rows inserted after the rollback are indexed");
      R := Database.Transactions.Commit (Tx);
      Database.Close (DB);
      Remove_Files (Name);
   end Rollback_Restores_Catalog;

   --  A table registered in a rolled-back transaction leaves neither a catalog entry nor a page behind, whether or
   --  not the transaction wrote rows first; a committed registration survives a reopen.
   procedure Rollback_Removes_Registration
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name   : constant String := "secondary_rollback_register.database";
      Path   : constant Wide_Wide_String := "secondary_rollback_register.database";
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      S      : Database.Schema.Table_Schema;
      Orders : Database.Schema.Table_Schema;
      Found  : Database.Schema.Table_Schema;
      R      : Database.Status.Result;

      procedure New_Orders is
      begin
         Orders := (others => <>);
         Add_User_Schema (Orders);
         Orders.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("orders");
      end New_Orders;
   begin
      Remove_Files (Name);
      Database.Create (DB, Path);
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register without a transaction failed");

      for Writes_First in Boolean loop
         New_Orders;
         Database.Transactions.Begin_Write (DB, Tx);
         if Writes_First then
            R := Users.Insert (Tx, DB, S, Numbered (1));
            Assert (Database.Status.Is_Ok (R), "insert failed");
         end if;
         R := Users.Register (Tx, DB, Orders);
         Assert (Database.Status.Is_Ok (R), "register in a transaction failed");
         R := Database.Transactions.Rollback (Tx);
         Assert (Database.Status.Is_Ok (R), "rollback failed");
         R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "orders", Found);
         Assert (R.Code = Database.Status.Not_Found, "a rolled-back table is not in the catalog");
         Expect_Healthy (DB, "a rolled-back registration leaves no orphan page");
      end loop;

      New_Orders;
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Register (Tx, DB, Orders);
      Assert (Database.Status.Is_Ok (R), "register in a transaction failed");
      R := Users.Insert (Tx, DB, Orders, Numbered (7));
      Assert (Database.Status.Is_Ok (R), "insert into the new table failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "orders", Found);
      Assert (Database.Status.Is_Ok (R), "a committed table survives a reopen");
      Expect_Healthy (DB, "a committed registration is consistent after a reopen");
      Database.Close (DB);

      --  Checking a registered table is a lookup, which a read-only handle allows.
      Database.Open_Read_Only (DB, Path);
      New_Orders;
      R := Users.Register (DB, Orders);
      Assert (Database.Status.Is_Ok (R), "a registered table is checked through a read-only handle");
      Assert (Orders.Heap_First_Page = Found.Heap_First_Page, "the check returns the registered schema");
      Database.Close (DB);
      Remove_Files (Name);
   end Rollback_Removes_Registration;

   --  A tree deeper than any real one is reported as corrupt rather than walked, and rebuilding the index replaces it.
   procedure Corrupt_Tree_Is_Replaced
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.Storage.Pages.Page_Id;
      Name  : constant String := "secondary_corrupt_tree.database";
      Path  : constant Wide_Wide_String := "secondary_corrupt_tree.database";
      Depth : constant := 70;
      DB    : Database.Handle;
      Tx    : Database.Transactions.Transaction;
      S     : Database.Schema.Table_Schema;
      Root  : Database.Storage.Pages.Page_Id;
      R     : Database.Status.Result;
   begin
      Remove_Files (Name);
      Database.Create (DB, Path);
      Add_User_Schema (S);
      R := Users.Register (DB, S);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Create_Index (Tx, DB, S, "age_index", 3, False);
      for Id in 1 .. 20 loop
         R := Users.Insert (Tx, DB, S, Numbered (Id));
      end loop;
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "setup commit failed");
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Root := S.Indexes.First_Element.Root_Page;
      Database.Close (DB);

      --  Hang a chain of internal nodes with one child each below the root.
      declare
         F     : Database.Storage.File_IO.File_Handle;
         Page  : Database.Storage.Pages.Page;
         Pages : Database.Indexes.BTree.Page_Id_Vectors.Vector;
         First : Database.Storage.Pages.Page_Id;

         procedure Put_Node (Id, Child : Database.Storage.Pages.Page_Id; Leaf : Boolean) is
            C : constant Natural := Natural (Child);
         begin
            Database.Storage.Pages.Initialize
              (Page, Id,
               (if Leaf then Database.Storage.Pages.BTree_Leaf_Page else Database.Storage.Pages.BTree_Internal_Page));
            Database.Storage.Pages.Set_Payload
              (Page,
               [Character'Pos ('B'), Character'Pos ('P'), Character'Pos ('T'), Character'Pos ('1'),
                (if Leaf then 0 else 1), 0, 0,
                Database.Byte (C / 16#1000000#), Database.Byte (C / 16#10000# mod 256),
                Database.Byte (C / 16#100# mod 256), Database.Byte (C mod 256)]);
            R := Database.Storage.File_IO.Write_Page (F, Page);
            Assert (Database.Status.Is_Ok (R), "corrupt node must be written");
         end Put_Node;
      begin
         R := Database.Storage.File_IO.Open (F, Path);
         Assert (Database.Status.Is_Ok (R), "file must open");
         First := Database.Storage.Pages.Page_Id (Database.Storage.File_IO.Page_Count (F));
         for I in 0 .. Depth - 1 loop
            Put_Node (First + Database.Storage.Pages.Page_Id (I), First + Database.Storage.Pages.Page_Id (I + 1),
                      Leaf => False);
         end loop;
         Put_Node (First + Depth, Database.Storage.Pages.Invalid_Page_Id, Leaf => True);
         Put_Node (Root, First, Leaf => False);
         R := Database.Indexes.BTree.Validate (F, Root);
         Assert (R.Code = Database.Status.Corrupt_Index, "a tree deeper than any real one is corrupt");
         R := Database.Indexes.BTree.Pages_Of (F, Root, Pages);
         Assert (R.Code = Database.Status.Corrupt_Index, "listing the pages of a too deep tree fails");
         R := Database.Storage.File_IO.Close (F);
      end;

      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Rebuild_Index (Tx, DB, S, S.Indexes.First_Element.Id);
      Assert (Database.Status.Is_Ok (R), "rebuilding a corrupt index failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "rebuild commit failed");
      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), "users", S);
      Assert (S.Indexes.First_Element.Root_Page /= Root, "a corrupt tree gets a new root");
      Root := S.Indexes.First_Element.Root_Page;
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Count_Where (Tx, DB, S, 3, Database.Values.From_Integer (Numbered (5).Age)) >= 1,
              "the rebuilt index finds its rows");
      R := Database.Transactions.Commit (Tx);

      --  The replaced tree, its old root and the chain below it, is unreachable until vacuum frees it.
      declare
         Orphans : Database.Indexes.BTree.Page_Id_Vectors.Vector;
         Report  : Database.Vacuum.Vacuum_Report;
      begin
         Database.Transactions.Begin_Write (DB, Tx);
         R := Database.Check.Orphan_Pages (Tx, Orphans);
         Assert (Database.Status.Is_Ok (R) and then Natural (Orphans.Length) = Depth + 2,
                 "the pages of the replaced tree are unreachable");
         R := Database.Vacuum.Vacuum (Tx, Report);
         Assert (Database.Status.Is_Ok (R), "vacuum failed");
         Assert (Report.Freed_Pages = Depth + 2 and then not Report.Reachability_Unknown,
                 "vacuum reports the pages it freed");
         R := Database.Transactions.Commit (Tx);
         Assert (Database.Status.Is_Ok (R), "vacuum commit failed");
         Expect_Healthy (DB, "vacuum frees the pages of a replaced tree");
      end;
      Database.Close (DB);
      Assert (Valid (Path, Root), "the rebuilt index is valid");
      Remove_Files (Name);
   end Corrupt_Tree_Is_Replaced;

   --  A transaction of one database is refused for another, which would otherwise be changed outside any transaction.
   procedure Foreign_Transaction_Is_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Name_A : constant String := "secondary_foreign_a.database";
      Name_B : constant String := "secondary_foreign_b.database";
      A, B   : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      S      : Database.Schema.Table_Schema;
      Orders : Database.Schema.Table_Schema;
      Item   : User_Row;
      R      : Database.Status.Result;
   begin
      Remove_Files (Name_A);
      Remove_Files (Name_B);
      Database.Create (A, Ada.Characters.Conversions.To_Wide_Wide_String (Name_A));
      Database.Create (B, Ada.Characters.Conversions.To_Wide_Wide_String (Name_B));
      Add_User_Schema (S);
      R := Users.Register (B, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (A, Tx);
      R := Users.Insert (Tx, B, S, Numbered (1));
      Assert (R.Code = Database.Status.Invalid_Argument, "an insert through another database's transaction is refused");
      Add_User_Schema (Orders);
      Orders.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("orders");
      R := Users.Register (Tx, B, Orders);
      Assert (R.Code = Database.Status.Invalid_Argument,
              "a registration through another database's transaction is refused");
      R := Database.Transactions.Rollback (Tx);

      Database.Transactions.Begin_Read (A, Tx);
      R := Users.Find (Tx, B, S, 1, Item);
      Assert (R.Code = Database.Status.Invalid_Argument, "a read through another database's transaction is refused");
      R := Database.Transactions.Commit (Tx);

      R := Database.Catalog.Find_By_Name (Database.Catalog_State_Key (B), "orders", Orders);
      Assert (R.Code = Database.Status.Not_Found, "the refused registration left no table");
      Expect_Healthy (B, "the refused operations left the database unchanged");
      Database.Close (A);
      Database.Close (B);
      Remove_Files (Name_A);
      Remove_Files (Name_B);
   end Foreign_Transaction_Is_Refused;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Create_Secondary_And_Unique_Metadata'Access,
         "create secondary/unique indexes and persist metadata");
      Register_Routine
        (T,
         Unique_And_Non_Unique_Behavior'Access,
         "unique and non-unique maintenance across reopen");
      Register_Routine
        (T, Rebuild_Existing_Index'Access, "rebuild secondary index");
      Register_Routine
        (T, Persistent_Tree_Across_Reopen'Access, "multi-page index trees across reopen");
      Register_Routine (T, Unbuilt_Index_Is_Rebuilt'Access, "unbuilt index bypassed then rebuilt");
      Register_Routine (T, Rollback_Restores_Index'Access, "rollback restores index pages");
      Register_Routine (T, Rollback_Restores_Catalog'Access, "rollback restores the catalog and allocation");
      Register_Routine (T, Rollback_Removes_Registration'Access, "rollback removes a table registration");
      Register_Routine (T, Corrupt_Tree_Is_Replaced'Access, "a corrupt tree is rejected, replaced and reclaimed");
      Register_Routine (T, Foreign_Transaction_Is_Refused'Access, "another database's transaction is refused");
   end Register_Tests;
end Secondary_Index_Tests;
