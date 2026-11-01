with AUnit.Assertions;

with Ada.Calendar;
with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Streams;
with Ada.Streams.Stream_IO;
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
with Database.WAL;
with GNAT.OS_Lib;

package body Concurrency_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;
   use type Database.Transactions.Transaction_Mode;
   use type GNAT.OS_Lib.Process_Id;
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;

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

   function File_Contents (Path : String) return Ada.Streams.Stream_Element_Array is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      declare
         Length : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (Ada.Streams.Stream_IO.Size (File));
         Data   : Ada.Streams.Stream_Element_Array
           (0 .. Length - Ada.Streams.Stream_Element_Offset'(1));
         Last   : Ada.Streams.Stream_Element_Offset;
      begin
         if Data'Length > 0 then
            Ada.Streams.Stream_IO.Read (File, Data, Last);
            if Last /= Data'Last then
               Ada.Streams.Stream_IO.Close (File);
               raise Ada.Streams.Stream_IO.End_Error;
            end if;
         end if;
         Ada.Streams.Stream_IO.Close (File);
         return Data;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end File_Contents;

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

   procedure Persistent_Read_Only_Contract
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path       : constant String := "read_only_contract.database";
      FTS_Path   : constant String := Path & ".fts";
      DB         : Database.Handle;
      Read_Tx    : Database.Transactions.Transaction;
      Write_Tx   : Database.Transactions.Transaction;
      W          : Database.WAL.WAL_Handle;
      R          : Database.Status.Result;
      DB_Size    : Ada.Directories.File_Size;
      FTS_Size   : Ada.Directories.File_Size;
      DB_Time    : Ada.Calendar.Time;
      FTS_Time   : Ada.Calendar.Time;
   begin
      Remove_File_If_Present (Path);
      Remove_File_If_Present (FTS_Path);
      Remove_File_If_Present (Path & ".wal");

      Database.Create
        (DB, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert (Database.Last_Operation_Succeeded (DB), "fixture create failed");
      Database.Close (DB);
      Assert (Database.Last_Operation_Succeeded (DB), "fixture close failed");
      Assert (Ada.Directories.Exists (FTS_Path), "fixture full-text sidecar missing");

      DB_Size := Ada.Directories.Size (Path);
      FTS_Size := Ada.Directories.Size (FTS_Path);
      DB_Time := Ada.Directories.Modification_Time (Path);
      FTS_Time := Ada.Directories.Modification_Time (FTS_Path);

      declare
         DB_Bytes  : constant Ada.Streams.Stream_Element_Array := File_Contents (Path);
         FTS_Bytes : constant Ada.Streams.Stream_Element_Array := File_Contents (FTS_Path);
      begin
         Database.Open_Read_Only
           (DB, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
         Assert (Database.Last_Operation_Succeeded (DB), "read-only open failed");
         Assert (Database.Is_Read_Only (DB), "handle not marked read-only");

         Database.Transactions.Begin_Read (DB, Read_Tx);
         Assert (Database.Transactions.Is_Active (Read_Tx), "read transaction inactive");
         R := Database.Transactions.Commit (Read_Tx);
         Assert (Database.Status.Is_Ok (R), "read transaction commit failed");

         Database.Transactions.Begin_Write (DB, Write_Tx);
         Assert (not Database.Transactions.Is_Active (Write_Tx), "write transaction was admitted");
         Assert
           (Database.Transactions.Result (Write_Tx).Code = Database.Status.Read_Only_Transaction,
            "write transaction returned wrong status");

         Database.Close (DB);
         Assert (Database.Last_Operation_Succeeded (DB), "read-only close failed");
         Assert (Ada.Directories.Size (Path) = DB_Size, "carrier size changed");
         Assert (Ada.Directories.Size (FTS_Path) = FTS_Size, "full-text sidecar size changed");
         Assert (Ada.Directories.Modification_Time (Path) = DB_Time, "carrier timestamp changed");
         Assert
           (Ada.Directories.Modification_Time (FTS_Path) = FTS_Time,
            "full-text sidecar timestamp changed");
         Assert (File_Contents (Path) = DB_Bytes, "carrier bytes changed");
         Assert (File_Contents (FTS_Path) = FTS_Bytes, "full-text sidecar bytes changed");
      end;

      R := Database.WAL.Create
        (W, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert (Database.Status.Is_Ok (R), "WAL fixture create failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "WAL fixture close failed");
      Database.Open_Read_Only
        (DB, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert
        (Database.Last_Result (DB).Code = Database.Status.Recovery_Required,
         "read-only open did not reject existing WAL");
      Assert
        (Database.WAL.Exists (Ada.Characters.Conversions.To_Wide_Wide_String (Path)),
         "read-only open removed the WAL");

      R := Database.WAL.Delete (Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert (Database.Status.Is_Ok (R), "WAL cleanup failed");
      Remove_File_If_Present (Path);
      Remove_File_If_Present (FTS_Path);
   exception
      when others =>
         Remove_File_If_Present (Path & ".wal");
         Remove_File_If_Present (Path);
         Remove_File_If_Present (FTS_Path);
         raise;
   end Persistent_Read_Only_Contract;

   procedure Process_Shared_Readers_Block_Writer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path       : constant String := "shared_reader_test.database";
      Ready_Path : constant String := "shared_reader_test.ready";
      Fixture    : Database.Handle;
      Reader     : Database.Handle;
      Writer     : Database.Handle;
      Args       : GNAT.OS_Lib.Argument_List (1 .. 3);
      Pid        : GNAT.OS_Lib.Process_Id;
      Done       : GNAT.OS_Lib.Process_Id;
      Success    : Boolean := False;
   begin
      Remove_File_If_Present (Path);
      Remove_File_If_Present (Path & ".fts");
      Remove_File_If_Present (Ready_Path);
      Database.Create
        (Fixture, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert (Database.Last_Operation_Succeeded (Fixture), "fixture create failed");
      Database.Close (Fixture);
      Assert (Database.Last_Operation_Succeeded (Fixture), "fixture close failed");

      Args (1) := new String'(Path);
      Args (2) := new String'(Ready_Path);
      Args (3) := new String'("read-only");
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn ("./bin/lock_holder", Args);
      for Arg of Args loop
         GNAT.OS_Lib.Free (Arg);
      end loop;
      Assert (Pid /= GNAT.OS_Lib.Invalid_Pid, "could not spawn read-only helper");
      for I in 1 .. 50 loop
         exit when Ada.Directories.Exists (Ready_Path);
         delay 0.05;
      end loop;
      Assert (Ada.Directories.Exists (Ready_Path), "read-only helper did not become ready");

      Database.Open_Read_Only
        (Reader, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert (Database.Last_Operation_Succeeded (Reader), "second reader was rejected");
      Database.Open
        (Writer, Ada.Characters.Conversions.To_Wide_Wide_String (Path));
      Assert
        (Database.Last_Result (Writer).Code = Database.Status.Lock_Error,
         "writer was admitted while shared readers held locks");
      Database.Close (Reader);
      Assert (Database.Last_Operation_Succeeded (Reader), "reader close failed");

      GNAT.OS_Lib.Wait_Process (Done, Success);
      Assert (Done = Pid, "unexpected process completed");
      Assert (Success, "read-only helper failed");
      Remove_File_If_Present (Ready_Path);
      Remove_File_If_Present (Path);
      Remove_File_If_Present (Path & ".fts");
   exception
      when others =>
         Remove_File_If_Present (Ready_Path);
         Remove_File_If_Present (Path);
         Remove_File_If_Present (Path & ".fts");
         raise;
   end Process_Shared_Readers_Block_Writer;

   --  Many readers admitted at once run Start concurrently; the transaction-id
   --  allocator must be atomic or two of them get the same id.
   procedure Concurrent_Begin_Assigns_Unique_Ids
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tasks    : constant := 8;
      Per_Task : constant := 250;
      Total    : constant := Tasks * Per_Task;

      type Id_Array is array (1 .. Total) of Natural;

      DB : Database.Handle;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;

      protected Collector is
         procedure Record_Id (Id : Natural);
         function Get (I : Positive) return Natural;
         function Count return Natural;
      private
         Ids : Id_Array := (others => 0);
         N   : Natural := 0;
      end Collector;

      protected body Collector is
         procedure Record_Id (Id : Natural) is
         begin
            N := N + 1;
            if N <= Total then
               Ids (N) := Id;
            end if;
         end Record_Id;
         function Get (I : Positive) return Natural is (Ids (I));
         function Count return Natural is (N);
      end Collector;

      task type Reader;
      task body Reader is
         Tx : Database.Transactions.Transaction;
         RR : Database.Status.Result;
      begin
         for I in 1 .. Per_Task loop
            Database.Transactions.Begin_Read (DB, Tx);
            Collector.Record_Id (Natural (Database.Transactions.Id (Tx)));
            RR := Database.Transactions.Commit (Tx);
         end loop;
      end Reader;

      Local     : array (1 .. Total) of Natural := (others => 0);
      Duplicate : Boolean := False;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      declare
         Readers : array (1 .. Tasks) of Reader;
         pragma Unreferenced (Readers);
      begin
         null;  --  block until every reader task terminates
      end;

      Assert (Collector.Count = Total,
              "some concurrent transactions were lost");
      for I in 1 .. Total loop
         Local (I) := Collector.Get (I);
      end loop;
      for I in 1 .. Total loop
         for J in I + 1 .. Total loop
            if Local (I) = Local (J) then
               Duplicate := True;
            end if;
         end loop;
      end loop;
      Assert (not Duplicate,
              "concurrent transactions were assigned duplicate ids");
      Database.Close (DB);
   end Concurrent_Begin_Assigns_Unique_Ids;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Concurrent_Begin_Assigns_Unique_Ids'Access,
         "concurrent begins assign unique transaction ids");
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
         Persistent_Read_Only_Contract'Access,
         "persistent read-only handle never mutates and rejects recovery");
      Register_Routine
        (T,
         Process_Shared_Readers_Block_Writer'Access,
         "process shared readers coexist and block writer");
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
