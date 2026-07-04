with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Diagnostics;
with Database.Diagnostics.Runtime;
with Database.Events; use Database.Events;
with Database.Fault_Hooks;
with Database.Indexes;
with Database.Indexes.BTree;
with Database.Metrics;
with Database.Optional;
with Database.Profiling;
with Database.Queries;
with Database.Replay;
with Database.Rows;
with Database.Schema;
with Database.Statistics;
with Database.Status; use Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Pages;
with Database.Tracing;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Database.Versioning;
with Database.Visibility;

package body Support_Package_Tests is
   use AUnit.Assertions;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Database.Status.Status_Code;
   use type Database.Storage.Pages.Page_Id;
   use type Database.Versioning.Transaction_Id;
   use type Database.Versioning.Commit_Version;

   package Integer_Optional is new Database.Optional (Integer);

   Event_Count        : Natural := 0;
   Last_Event         : Database.Events.Event_Kind :=
     Database.Events.Transaction_Begin;
   Trace_Sink_Count   : Natural := 0;
   Last_Trace_Message : Unbounded_Wide_Wide_String :=
     Null_Unbounded_Wide_Wide_String;

   procedure Count_Event (Event : Database.Events.Operational_Event) is
   begin
      Event_Count := Event_Count + 1;
      Last_Event := Event.Kind;
   end Count_Event;

   procedure Bad_Event_Handler (Event : Database.Events.Operational_Event) is
      pragma Unreferenced (Event);
   begin
      raise Program_Error with "expected test hook failure";
   end Bad_Event_Handler;

   procedure Count_Trace (Event : Database.Tracing.Trace_Event) is
   begin
      Trace_Sink_Count := Trace_Sink_Count + 1;
      Last_Trace_Message := Event.Message;
   end Count_Trace;

   procedure Bad_Trace_Sink (Event : Database.Tracing.Trace_Event) is
      pragma Unreferenced (Event);
   begin
      raise Program_Error with "expected test hook failure";
   end Bad_Trace_Sink;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("behavioral support package contracts");
   end Name;

   procedure Remove_File (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_File;

   procedure Status_And_Optional_Contracts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Status.Result;
      N : Integer_Optional.Optional_Value;
      S : Integer_Optional.Optional_Value;
   begin
      R := Database.Status.Success;
      Assert (Database.Status.Is_Ok (R), "success result must be ok");
      Assert (R.Code = Database.Status.Ok, "success code must be Ok");
      Assert (Length (R.Message) = 0, "success message must be empty");

      R :=
        Database.Status.Failure
          (Database.Status.Invalid_Argument, "bad argument");
      Assert (not Database.Status.Is_Ok (R), "failure result must not be ok");
      Assert
        (R.Code = Database.Status.Invalid_Argument,
         "failure code must survive");
      Assert
        (To_Wide_Wide_String (R.Message) = "bad argument",
         "failure message must round trip");

      R :=
        Database.Status.Failure
          (Database.Status.Corrupt_Encrypted_WAL, "tampered wal");
      Assert
        (R.Code = Database.Status.Corrupt_Encrypted_WAL,
         "new status codes must be ordinary results");
      Assert
        (not Database.Status.Is_Ok (R), "new failure codes must be non-ok");

      N := Integer_Optional.None;
      S := Integer_Optional.With_Value (42);
      Assert (not Integer_Optional.Has_Value (N), "None must not have value");
      Assert (Integer_Optional.Has_Value (S), "Some must have value");
      Assert (Integer_Optional.Get (S) = 42, "Some value must round trip");

      S := Integer_Optional.With_Value (-17);
      Assert
        (Integer_Optional.Has_Value (S),
         "Some negative value must have value");
      Assert
        (Integer_Optional.Get (S) = -17,
         "Some negative value must round trip");
   end Status_And_Optional_Contracts;

   procedure Events_Dispatch_Error_And_Clear
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Status.Result;
   begin
      Database.Events.Clear_Handlers;
      Event_Count := 0;

      Database.Events.Subscribe (null);
      R := Database.Events.Emit (Database.Events.Backup_Start, "ignored");
      Assert
        (Database.Status.Is_Ok (R),
         "null subscription must be ignored safely");
      Assert (Event_Count = 0, "null handler must not be invoked");

      Database.Events.Subscribe (Count_Event'Access);
      R := Database.Events.Emit (Database.Events.Backup_Start, "support test");
      Assert (Database.Status.Is_Ok (R), "event dispatch should succeed");
      Assert (Event_Count = 1, "event handler must be invoked once");
      Assert
        (Last_Event = Database.Events.Backup_Start,
         "event kind must round trip");

      Database.Events.Clear_Handlers;
      R := Database.Events.Emit (Database.Events.Backup_End, "support test");
      Assert
        (Database.Status.Is_Ok (R),
         "event dispatch without handlers should succeed");
      Assert (Event_Count = 1, "cleared handlers must not be invoked");

      Database.Events.Clear_Handlers;
      Database.Events.Subscribe (Bad_Event_Handler'Access);
      R := Database.Events.Emit (Database.Events.Restore_End, "bad handler");
      Assert
        (R.Code = Database.Status.Event_Handler_Error,
         "bad event handler must be isolated as status failure");
      Database.Events.Clear_Handlers;
   end Events_Dispatch_Error_And_Clear;

   procedure Tracing_State_Filtering_And_Buffering
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R  : Database.Status.Result;
      E0 : Database.Tracing.Trace_Event;
      E1 : Database.Tracing.Trace_Event;
   begin
      Database.Tracing.Reset;
      Trace_Sink_Count := 0;
      Last_Trace_Message := Null_Unbounded_Wide_Wide_String;

      Assert (not Database.Tracing.Is_Enabled, "tracing must reset disabled");
      R :=
        Database.Tracing.Emit (Database.Tracing.Query_Trace, "disabled trace");
      Assert
        (Database.Status.Is_Ok (R),
         "disabled trace emission must be a safe no-op");
      Assert
        (Database.Tracing.Buffered_Count = 0,
         "disabled tracing must not buffer");

      Database.Tracing.Enable;
      Database.Tracing.Set_Custom_Sink (Count_Trace'Access);
      R :=
        Database.Tracing.Emit (Database.Tracing.Query_Trace, "visible trace");
      Assert (Database.Status.Is_Ok (R), "enabled trace must succeed");
      Assert (Trace_Sink_Count = 1, "custom sink must receive enabled trace");
      Assert
        (Database.Tracing.Buffered_Count = 1,
         "enabled trace must be buffered");
      E0 := Database.Tracing.Buffered_Event (0);
      Assert (E0.Timestamp = 1, "first trace timestamp must start at one");
      Assert
        (To_Wide_Wide_String (E0.Message) = "visible trace",
         "trace message must round trip");

      Database.Tracing.Disable_Category (Database.Tracing.Query_Trace);
      Assert
        (not Database.Tracing.Category_Enabled (Database.Tracing.Query_Trace),
         "category disable must be visible");
      R :=
        Database.Tracing.Emit (Database.Tracing.Query_Trace, "filtered trace");
      Assert (Database.Status.Is_Ok (R), "filtered trace must return success");
      Assert (Trace_Sink_Count = 1, "filtered trace must not reach sink");
      Assert
        (Database.Tracing.Buffered_Count = 1,
         "filtered trace must not be buffered");

      Database.Tracing.Enable_Category (Database.Tracing.Query_Trace);
      R :=
        Database.Tracing.Emit (Database.Tracing.Query_Trace, "second trace");
      Assert (Database.Status.Is_Ok (R), "reenabled trace must succeed");
      E1 := Database.Tracing.Buffered_Event (1);
      Assert (E1.Timestamp = 2, "trace timestamps must be monotonic");

      Database.Tracing.Clear_Buffer;
      Assert
        (Database.Tracing.Buffered_Count = 0,
         "clear buffer must remove buffered traces");

      Database.Tracing.Set_Custom_Sink (Bad_Trace_Sink'Access);
      R := Database.Tracing.Emit (Database.Tracing.Storage_Trace, "bad sink");
      Assert
        (R.Code = Database.Status.Event_Handler_Error,
         "bad trace sink must be isolated as status failure");
      Database.Tracing.Reset;
   end Tracing_State_Filtering_And_Buffering;

   procedure Tracing_Sensitive_And_File_Sink
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R    : Database.Status.Result;
      Path : constant String := "support_trace.log";
   begin
      Remove_File (Path);
      Database.Tracing.Reset;
      Database.Tracing.Enable;

      R :=
        Database.Tracing.Emit
          (Database.Tracing.Encryption_Trace, "plaintext key material", True);
      Assert (Database.Status.Is_Ok (R), "sensitive trace must emit safely");
      Assert
        (To_Wide_Wide_String (Database.Tracing.Buffered_Event (0).Message)
         = "[sensitive trace suppressed]",
         "sensitive traces must be redacted by default");

      Database.Tracing.Enable_Sensitive_Traces;
      Assert
        (Database.Tracing.Sensitive_Traces_Enabled,
         "sensitive trace flag must be enabled");
      R :=
        Database.Tracing.Emit
          (Database.Tracing.Encryption_Trace, "explicit diagnostic", True);
      Assert
        (Database.Status.Is_Ok (R),
         "enabled sensitive trace must emit safely");
      Assert
        (To_Wide_Wide_String (Database.Tracing.Buffered_Event (1).Message)
         = "explicit diagnostic",
         "enabled sensitive traces must preserve explicit diagnostic text");
      Database.Tracing.Disable_Sensitive_Traces;
      Assert
        (not Database.Tracing.Sensitive_Traces_Enabled,
         "sensitive trace flag must be disabled");

      R := Database.Tracing.Enable_File_Sink (Path);
      Assert (Database.Status.Is_Ok (R), "file trace sink must open");
      R :=
        Database.Tracing.Emit
          (Database.Tracing.Storage_Trace, "file sink trace");
      Assert (Database.Status.Is_Ok (R), "file sink trace must write");
      Database.Tracing.Disable_File_Sink;
      Assert
        (Ada.Directories.Exists (Path), "file trace sink must create file");
      Remove_File (Path);
      Database.Tracing.Reset;
   end Tracing_Sensitive_And_File_Sink;

   procedure Metrics_All_Counters_Are_Behavioral
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Database.Metrics.Metrics_Snapshot;
   begin
      Database.Metrics.Reset_Metrics;
      S := Database.Metrics.Snapshot_Metrics;
      Assert
        (S.Transactions_Begun = 0 and then S.Verification_Failures = 0,
         "metrics reset must zero edge counters");

      Database.Metrics.Increment_Transactions_Begun;
      Database.Metrics.Increment_Transactions_Committed;
      Database.Metrics.Increment_Transactions_Rolled_Back;
      Database.Metrics.Add_WAL_Bytes (17);
      Database.Metrics.Increment_WAL_Flushes;
      Database.Metrics.Increment_WAL_Replays;
      Database.Metrics.Increment_Checkpoints (5);
      Database.Metrics.Increment_Page_Reads;
      Database.Metrics.Increment_Page_Writes;
      Database.Metrics.Increment_Cache_Hits;
      Database.Metrics.Increment_Cache_Misses;
      Database.Metrics.Increment_Index_Lookups;
      Database.Metrics.Increment_Optimizer_Plans;
      Database.Metrics.Increment_Heap_Scan_Fallbacks;
      Database.Metrics.Increment_Query_Executions;
      Database.Metrics.Add_Rows_Scanned (11);
      Database.Metrics.Add_Rows_Returned (7);
      Database.Metrics.Increment_Full_Text_Queries;
      Database.Metrics.Increment_Backups;
      Database.Metrics.Increment_Restores;
      Database.Metrics.Increment_Exports;
      Database.Metrics.Increment_Imports;
      Database.Metrics.Increment_Encryption_Operations;
      Database.Metrics.Increment_Extension_Invocations;
      Database.Metrics.Increment_Lock_Waits;
      Database.Metrics.Increment_Blocked_Operations;
      Database.Metrics.Increment_Integrity_Checks;
      Database.Metrics.Increment_Validation_Failures;
      Database.Metrics.Increment_Fault_Injections;
      Database.Metrics.Increment_Invariant_Failures;
      Database.Metrics.Increment_Fuzzing_Failures;
      Database.Metrics.Increment_Verification_Failures;

      S := Database.Metrics.Snapshot_Metrics;
      Assert (S.Transactions_Begun = 1, "transactions begun counter");
      Assert (S.Transactions_Committed = 1, "transactions committed counter");
      Assert
        (S.Transactions_Rolled_Back = 1, "transactions rolled back counter");
      Assert (S.WAL_Bytes_Written = 17, "wal bytes counter");
      Assert (S.WAL_Flush_Count = 1, "wal flush counter");
      Assert (S.WAL_Replay_Count = 1, "wal replay counter");
      Assert
        (S.Checkpoint_Count = 1 and then S.Checkpoint_Duration = 5,
         "checkpoint counters");
      Assert (S.Page_Reads = 1 and then S.Page_Writes = 1, "page counters");
      Assert (S.Cache_Hits = 1 and then S.Cache_Misses = 1, "cache counters");
      Assert (S.Index_Lookups = 1, "index lookup counter");
      Assert (S.Optimizer_Plans = 1, "optimizer plan counter");
      Assert (S.Heap_Scan_Fallbacks = 1, "heap scan fallback counter");
      Assert (S.Query_Executions = 1, "query execution counter");
      Assert
        (S.Rows_Scanned = 11 and then S.Rows_Returned = 7, "row counters");
      Assert (S.Full_Text_Queries = 1, "full-text counter");
      Assert
        (S.Backup_Count = 1 and then S.Restore_Count = 1,
         "backup restore counters");
      Assert
        (S.Export_Count = 1 and then S.Import_Count = 1,
         "export import counters");
      Assert (S.Encryption_Operations = 1, "encryption counter");
      Assert (S.Extension_Invocations = 1, "extension counter");
      Assert
        (S.Lock_Waits = 1 and then S.Blocked_Operations = 1, "lock counters");
      Assert
        (S.Integrity_Checks = 1 and then S.Validation_Failures = 1,
         "validation counters");
      Assert
        (S.Fault_Injections = 1 and then S.Invariant_Failures = 1,
         "hardening counters");
      Assert
        (S.Fuzzing_Failures = 1 and then S.Verification_Failures = 1,
         "verification counters");

      Database.Metrics.Reset_Metrics;
      S := Database.Metrics.Snapshot_Metrics;
      Assert
        (S.Transactions_Begun = 0 and then S.Verification_Failures = 0,
         "second reset must zero edge counters");
   end Metrics_All_Counters_Are_Behavioral;

   procedure Profiling_Reports_And_Metrics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Q   : Database.Queries.Query := Database.Queries.Empty;
      Row : Database.Rows.Row;
      P   : Database.Profiling.Query_Profile;
      R   : Database.Status.Result;
      S   : Database.Metrics.Metrics_Snapshot;
   begin
      Database.Metrics.Reset_Metrics;
      Database.Rows.Append (Row, Database.Values.From_Integer (42));
      Database.Rows.Append (Row, Database.Values.From_Text ("profile"));
      Database.Queries.Append (Q, Row);
      Database.Queries.Disable_Optimizer (Q);

      R := Database.Profiling.Try_Profile_Query (Q, P);
      Assert (Database.Status.Is_Ok (R), "try profile query must succeed");
      Assert
        (P.Rows_Scanned = 1 and then P.Rows_Returned = 1,
         "profile must report row counts");
      Assert
        (P.Index_Lookups = 0, "empty profile must not invent index lookups");
      Assert
        (Natural (P.Operators.Length) = 1,
         "profile must include operator profile");
      Assert
        (To_Wide_Wide_String (P.Operators.Element (0).Name) = "rows",
         "operator name must be stable");
      Assert
        (To_Wide_Wide_String (P.Optimizer_Decision) = "optimizer disabled",
         "optimizer decision must reflect query flag");

      Database.Queries.Enable_Optimizer (Q);
      P := Database.Profiling.Profile_Query (Q);
      Assert
        (To_Wide_Wide_String (P.Optimizer_Decision) = "optimizer enabled",
         "optimizer-enabled profile must be reported");
      S := Database.Metrics.Snapshot_Metrics;
      Assert
        (S.Query_Executions = 2,
         "profiling must increment query execution metrics");
      Assert
        (S.Rows_Scanned = 2 and then S.Rows_Returned = 2,
         "profiling must increment row metrics");
   end Profiling_Reports_And_Metrics;

   procedure Runtime_Diagnostics_Reflect_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Read_Tx  : Database.Transactions.Transaction;
      Write_Tx : Database.Transactions.Transaction;
      D        : Database.Diagnostics.Runtime.Transaction_Diagnostics;
      Cache    : Database.Diagnostics.Runtime.Cache_Diagnostics;
      R        : Database.Status.Result;
   begin
      Database.Metrics.Reset_Metrics;
      Database.Metrics.Increment_Page_Reads;
      Database.Metrics.Increment_Page_Writes;
      Database.Metrics.Increment_Cache_Hits;
      Database.Metrics.Increment_Cache_Misses;
      Cache := Database.Diagnostics.Runtime.Cache_Statistics;
      Assert
        (Cache.Page_Reads = 1 and then Cache.Page_Writes = 1,
         "runtime cache diagnostics must mirror metrics");
      Assert
        (Cache.Cache_Hits = 1 and then Cache.Cache_Misses = 1,
         "runtime cache hit/miss diagnostics must mirror metrics");

      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Read_Tx);
      D := Database.Diagnostics.Runtime.Active_Transactions (DB);
      Assert (D.Active_Readers = 1, "active reader must be visible");
      Assert
        (not D.Writer_Active,
         "writer must not be active during read-only transaction");
      Assert
        (Database.Diagnostics.Runtime.Lock_Statistics (DB).Active_Readers = 1,
         "lock statistics must mirror active transactions");
      R := Database.Transactions.Commit (Read_Tx);
      Assert
        (Database.Status.Is_Ok (R), "read transaction commit must succeed");

      Database.Transactions.Begin_Write (DB, Write_Tx);
      D := Database.Diagnostics.Runtime.Active_Transactions (DB);
      Assert
        (D.Writer_Active, "writer must be visible during write transaction");
      R := Database.Transactions.Rollback (Write_Tx);
      Assert
        (Database.Status.Is_Ok (R), "write transaction rollback must succeed");
      D := Database.Diagnostics.Runtime.Active_Transactions (DB);
      Assert
        (not D.Writer_Active and then D.Active_Readers = 0,
         "transactions must clear after rollback");
      Assert
        (not Database.Diagnostics.Runtime.WAL_State (DB).Exists,
         "in-memory database must not report WAL file");
      Database.Close (DB);
   end Runtime_Diagnostics_Reflect_State;

   procedure Diagnostics_Basic_Database_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;
   begin
      S.Name := To_Unbounded_Wide_Wide_String ("diag_support");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);

      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      Assert
        (Database.Diagnostics.Page_Count (Tx) = 0,
         "in-memory page count must be zero");
      Assert
        (Database.Diagnostics.Free_Page_Count (Tx) = 0,
         "in-memory free page count must be zero");
      Assert
        (Database.Diagnostics.Database_Size (Tx) = 0,
         "in-memory database size must be zero");
      Assert
        (Database.Diagnostics.Table_Row_Count (Tx, S) = 0,
         "unregistered in-memory table row count must be zero");
      Assert
        (Database.Diagnostics.Table_Page_Count (Tx, S) = 0,
         "unregistered in-memory table page count must be zero");
      Assert
        (not Database.Diagnostics.Encryption_Enabled (DB),
         "plain in-memory database must not report encryption");
      Assert
        (Database.Diagnostics.Encryption_Format_Version (DB) = 0,
         "plain database encryption format must be zero");
      Assert
        (not Database.Diagnostics.WAL_Encryption_Enabled (DB),
         "plain database wal encryption must be false");
      Assert
        (Database.Diagnostics.Full_Text_Index_Count >= 0,
         "full-text diagnostics must be callable");
      Assert
        (Database.Diagnostics.Full_Text_Term_Count ("missing_index") = 0,
         "missing full-text term count must be zero");
      R := Database.Transactions.Commit (Tx);
      Assert
        (Database.Status.Is_Ok (R),
         "diagnostic read transaction commit must succeed");
      Database.Close (DB);
   end Diagnostics_Basic_Database_State;

   procedure Fault_Hooks_Are_Deterministic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Status.Result;
   begin
      Database.Fault_Hooks.Reset;
      Database.Fault_Hooks.Set_Seed (12345);
      Assert
        (Database.Fault_Hooks.Current_Seed = 12345,
         "fault seed must round trip");
      Database.Fault_Hooks.Arm_Fault_After
        (Database.Fault_Hooks.Fail_Page_Write, 1);
      Assert
        (Database.Fault_Hooks.Fault_Enabled
           (Database.Fault_Hooks.Fail_Page_Write),
         "fault must be armed");
      Assert
        (not Database.Fault_Hooks.Should_Fail
               (Database.Fault_Hooks.Fail_Page_Write),
         "fault must wait for countdown");
      Assert
        (Database.Fault_Hooks.Should_Fail
           (Database.Fault_Hooks.Fail_Page_Write),
         "fault must fire deterministically");
      Assert
        (not Database.Fault_Hooks.Should_Fail
               (Database.Fault_Hooks.Fail_Page_Write),
         "one-shot fault must be consumed");
      Database.Fault_Hooks.Arm_Crash (Database.Fault_Hooks.During_Checkpoint);
      Assert
        (Database.Fault_Hooks.Crash_Armed
           (Database.Fault_Hooks.During_Checkpoint),
         "crash point must be armed");
      Assert
        (Database.Fault_Hooks.Should_Crash
           (Database.Fault_Hooks.During_Checkpoint),
         "crash point must fire");
      Assert
        (not Database.Fault_Hooks.Should_Crash
               (Database.Fault_Hooks.During_Checkpoint),
         "crash point must be consumed");
      R :=
        Database.Fault_Hooks.Injected_Failure
          (Database.Fault_Hooks.Fail_Page_Write);
      Assert
        (R.Code = Database.Status.Fault_Injection_Error,
         "injected failure must use status result");
      Database.Fault_Hooks.Reset;
   end Fault_Hooks_Are_Deterministic;

   procedure Replay_Validates_Absent_WAL
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "support_replay_absent.db";
      F    : Database.Storage.File_IO.File_Handle;
      R    : Database.Status.Result;
   begin
      Remove_File ("support_replay_absent.db");
      Remove_File ("support_replay_absent.db.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "file create must succeed");
      R := Database.Replay.Validate_WAL (Path);
      Assert (Database.Status.Is_Ok (R), "absent WAL must validate as no-op");
      R := Database.Replay.Replay_WAL (Path, F);
      Assert (Database.Status.Is_Ok (R), "absent WAL replay must be no-op");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close must succeed");
      Remove_File ("support_replay_absent.db");
   end Replay_Validates_Absent_WAL;

   procedure Versioning_And_Visibility_Rules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      V  : Database.Versioning.Row_Version_Metadata;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      V :=
        Database.Versioning.New_Committed
          (Database.Transactions.Snapshot_Version (Tx));
      Assert (V.Flags.Committed, "committed version flag must be set");
      Assert
        (Database.Visibility.Is_Visible (Tx, V),
         "committed snapshot version must be visible");
      Database.Versioning.Mark_Deleted
        (V,
         Database.Transactions.Id (Tx),
         Database.Transactions.Snapshot_Version (Tx));
      Assert
        (Database.Visibility.Is_Deleted_For (Tx, V),
         "own delete must be visible as deleted");
      Assert
        (Database.Visibility.Is_Own_Write (Tx, V),
         "own delete must count as own write");
      Database.Versioning.Clear_Delete (V);
      Assert
        (not Database.Visibility.Is_Deleted_For (Tx, V),
         "cleared delete must not be visible");
      R := Database.Transactions.Commit (Tx);
      Assert
        (Database.Status.Is_Ok (R), "read transaction commit must succeed");
      Database.Close (DB);
   end Versioning_And_Visibility_Rules;

   procedure Statistics_Analyze_No_Op_Is_Statused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      TS : Database.Statistics.Table_Statistic;
      R  : Database.Status.Result;
   begin
      S.Name := To_Unbounded_Wide_Wide_String ("stats_support");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      TS := Database.Statistics.Table_Stats (Tx, S);
      Assert
        (TS.Row_Count = 0, "empty unregistered table stats must be zero rows");
      R := Database.Statistics.Analyze (Tx);
      Assert (Database.Status.Is_Ok (R), "analyze must return status success");
      R := Database.Statistics.Analyze_Table (Tx, "stats_support");
      Assert
        (Database.Status.Is_Ok (R),
         "analyze table must return status success");
      R := Database.Transactions.Commit (Tx);
      Assert
        (Database.Status.Is_Ok (R), "read transaction commit must succeed");
      Database.Close (DB);
   end Statistics_Analyze_No_Op_Is_Statused;

   procedure BTree_Create_Find_Validate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path      : constant Wide_Wide_String := "support_btree.db";
      DB        : Database.Handle;
      Tx        : Database.Transactions.Transaction;
      F         : Database.Storage.File_IO.File_Handle;
      Allocator : Database.Storage.Free_List.Allocator;
      Root      : Database.Storage.Pages.Page_Id;
      Ref       : Database.Indexes.Row_Reference;
      Found     : Database.Indexes.Row_Reference;
      R         : Database.Status.Result;
   begin
      Remove_File ("support_btree.db");
      Remove_File ("support_btree.db.wal");
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Write (DB, Tx);
      R := Database.Storage.File_IO.Create (F, Path);
      Assert
        (Database.Status.Is_Ok (R), "btree backing file create must succeed");
      Database.Storage.Free_List.Initialize_From_File (Allocator, F);
      R := Database.Indexes.BTree.Create (Tx, F, Allocator, Root);
      Assert (Database.Status.Is_Ok (R), "btree create must succeed");
      Assert
        (Root /= Database.Storage.Pages.Invalid_Page_Id,
         "btree root must be allocated");
      Ref := (Page => 3, Slot_Offset => 1);
      R :=
        Database.Indexes.BTree.Insert
          (Tx, F, Allocator, Root, Database.Values.From_Integer (7), Ref);
      Assert (Database.Status.Is_Ok (R), "btree insert must succeed");
      R :=
        Database.Indexes.BTree.Find
          (F, Root, Database.Values.From_Integer (7), Found);
      Assert (Database.Status.Is_Ok (R), "btree find must succeed");
      Assert
        (Found.Page = Ref.Page and then Found.Slot_Offset = Ref.Slot_Offset,
         "btree reference must round trip");
      R := Database.Indexes.BTree.Validate (F, Root);
      Assert (Database.Status.Is_Ok (R), "btree validate must succeed");
      R := Database.Storage.File_IO.Close (F);
      Assert
        (Database.Status.Is_Ok (R), "btree backing file close must succeed");
      R := Database.Transactions.Commit (Tx);
      Assert
        (Database.Status.Is_Ok (R), "write transaction commit must succeed");
      Database.Close (DB);
      Remove_File ("support_btree.db");
      Remove_File ("support_btree.db.wal");
   end BTree_Create_Find_Validate;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Status_And_Optional_Contracts'Access,
         "status and optional behavioral contracts");
      Register_Routine
        (T,
         Events_Dispatch_Error_And_Clear'Access,
         "events dispatch error and clear behavior");
      Register_Routine
        (T,
         Tracing_State_Filtering_And_Buffering'Access,
         "tracing state filtering and buffering behavior");
      Register_Routine
        (T,
         Tracing_Sensitive_And_File_Sink'Access,
         "tracing sensitive and file sink behavior");
      Register_Routine
        (T,
         Metrics_All_Counters_Are_Behavioral'Access,
         "all metrics counters behavior");
      Register_Routine
        (T,
         Profiling_Reports_And_Metrics'Access,
         "profiling reports rows and metrics behavior");
      Register_Routine
        (T,
         Runtime_Diagnostics_Reflect_State'Access,
         "runtime diagnostics reflect transaction and cache state");
      Register_Routine
        (T,
         Diagnostics_Basic_Database_State'Access,
         "diagnostics basic database state behavior");
      Register_Routine
        (T,
         Fault_Hooks_Are_Deterministic'Access,
         "fault hooks deterministic behavior");
      Register_Routine
        (T,
         Replay_Validates_Absent_WAL'Access,
         "replay absent wal is safe no-op");
      Register_Routine
        (T,
         Versioning_And_Visibility_Rules'Access,
         "versioning and visibility contracts");
      Register_Routine
        (T,
         Statistics_Analyze_No_Op_Is_Statused'Access,
         "statistics analyze returns status");
      Register_Routine
        (T, BTree_Create_Find_Validate'Access, "btree create find validate");
   end Register_Tests;
end Support_Package_Tests;
