with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Catalog;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Status; use Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
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
      R := Database.Catalog.Find_By_Name ("users", S);
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
      R := Database.Catalog.Find_By_Name ("users", S);
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
      R := Database.Catalog.Find_By_Name ("users", S);
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
   end Register_Tests;
end Secondary_Index_Tests;
