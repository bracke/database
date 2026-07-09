with AUnit.Assertions;

with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Locking;
with Database.Predicates;
with Database.Queries;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with GNAT.OS_Lib;

package body Concurrency_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;
   use type Database.Transactions.Transaction_Mode;
   use type GNAT.OS_Lib.Process_Id;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("concurrency and isolation");
   end Name;

   type Item is record
      Id    : Integer;
      Value : Integer;
   end record;

   function To_Row (X : Item) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (X.Id));
      Database.Rows.Append (R, Database.Values.From_Integer (X.Value));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Item is
   begin
      return
        (Id    => Database.Rows.Get (R, 0).Int,
         Value => Database.Rows.Get (R, 1).Int);
   end From_Row;

   function Key_Of (X : Item) return Integer
   is (X.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   procedure Remove_File_If_Present (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others => null;
   end Remove_File_If_Present;

   package Items is new
     Database.Tables.Typed
       (Item,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   procedure Build_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("items");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "value", Database.Types.Integer_Value, False);
   end Build_Schema;

   procedure Lock_Allows_Multiple_Readers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      L       : Database.Locking.Read_Write_Lock;
      Granted : Boolean;
   begin
      L.Try_Begin_Read (Granted);
      Assert (Granted, "first reader rejected");
      L.Try_Begin_Read (Granted);
      Assert (Granted, "second reader rejected");
      Assert (L.Active_Readers = 2, "reader count wrong");
      L.Try_Begin_Write (Granted);
      Assert (Granted, "writer rejected while readers active under MVCC");
      L.End_Write;
      L.End_Read;
      L.End_Read;
      L.Try_Begin_Write (Granted);
      Assert (Granted, "writer rejected after readers ended");
      Assert (L.Writer_Active, "writer not marked active");
      L.Try_Begin_Read (Granted);
      Assert (Granted, "reader rejected while writer active under MVCC");
      L.End_Read;
      L.End_Write;
   end Lock_Allows_Multiple_Readers;

   procedure Transaction_Modes_And_Conflicts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Read_Tx  : Database.Transactions.Transaction;
      Write_Tx : Database.Transactions.Transaction;
      Granted  : Boolean;
      R        : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Read_Tx);
      Assert
        (Database.Transactions.Is_Active (Read_Tx),
         "read transaction inactive");
      Assert
        (Database.Transactions.Mode (Read_Tx)
         = Database.Transactions.Read_Only,
         "read transaction mode wrong");
      Database.Transactions.Try_Begin_Write (DB, Write_Tx, Granted);
      Assert (Granted, "writer rejected while reader active under MVCC");
      R := Database.Transactions.Commit (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");
      R := Database.Transactions.Rollback (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "writer rollback failed");
      Database.Close (DB);
   end Transaction_Modes_And_Conflicts;

   procedure Read_Only_Write_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Read (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 10));
      Assert
        (R.Code = Database.Status.Read_Only_Transaction,
         "read-only insert was not rejected");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      Database.Close (DB);
   end Read_Only_Write_Rejected;

   procedure Read_And_Write_Visibility
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Read_Tx : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema;
      R       : Database.Status.Result;
      Found   : Item;
      Q       : Database.Queries.Query;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 10));
      Assert (Database.Status.Is_Ok (R), "write insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "write commit failed");

      Database.Transactions.Begin_Read (DB, Read_Tx);
      R := Items.Find (Read_Tx, DB, S, 1, Found);
      Assert (Database.Status.Is_Ok (R), "read find failed");
      Assert (Found.Value = 10, "committed value wrong");
      R :=
        Items.Scan_Query
          (Read_Tx, DB, S, Database.Predicates.True_Predicate, Q);
      Assert (Database.Status.Is_Ok (R), "read scan failed");
      Assert (Database.Queries.Row_Count (Q) = 1, "read scan count wrong");
      R := Database.Transactions.Commit (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");
      Database.Close (DB);
   end Read_And_Write_Visibility;

   procedure Cursor_After_Commit_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;
      C  : Items.Cursor;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 10));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Items.Insert (Tx, DB, S, (Id => 2, Value => 20));
      Assert (Database.Status.Is_Ok (R), "second insert failed");
      R := Items.Scan (Tx, DB, S, Database.Predicates.True_Predicate, C);
      Assert (Database.Status.Is_Ok (R), "scan failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      R := Items.Next (Tx, DB, S, Database.Predicates.True_Predicate, C);
      Assert
        (R.Code = Database.Status.Transaction_Error,
         "cursor use after commit did not fail safely");
      Database.Close (DB);
   end Cursor_After_Commit_Fails;

   procedure Active_Write_Allows_Readers_But_Blocks_Second_Writer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB             : Database.Handle;
      Write_Tx       : Database.Transactions.Transaction;
      Other_Write_Tx : Database.Transactions.Transaction;
      Read_Tx        : Database.Transactions.Transaction;
      Granted        : Boolean;
      R              : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Write (DB, Write_Tx);
      Assert
        (Database.Transactions.Is_Active (Write_Tx),
         "write transaction inactive");

      Database.Transactions.Try_Begin_Write (DB, Other_Write_Tx, Granted);
      Assert (not Granted, "second writer granted while writer active");
      Assert
        (Database.Transactions.Result (Other_Write_Tx).Code
         = Database.Status.Transaction_Conflict,
         "second writer conflict status wrong");

      Database.Transactions.Try_Begin_Read (DB, Read_Tx, Granted);
      Assert (Granted, "reader rejected while writer active under MVCC");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback during writer failed");

      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "write commit failed");
      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "double commit was not safe");

      Database.Transactions.Try_Begin_Read (DB, Read_Tx, Granted);
      Assert (Granted, "reader rejected after writer committed");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "double rollback was not safe");
      Database.Close (DB);
   end Active_Write_Allows_Readers_But_Blocks_Second_Writer;

   procedure Close_Rejects_Active_Transaction
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      Database.Close (DB);
      Assert
        (Database.Last_Result (DB).Code = Database.Status.Transaction_Conflict,
         "close did not reject active transaction");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit after rejected close failed");
      Database.Close (DB);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "close after commit failed");
   end Close_Rejects_Active_Transaction;

   procedure Process_Lock_Blocks_Second_Process
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path       : constant String := "process_lock_test.database";
      Ready_Path : constant String := "process_lock_test.ready";
      DB         : Database.Handle;
      Other      : Database.Handle;
      Args       : GNAT.OS_Lib.Argument_List (1 .. 2);
      Pid        : GNAT.OS_Lib.Process_Id;
      Done       : GNAT.OS_Lib.Process_Id;
      Success    : Boolean := False;
      Ready      : Boolean := False;
   begin
      Remove_File_If_Present (Path);
      Remove_File_If_Present (Path & ".fts");
      Remove_File_If_Present (Ready_Path);

      Database.Create
        (DB, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert
        (Database.Last_Operation_Succeeded (DB),
         "process lock fixture create failed");
      Database.Close (DB);
      Assert
        (Database.Last_Operation_Succeeded (DB),
         "process lock fixture close failed");

      Args (1) := new String'(Path);
      Args (2) := new String'(Ready_Path);
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn ("./bin/lock_holder", Args);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      Assert
        (Pid /= GNAT.OS_Lib.Invalid_Pid,
         "could not spawn process lock helper");

      for I in 1 .. 50 loop
         exit when Ada.Directories.Exists (Ready_Path);
         delay 0.05;
      end loop;
      Ready := Ada.Directories.Exists (Ready_Path);
      Assert (Ready, "process lock helper did not become ready");

      Database.Open
        (Other, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert
        (Database.Last_Result (Other).Code = Database.Status.Lock_Error,
         "second process open was not rejected by process lock");

      GNAT.OS_Lib.Wait_Process (Done, Success);
      Assert (Done = Pid, "unexpected process completed");
      Assert (Success, "process lock helper failed");

      Remove_File_If_Present (Ready_Path);
      Remove_File_If_Present (Path);
      Remove_File_If_Present (Path & ".fts");
   exception
      when others =>
         Remove_File_If_Present (Ready_Path);
         Remove_File_If_Present (Path);
         Remove_File_If_Present (Path & ".fts");
         raise;
   end Process_Lock_Blocks_Second_Process;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Lock_Allows_Multiple_Readers'Access,
         "lock allows multiple readers and one writer");
      Register_Routine
        (T,
         Transaction_Modes_And_Conflicts'Access,
         "transaction modes and nonblocking conflicts");
      Register_Routine
        (T,
         Read_Only_Write_Rejected'Access,
         "read-only transaction rejects writes");
      Register_Routine
        (T,
         Active_Write_Allows_Readers_But_Blocks_Second_Writer'Access,
         "active writer allows readers and blocks second writer");
      Register_Routine
        (T,
         Close_Rejects_Active_Transaction'Access,
         "close rejects active transactions");
      Register_Routine
        (T,
         Process_Lock_Blocks_Second_Process'Access,
         "process lock blocks second process");
      Register_Routine
        (T,
         Read_And_Write_Visibility'Access,
         "committed data visible to later readers");
      Register_Routine
        (T,
         Cursor_After_Commit_Fails'Access,
         "cursor after transaction end fails safely");
   end Register_Tests;
end Concurrency_Tests;
