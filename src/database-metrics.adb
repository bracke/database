package body Database.Metrics is
   protected Store is
      procedure Reset;
      function Snapshot return Metrics_Snapshot;
      procedure Add (Field : Positive; Amount : Natural := 1);
   private
      S : Metrics_Snapshot;
   end Store;

   protected body Store is
      procedure Reset is
      begin
         S := (others => 0);
      end Reset;
      function Snapshot return Metrics_Snapshot is (S);
      procedure Add (Field : Positive; Amount : Natural := 1) is
      begin
         case Field is
            when 1 => S.Transactions_Begun := S.Transactions_Begun + Amount;
            when 2 => S.Transactions_Committed := S.Transactions_Committed + Amount;
            when 3 => S.Transactions_Rolled_Back := S.Transactions_Rolled_Back + Amount;
            when 4 => S.WAL_Bytes_Written := S.WAL_Bytes_Written + Amount;
            when 5 => S.WAL_Flush_Count := S.WAL_Flush_Count + Amount;
            when 6 => S.WAL_Replay_Count := S.WAL_Replay_Count + Amount;
            when 7 =>
               S.Checkpoint_Count := S.Checkpoint_Count + 1;
               S.Checkpoint_Duration := S.Checkpoint_Duration + Amount;
            when 8 => S.Page_Reads := S.Page_Reads + Amount;
            when 9 => S.Page_Writes := S.Page_Writes + Amount;
            when 10 => S.Cache_Hits := S.Cache_Hits + Amount;
            when 11 => S.Cache_Misses := S.Cache_Misses + Amount;
            when 12 => S.Index_Lookups := S.Index_Lookups + Amount;
            when 13 => S.Optimizer_Plans := S.Optimizer_Plans + Amount;
            when 14 => S.Heap_Scan_Fallbacks := S.Heap_Scan_Fallbacks + Amount;
            when 15 => S.Query_Executions := S.Query_Executions + Amount;
            when 16 => S.Rows_Scanned := S.Rows_Scanned + Amount;
            when 17 => S.Rows_Returned := S.Rows_Returned + Amount;
            when 18 => S.Full_Text_Queries := S.Full_Text_Queries + Amount;
            when 19 => S.Backup_Count := S.Backup_Count + Amount;
            when 20 => S.Restore_Count := S.Restore_Count + Amount;
            when 21 => S.Export_Count := S.Export_Count + Amount;
            when 22 => S.Import_Count := S.Import_Count + Amount;
            when 23 => S.Encryption_Operations := S.Encryption_Operations + Amount;
            when 24 => S.Extension_Invocations := S.Extension_Invocations + Amount;
            when 25 => S.Lock_Waits := S.Lock_Waits + Amount;
            when 26 => S.Blocked_Operations := S.Blocked_Operations + Amount;
            when 27 => S.Integrity_Checks := S.Integrity_Checks + Amount;
            when 28 => S.Validation_Failures := S.Validation_Failures + Amount;
            when 29 => S.Fault_Injections := S.Fault_Injections + Amount;
            when 30 => S.Invariant_Failures := S.Invariant_Failures + Amount;
            when 31 => S.Fuzzing_Failures := S.Fuzzing_Failures + Amount;
            when 32 => S.Verification_Failures := S.Verification_Failures + Amount;
            when others => null;
         end case;
      end Add;
   end Store;

   function Snapshot_Metrics return Metrics_Snapshot is (Store.Snapshot);
   procedure Reset_Metrics is
   begin
      Store.Reset;
   end Reset_Metrics;
   procedure Increment_Transactions_Begun is
   begin
      Store.Add (1);
   end Increment_Transactions_Begun;
   procedure Increment_Transactions_Committed is
   begin
      Store.Add (2);
   end Increment_Transactions_Committed;
   procedure Increment_Transactions_Rolled_Back is
   begin
      Store.Add (3);
   end Increment_Transactions_Rolled_Back;
   procedure Add_WAL_Bytes (Bytes : Natural) is
   begin
      Store.Add (4, Bytes);
   end Add_WAL_Bytes;
   procedure Increment_WAL_Flushes is
   begin
      Store.Add (5);
   end Increment_WAL_Flushes;
   procedure Increment_WAL_Replays is
   begin
      Store.Add (6);
   end Increment_WAL_Replays;
   procedure Increment_Checkpoints (Duration : Natural := 0) is
   begin
      Store.Add (7, Duration);
   end Increment_Checkpoints;
   procedure Increment_Page_Reads is
   begin
      Store.Add (8);
   end Increment_Page_Reads;
   procedure Increment_Page_Writes is
   begin
      Store.Add (9);
   end Increment_Page_Writes;
   procedure Increment_Cache_Hits is
   begin
      Store.Add (10);
   end Increment_Cache_Hits;
   procedure Increment_Cache_Misses is
   begin
      Store.Add (11);
   end Increment_Cache_Misses;
   procedure Increment_Index_Lookups is
   begin
      Store.Add (12);
   end Increment_Index_Lookups;
   procedure Increment_Optimizer_Plans is
   begin
      Store.Add (13);
   end Increment_Optimizer_Plans;
   procedure Increment_Heap_Scan_Fallbacks is
   begin
      Store.Add (14);
   end Increment_Heap_Scan_Fallbacks;
   procedure Increment_Query_Executions is
   begin
      Store.Add (15);
   end Increment_Query_Executions;
   procedure Add_Rows_Scanned (Rows : Natural) is
   begin
      Store.Add (16, Rows);
   end Add_Rows_Scanned;
   procedure Add_Rows_Returned (Rows : Natural) is
   begin
      Store.Add (17, Rows);
   end Add_Rows_Returned;
   procedure Increment_Full_Text_Queries is
   begin
      Store.Add (18);
   end Increment_Full_Text_Queries;
   procedure Increment_Backups is
   begin
      Store.Add (19);
   end Increment_Backups;
   procedure Increment_Restores is
   begin
      Store.Add (20);
   end Increment_Restores;
   procedure Increment_Exports is
   begin
      Store.Add (21);
   end Increment_Exports;
   procedure Increment_Imports is
   begin
      Store.Add (22);
   end Increment_Imports;
   procedure Increment_Encryption_Operations is
   begin
      Store.Add (23);
   end Increment_Encryption_Operations;
   procedure Increment_Extension_Invocations is
   begin
      Store.Add (24);
   end Increment_Extension_Invocations;
   procedure Increment_Lock_Waits is
   begin
      Store.Add (25);
   end Increment_Lock_Waits;
   procedure Increment_Blocked_Operations is
   begin
      Store.Add (26);
   end Increment_Blocked_Operations;
   procedure Increment_Integrity_Checks is
   begin
      Store.Add (27);
   end Increment_Integrity_Checks;
   procedure Increment_Validation_Failures is
   begin
      Store.Add (28);
   end Increment_Validation_Failures;
   procedure Increment_Fault_Injections is
   begin
      Store.Add (29);
   end Increment_Fault_Injections;
   procedure Increment_Invariant_Failures is
   begin
      Store.Add (30);
   end Increment_Invariant_Failures;
   procedure Increment_Fuzzing_Failures is
   begin
      Store.Add (31);
   end Increment_Fuzzing_Failures;
   procedure Increment_Verification_Failures is
   begin
      Store.Add (32);
   end Increment_Verification_Failures;
end Database.Metrics;
