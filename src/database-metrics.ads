--  Low-overhead runtime counters and operational snapshots.
package Database.Metrics is
   --  Metrics_Snapshot stores the public fields for this database abstraction.
   type Metrics_Snapshot is record
      Transactions_Begun      : Natural := 0;
      Transactions_Committed  : Natural := 0;
      Transactions_Rolled_Back : Natural := 0;
      WAL_Bytes_Written       : Natural := 0;
      WAL_Flush_Count         : Natural := 0;
      WAL_Replay_Count        : Natural := 0;
      Checkpoint_Count        : Natural := 0;
      Checkpoint_Duration     : Natural := 0;
      Page_Reads              : Natural := 0;
      Page_Writes             : Natural := 0;
      Cache_Hits              : Natural := 0;
      Cache_Misses            : Natural := 0;
      Index_Lookups           : Natural := 0;
      Optimizer_Plans         : Natural := 0;
      Heap_Scan_Fallbacks     : Natural := 0;
      Query_Executions        : Natural := 0;
      Rows_Scanned            : Natural := 0;
      Rows_Returned           : Natural := 0;
      Full_Text_Queries       : Natural := 0;
      Backup_Count            : Natural := 0;
      Restore_Count           : Natural := 0;
      Export_Count            : Natural := 0;
      Import_Count            : Natural := 0;
      Encryption_Operations   : Natural := 0;
      Extension_Invocations   : Natural := 0;
      Lock_Waits              : Natural := 0;
      Blocked_Operations      : Natural := 0;
      Integrity_Checks        : Natural := 0;
      Validation_Failures     : Natural := 0;
      Fault_Injections       : Natural := 0;
      Invariant_Failures     : Natural := 0;
      Fuzzing_Failures       : Natural := 0;
      Verification_Failures  : Natural := 0;
   end record;

   --  Return snapshot metrics for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Snapshot_Metrics return Metrics_Snapshot;
   --  Perform reset metrics for the supplied database state or arguments.
   procedure Reset_Metrics;
   --  Perform increment transactions begun for the supplied database state or arguments.
   procedure Increment_Transactions_Begun;
   --  Perform increment transactions committed for the supplied database state or arguments.
   procedure Increment_Transactions_Committed;
   --  Perform increment transactions rolled back for the supplied database state or arguments.
   procedure Increment_Transactions_Rolled_Back;
   --  Perform add wal bytes for the supplied database state or arguments.
   --  @param Bytes byte data processed by the operation.
   procedure Add_WAL_Bytes (Bytes : Natural);
   --  Perform increment wal flushes for the supplied database state or arguments.
   procedure Increment_WAL_Flushes;
   --  Perform increment wal replays for the supplied database state or arguments.
   procedure Increment_WAL_Replays;
   --  Perform increment checkpoints for the supplied database state or arguments.
   --  @param Duration duration argument supplied to the operation.
   procedure Increment_Checkpoints (Duration : Natural := 0);
   --  Perform increment page reads for the supplied database state or arguments.
   procedure Increment_Page_Reads;
   --  Perform increment page writes for the supplied database state or arguments.
   procedure Increment_Page_Writes;
   --  Perform increment cache hits for the supplied database state or arguments.
   procedure Increment_Cache_Hits;
   --  Perform increment cache misses for the supplied database state or arguments.
   procedure Increment_Cache_Misses;
   --  Perform increment index lookups for the supplied database state or arguments.
   procedure Increment_Index_Lookups;
   --  Perform increment optimizer plans for the supplied database state or arguments.
   procedure Increment_Optimizer_Plans;
   --  Perform increment heap scan fallbacks for the supplied database state or arguments.
   procedure Increment_Heap_Scan_Fallbacks;
   --  Perform increment query executions for the supplied database state or arguments.
   procedure Increment_Query_Executions;
   --  Perform add rows scanned for the supplied database state or arguments.
   --  @param Rows rows argument supplied to the operation.
   procedure Add_Rows_Scanned (Rows : Natural);
   --  Perform add rows returned for the supplied database state or arguments.
   --  @param Rows rows argument supplied to the operation.
   procedure Add_Rows_Returned (Rows : Natural);
   --  Perform increment full text queries for the supplied database state or arguments.
   procedure Increment_Full_Text_Queries;
   --  Perform increment backups for the supplied database state or arguments.
   procedure Increment_Backups;
   --  Perform increment restores for the supplied database state or arguments.
   procedure Increment_Restores;
   --  Perform increment exports for the supplied database state or arguments.
   procedure Increment_Exports;
   --  Perform increment imports for the supplied database state or arguments.
   procedure Increment_Imports;
   --  Perform increment encryption operations for the supplied database state or arguments.
   procedure Increment_Encryption_Operations;
   --  Perform increment extension invocations for the supplied database state or arguments.
   procedure Increment_Extension_Invocations;
   --  Perform increment lock waits for the supplied database state or arguments.
   procedure Increment_Lock_Waits;
   --  Perform increment blocked operations for the supplied database state or arguments.
   procedure Increment_Blocked_Operations;
   --  Perform increment integrity checks for the supplied database state or arguments.
   procedure Increment_Integrity_Checks;
   --  Perform increment validation failures for the supplied database state or arguments.
   procedure Increment_Validation_Failures;
   --  Perform increment fault injections for the supplied database state or arguments.
   procedure Increment_Fault_Injections;
   --  Perform increment invariant failures for the supplied database state or arguments.
   procedure Increment_Invariant_Failures;
   --  Perform increment fuzzing failures for the supplied database state or arguments.
   procedure Increment_Fuzzing_Failures;
   --  Perform increment verification failures for the supplied database state or arguments.
   procedure Increment_Verification_Failures;
end Database.Metrics;
