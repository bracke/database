with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Events;
with Database.Metrics;
with Database.Profiling;
with Database.Queries;
with Database.Rows;
with Database.Status; use Database.Status;
with Database.Tracing;
with Database.Transactions;
with Database.Values;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.WAL;
with Database.Log_Sequence;
with Database.Diagnostics.Runtime;

package body Observability_Tests is
   use AUnit.Assertions;
   use Ada.Strings.Wide_Wide_Unbounded;

   Sink_Count    : Natural := 0;
   Handler_Count : Natural := 0;

   procedure Remove_File (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_File;

   procedure Sink (Event : Database.Tracing.Trace_Event) is
      pragma Unreferenced (Event);
   begin
      Sink_Count := Sink_Count + 1;
   end Sink;

   procedure Handler (Event : Database.Events.Operational_Event) is
      pragma Unreferenced (Event);
   begin
      Handler_Count := Handler_Count + 1;
   end Handler;

   procedure Bad_Handler (Event : Database.Events.Operational_Event) is
      pragma Unreferenced (Event);
   begin
      raise Program_Error with "expected test hook failure";
   end Bad_Handler;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("observability");
   end Name;

   procedure Trace_Filter_And_Sink
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Status.Result;
   begin
      Sink_Count := 0;
      Database.Tracing.Reset;
      Database.Tracing.Enable;
      Database.Tracing.Set_Custom_Sink (Sink'Access);
      R := Database.Tracing.Emit (Database.Tracing.Query_Trace, "visible");
      Assert (Database.Status.Is_Ok (R), "trace emitted");
      Assert (Sink_Count = 1, "custom sink received trace");
      Assert (Database.Tracing.Buffered_Count = 1, "trace buffered");
      Database.Tracing.Disable_Category (Database.Tracing.Query_Trace);
      R := Database.Tracing.Emit (Database.Tracing.Query_Trace, "filtered");
      Assert (Database.Status.Is_Ok (R), "filtered trace succeeds");
      Assert (Sink_Count = 1, "filtered trace not delivered");
   end Trace_Filter_And_Sink;

   procedure Sensitive_Trace_Filtering
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      E : Database.Tracing.Trace_Event;
   begin
      Database.Tracing.Reset;
      Database.Tracing.Enable;
      E.Category := Database.Tracing.Encryption_Trace;
      E.Message := To_Unbounded_Wide_Wide_String ("plaintext key material");
      E.Sensitive := True;
      Database.Tracing.Emit_Trace (E);
      Assert (Database.Tracing.Buffered_Count = 1, "sensitive trace stored");
      Assert
        (To_Wide_Wide_String (Database.Tracing.Buffered_Event (0).Message)
         /= "plaintext key material",
         "sensitive trace redacted by default");
   end Sensitive_Trace_Filtering;

   procedure Metrics_And_Transactions
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Metrics.Metrics_Snapshot;
   begin
      Database.Metrics.Reset_Metrics;
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Write (DB, Tx);
      Assert (Database.Transactions.Is_Active (Tx), "transaction active");
      Database.Transactions.Commit (Tx);
      S := Database.Metrics.Snapshot_Metrics;
      Assert (S.Transactions_Begun = 1, "begin counted");
      Assert (S.Transactions_Committed = 1, "commit counted");
      Database.Close (DB);
   end Metrics_And_Transactions;

   procedure Events_Isolate_Handlers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Status.Result;
   begin
      Handler_Count := 0;
      Database.Events.Clear_Handlers;
      Database.Events.Subscribe (Handler'Access);
      R := Database.Events.Emit (Database.Events.Backup_Start, "backup");
      Assert (Database.Status.Is_Ok (R), "good event handler succeeds");
      Assert (Handler_Count = 1, "handler called");
      Database.Events.Clear_Handlers;
      Database.Events.Subscribe (Bad_Handler'Access);
      R := Database.Events.Emit (Database.Events.Backup_Start, "backup");
      Assert
        (R.Code = Database.Status.Event_Handler_Error, "bad handler isolated");
      Database.Events.Clear_Handlers;
   end Events_Isolate_Handlers;

   procedure Profile_Query_Rows (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Q   : Database.Queries.Query := Database.Queries.Empty;
      Row : Database.Rows.Row;
      P   : Database.Profiling.Query_Profile;
   begin
      Database.Rows.Append (Row, Database.Values.From_Integer (42));
      Database.Queries.Append (Q, Row);
      P := Database.Profiling.Profile_Query (Q);
      Assert (P.Rows_Returned = 1, "profile returned row count");
      Assert (Natural (P.Operators.Length) = 1, "operator profile present");
   end Profile_Query_Rows;

   procedure Runtime_Diagnostics (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      D  : Database.Diagnostics.Runtime.Transaction_Diagnostics;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      D := Database.Diagnostics.Runtime.Active_Transactions (DB);
      Assert (D.Active_Readers = 1, "active reader visible");
      Database.Transactions.Rollback (Tx);
      Database.Close (DB);
   end Runtime_Diagnostics;

   procedure Storage_And_WAL_Metrics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "observability_metrics.database";
      F    : Database.Storage.File_IO.File_Handle;
      W    : Database.WAL.WAL_Handle;
      P    : Database.Storage.Pages.Page;
      L    : Database.Log_Sequence.Log_Sequence_Number;
      R    : Database.Status.Result;
      S    : Database.Metrics.Metrics_Snapshot;
   begin
      Remove_File ("observability_metrics.database");
      Remove_File ("observability_metrics.database.wal");
      Database.Metrics.Reset_Metrics;
      Database.Tracing.Reset;
      Database.Tracing.Enable;
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "file create failed");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.Storage.File_IO.Write_Page (F, P);
      Assert (Database.Status.Is_Ok (R), "page write failed");
      R := Database.Storage.File_IO.Read_Raw_Page (F, 2, P);
      Assert (Database.Status.Is_Ok (R), "page read failed");
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      R := Database.WAL.Append_Commit (W, 1, 1, L);
      Assert (Database.Status.Is_Ok (R), "wal append failed");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "wal flush failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "wal close failed");
      S := Database.Metrics.Snapshot_Metrics;
      Assert (S.Page_Reads >= 1, "page reads counted");
      Assert (S.Page_Writes >= 1, "page writes counted");
      Assert (S.WAL_Bytes_Written > 0, "wal bytes counted");
      Assert (S.WAL_Flush_Count = 1, "wal flush counted");
      Assert
        (Database.Tracing.Buffered_Count > 0,
         "storage or wal traces buffered");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("observability_metrics.database");
      Remove_File ("observability_metrics.database.wal");
   end Storage_And_WAL_Metrics;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Trace_Filter_And_Sink'Access, "trace filter and sink");
      Register_Routine
        (T, Sensitive_Trace_Filtering'Access, "sensitive trace filtering");
      Register_Routine
        (T, Metrics_And_Transactions'Access, "metrics transactions");
      Register_Routine (T, Events_Isolate_Handlers'Access, "event isolation");
      Register_Routine (T, Profile_Query_Rows'Access, "profile query rows");
      Register_Routine (T, Runtime_Diagnostics'Access, "runtime diagnostics");
      Register_Routine
        (T, Storage_And_WAL_Metrics'Access, "storage and wal metrics");
   end Register_Tests;
end Observability_Tests;
