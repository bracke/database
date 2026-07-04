with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Catalog;
with Database.Migrations;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body Migration_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;

   type Person_V1 is record
      Id   : Integer;
      Name : Wide_Wide_String (1 .. 16);
   end record;

   type Person_V2 is record
      Id    : Integer;
      Name  : Wide_Wide_String (1 .. 16);
      Email : Wide_Wide_String (1 .. 24);
   end record;

   function To_Row_V1 (P : Person_V1) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (P.Id));
      Database.Rows.Append (R, Database.Values.From_Text (P.Name));
      return R;
   end To_Row_V1;

   function From_Row_V1 (R : Database.Rows.Row) return Person_V1 is
      use Ada.Strings.Wide_Wide_Unbounded;
      N : Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      P : Person_V1 :=
        (Id => Database.Rows.Get (R, 0).Int, Name => [others => ' ']);
   begin
      for I in 1 .. Integer'Min (16, N'Length) loop
         P.Name (I) := N (N'First + I - 1);
      end loop;
      return P;
   end From_Row_V1;

   function Key_Of_V1 (P : Person_V1) return Integer
   is (P.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));
   package People_V1 is new
     Database.Tables.Typed
       (Person_V1,
        Integer,
        To_Row_V1,
        From_Row_V1,
        Key_Of_V1,
        Key_Value);

   function To_Row_V2 (P : Person_V2) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (P.Id));
      Database.Rows.Append (R, Database.Values.From_Text (P.Name));
      Database.Rows.Append (R, Database.Values.From_Text (P.Email));
      return R;
   end To_Row_V2;

   function From_Row_V2 (R : Database.Rows.Row) return Person_V2 is
      use Ada.Strings.Wide_Wide_Unbounded;
      N : Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      E : Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 2).Text);
      P : Person_V2 :=
        (Id    => Database.Rows.Get (R, 0).Int,
         Name  => [others => ' '],
         Email => [others => ' ']);
   begin
      for I in 1 .. Integer'Min (16, N'Length) loop
         P.Name (I) := N (N'First + I - 1);
      end loop;
      for I in 1 .. Integer'Min (24, E'Length) loop
         P.Email (I) := E (E'First + I - 1);
      end loop;
      return P;
   end From_Row_V2;

   function Key_Of_V2 (P : Person_V2) return Integer
   is (P.Id);
   package People_V2 is new
     Database.Tables.Typed
       (Person_V2,
        Integer,
        To_Row_V2,
        From_Row_V2,
        Key_Of_V2,
        Key_Value);

   procedure Delete_File_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_File_If_Exists;

   procedure V1_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("people");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
   end V1_Schema;

   procedure V2_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      V1_Schema (S);
      Database.Schema.Add_Column
        (S, "email", Database.Types.Text_Value, False);
   end V2_Schema;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("schema migrations");
   end Name;

   procedure Add_Column_Reopen_And_Register
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      S1     : Database.Schema.Table_Schema;
      S2     : Database.Schema.Table_Schema;
      Loaded : Database.Schema.Table_Schema;
      R      : Database.Status.Result;
      P      : Person_V2;
      Path   : constant Wide_Wide_String := "migration_add.database";
   begin
      Delete_File_If_Exists ("migration_add.database");
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      V1_Schema (S1);
      R := People_V1.Register (DB, S1);
      Assert (Database.Status.Is_Ok (R), "register v1 failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        People_V1.Insert (Tx, DB, S1, (Id => 1, Name => "Bent            "));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R :=
        Database.Migrations.Add_Column
          (Tx,
           "people",
           "email",
           Database.Types.Describe (Database.Types.Text_Value),
           Database.Values.From_Text ("unknown@example.test"));
      Assert (Database.Status.Is_Ok (R), "add column failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "reopen failed");
      R := Database.Catalog.Find_By_Name ("people", Loaded);
      Assert (Database.Status.Is_Ok (R), "catalog load failed");
      Assert
        (Database.Schema.Column_Count (Loaded) = 3,
         "added column not persisted");
      Assert (Loaded.Schema_Version = 2, "schema version not advanced");
      V2_Schema (S2);
      R := People_V2.Register (DB, S2);
      Assert (Database.Status.Is_Ok (R), "register v2 after migration failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := People_V2.Find (Tx, DB, S2, 1, P);
      Assert (Database.Status.Is_Ok (R), "find after migration failed");
      Assert
        (P.Email (1 .. 20) = "unknown@example.test",
         "default value not written to migrated row");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");
      Database.Close (DB);
      Delete_File_If_Exists ("migration_add.database");
   end Add_Column_Reopen_And_Register;

   procedure Invalid_Add_Column_Cases
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      V1_Schema (S);
      R := People_V1.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Migrations.Add_Column
          (Tx,
           "people",
           "name",
           Database.Types.Describe (Database.Types.Text_Value),
           Database.Values.Null_Value);
      Assert
        (R.Code = Database.Status.Already_Exists, "duplicate add accepted");
      R :=
        Database.Migrations.Add_Column
          (Tx,
           "people",
           "nickname",
           Database.Types.Describe (Database.Types.Text_Value),
           True,
           Database.Values.From_Text ("anonymous"));
      Assert
        (Database.Status.Is_Ok (R),
         "explicit nullable column with non-null default failed");
      declare
         Loaded : Database.Schema.Table_Schema;
      begin
         R := Database.Catalog.Find_By_Name ("people", Loaded);
         Assert
           (Database.Status.Is_Ok (R),
            "catalog read after explicit nullable add failed");
         Assert
           (Loaded.Columns.Element (2).Nullable,
            "explicit nullable flag was not preserved");
      end;
      R :=
        Database.Migrations.Add_Column
          (Tx,
           "people",
           "bad",
           Database.Types.Describe (Database.Types.Text_Value),
           Database.Values.From_Integer (1));
      Assert
        (R.Code = Database.Status.Schema_Mismatch,
         "wrong default type accepted");
      R :=
        Database.Migrations.Add_Column
          (Tx,
           "people",
           "no_type",
           Database.Types.Describe (Database.Types.Null_Value),
           Database.Values.Null_Value);
      Assert (R.Code = Database.Status.Invalid_Schema, "null type accepted");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Invalid_Add_Column_Cases;

   procedure Rename_Drop_And_Nullability
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      S      : Database.Schema.Table_Schema;
      Loaded : Database.Schema.Table_Schema;
      R      : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      V1_Schema (S);
      R := People_V1.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Migrations.Rename_Column (Tx, "people", "name", "full_name");
      Assert (Database.Status.Is_Ok (R), "rename failed");
      R := Database.Catalog.Find_By_Name ("people", Loaded);
      Assert (Database.Status.Is_Ok (R), "catalog read failed");
      Assert
        (Database.Schema.Find_Column_Position (Loaded, "full_name")
         /= Natural'Last,
         "rename not visible");
      Assert
        (Loaded.Columns.Element (1).Id = 1, "column id changed during rename");
      R := Database.Migrations.Rename_Column (Tx, "people", "full_name", "id");
      Assert
        (R.Code = Database.Status.Already_Exists, "rename collision accepted");
      R := Database.Migrations.Drop_Column (Tx, "people", "id");
      Assert
        (R.Code = Database.Status.Unsupported_Migration,
         "dropped primary key");
      R := Database.Migrations.Change_Nullability (Tx, "people", "id", True);
      Assert
        (R.Code = Database.Status.Unsupported_Migration,
         "primary key made nullable");
      R :=
        Database.Migrations.Change_Nullability
          (Tx, "people", "full_name", True);
      Assert (Database.Status.Is_Ok (R), "not-null to nullable failed");
      R := Database.Migrations.Drop_Column (Tx, "people", "full_name");
      Assert (Database.Status.Is_Ok (R), "drop ordinary column failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
   end Rename_Drop_And_Nullability;

   procedure Rollback_Restores_Catalog
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      S      : Database.Schema.Table_Schema;
      Loaded : Database.Schema.Table_Schema;
      R      : Database.Status.Result;
      Path   : constant Wide_Wide_String := "migration_rollback.database";
   begin
      Delete_File_If_Exists ("migration_rollback.database");
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      V1_Schema (S);
      R := People_V1.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Migrations.Rename_Column (Tx, "people", "name", "full_name");
      Assert (Database.Status.Is_Ok (R), "rename failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      R := Database.Catalog.Find_By_Name ("people", Loaded);
      Assert (Database.Status.Is_Ok (R), "catalog read failed");
      Assert
        (Database.Schema.Find_Column_Position (Loaded, "name") /= Natural'Last,
         "rollback did not restore old name");
      Database.Close (DB);
      Delete_File_If_Exists ("migration_rollback.database");
   end Rollback_Restores_Catalog;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Add_Column_Reopen_And_Register'Access,
         "add column rebuilds rows, persists schema, and permits new typed registration");
      Register_Routine
        (T, Invalid_Add_Column_Cases'Access, "add column validation failures");
      Register_Routine
        (T,
         Rename_Drop_And_Nullability'Access,
         "rename, drop, and nullability rules");
      Register_Routine
        (T,
         Rollback_Restores_Catalog'Access,
         "rollback restores catalog metadata");
   end Register_Tests;
end Migration_Tests;
