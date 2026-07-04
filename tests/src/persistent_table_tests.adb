with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Catalog;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Database.Status; use Database.Status;

package body Persistent_Table_Tests is
   use AUnit.Assertions;
   type User_Row is record
      Id   : Integer;
      Name : Wide_Wide_String (1 .. 16);
      Age  : Integer;
   end record;
   function To_Row (U : User_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (U.Id));
      Database.Rows.Append (R, Database.Values.From_Text (U.Name));
      Database.Rows.Append (R, Database.Values.From_Integer (U.Age));
      return R;
   end To_Row;
   function From_Row (R : Database.Rows.Row) return User_Row is
      use Ada.Strings.Wide_Wide_Unbounded;
      S : Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      U : User_Row :=
        (Id   => Database.Rows.Get (R, 0).Int,
         Name => (others => ' '),
         Age  => Database.Rows.Get (R, 2).Int);
   begin
      for I in 1 .. Integer'Min (16, S'Length) loop
         U.Name (I) := S (S'First + I - 1);
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
      return AUnit.Format ("persistent typed tables");
   end Name;

   procedure Reopen_Find_Scan_Delete
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema;
      R        : Database.Status.Result;
      U        : User_Row := (Id => 1, Name => "Bent            ", Age => 42);
      Out_User : User_Row;
      C        : Users.Cursor;
      Path     : constant Wide_Wide_String := "persistent_users.database";
   begin
      if Ada.Directories.Exists ("persistent_users.database") then
         Ada.Directories.Delete_File ("persistent_users.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create persistent DB failed");
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register table failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, U);
      Assert (Database.Status.Is_Ok (R), "insert failed");
      Database.Transactions.Commit (Tx);
      Assert
        (Database.Status.Is_Ok (Database.Transactions.Result (Tx)),
         "commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "reopen failed");
      R := Database.Catalog.Find_By_Name ("users", S);
      Assert (Database.Status.Is_Ok (R), "catalog restore failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Find (Tx, DB, S, 1, Out_User);
      Assert (Database.Status.Is_Ok (R), "find after reopen failed");
      Assert (Out_User.Age = 42, "wrong row after reopen");
      R := Users.Scan (Tx, DB, S, Database.Predicates.True_Predicate, C);
      Assert
        (Database.Status.Is_Ok (R) and then Users.Has_Element (C),
         "scan after reopen failed");
      R := Users.Delete (Tx, DB, S, 1);
      Assert (Database.Status.Is_Ok (R), "delete failed");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);

      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name ("users", S);
      Assert
        (Database.Status.Is_Ok (R), "catalog restore after delete failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Find (Tx, DB, S, 1, Out_User);
      Assert
        (not Database.Status.Is_Ok (R), "deleted row visible after reopen");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
      if Ada.Directories.Exists ("persistent_users.database") then
         Ada.Directories.Delete_File ("persistent_users.database");
      end if;
   end Reopen_Find_Scan_Delete;

   procedure Rollback_Insert_Update_Delete
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema;
      R        : Database.Status.Result;
      U1       : User_Row := (Id => 1, Name => "Bent            ", Age => 42);
      U2       : User_Row := (Id => 1, Name => "Bent            ", Age => 43);
      Out_User : User_Row;
      Path     : constant Wide_Wide_String := "persistent_rollback.database";
   begin
      if Ada.Directories.Exists ("persistent_rollback.database") then
         Ada.Directories.Delete_File ("persistent_rollback.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create rollback DB failed");
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register rollback table failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, U1);
      Assert (Database.Status.Is_Ok (R), "insert before rollback failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback insert failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Find (Tx, DB, S, 1, Out_User);
      Assert (not Database.Status.Is_Ok (R), "rolled back insert is visible");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "empty commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, U1);
      Assert (Database.Status.Is_Ok (R), "baseline insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "baseline commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Update (Tx, DB, S, U2);
      Assert (Database.Status.Is_Ok (R), "update before rollback failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback update failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Find (Tx, DB, S, 1, Out_User);
      Assert (Database.Status.Is_Ok (R), "find after rollback update failed");
      Assert (Out_User.Age = 42, "rollback update did not restore old row");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit after update check failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Delete (Tx, DB, S, 1);
      Assert (Database.Status.Is_Ok (R), "delete before rollback failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback delete failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Find (Tx, DB, S, 1, Out_User);
      Assert
        (Database.Status.Is_Ok (R), "rollback delete did not restore row");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit after delete check failed");
      Database.Close (DB);
      if Ada.Directories.Exists ("persistent_rollback.database") then
         Ada.Directories.Delete_File ("persistent_rollback.database");
      end if;
   end Rollback_Insert_Update_Delete;

   procedure Indexed_Duplicate_And_Reopen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema;
      R        : Database.Status.Result;
      U1       : User_Row := (Id => 7, Name => "Bent            ", Age => 42);
      U2       : User_Row := (Id => 7, Name => "Bent            ", Age => 43);
      Out_User : User_Row;
      Path     : constant Wide_Wide_String := "persistent_indexed.database";
   begin
      if Ada.Directories.Exists ("persistent_indexed.database") then
         Ada.Directories.Delete_File ("persistent_indexed.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create indexed DB failed");
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register indexed table failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, U1);
      Assert (Database.Status.Is_Ok (R), "indexed insert failed");
      R := Users.Insert (Tx, DB, S, U2);
      Assert
        (R.Code = Database.Status.Duplicate_Key,
         "duplicate primary key was not rejected by index");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit indexed insert failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "reopen indexed DB failed");
      R := Database.Catalog.Find_By_Name ("users", S);
      Assert (Database.Status.Is_Ok (R), "catalog index metadata missing");
      Assert
        (S.Primary_Index_Root /= 0, "primary index root was not persisted");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Find (Tx, DB, S, 7, Out_User);
      Assert (Database.Status.Is_Ok (R), "indexed lookup after reopen failed");
      Assert (Out_User.Age = 42, "indexed lookup returned wrong row");
      R := Users.Delete (Tx, DB, S, 7);
      Assert (Database.Status.Is_Ok (R), "indexed delete failed");
      R := Users.Find (Tx, DB, S, 7, Out_User);
      Assert
        (not Database.Status.Is_Ok (R),
         "deleted key remained visible in index");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit indexed delete failed");
      Database.Close (DB);
      if Ada.Directories.Exists ("persistent_indexed.database") then
         Ada.Directories.Delete_File ("persistent_indexed.database");
      end if;
   end Indexed_Duplicate_And_Reopen;

   procedure Transaction_State_Rejections
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      U    : User_Row := (Id => 1, Name => "Bent            ", Age => 42);
      Path : constant Wide_Wide_String := "persistent_state.database";
   begin
      if Ada.Directories.Exists ("persistent_state.database") then
         Ada.Directories.Delete_File ("persistent_state.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create state DB failed");
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register state table failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Users.Insert (Tx, DB, S, U);
      Assert (Database.Status.Is_Ok (R), "state insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "state commit failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (not Database.Status.Is_Ok (R), "rollback after commit accepted");
      R := Users.Insert (Tx, DB, S, U);
      Assert
        (not Database.Status.Is_Ok (R), "operation after commit accepted");
      Database.Close (DB);
      if Ada.Directories.Exists ("persistent_state.database") then
         Ada.Directories.Delete_File ("persistent_state.database");
      end if;
   end Transaction_State_Rejections;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Reopen_Find_Scan_Delete'Access,
         "create/register/insert/commit/reopen/find/scan/delete/reopen");
      Register_Routine
        (T,
         Indexed_Duplicate_And_Reopen'Access,
         "indexed duplicate detection and reopen lookup");
      Register_Routine
        (T,
         Rollback_Insert_Update_Delete'Access,
         "rollback insert/update/delete");
      Register_Routine
        (T,
         Transaction_State_Rejections'Access,
         "transaction state rejection rules");
   end Register_Tests;
end Persistent_Table_Tests;
