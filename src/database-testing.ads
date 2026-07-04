--  Reliability verification helpers.
with Database.Status;
with Database.Fault_Injection;

--  Shared test and verification helpers.
package Database.Testing is
   --  Recovery_Expectation stores the public fields for this database abstraction.
   type Recovery_Expectation is record
      Committed_Data_Preserved : Boolean := True;
      Uncommitted_Data_Absent : Boolean := True;
      Indexes_Valid : Boolean := True;
      MVCC_Valid : Boolean := True;
      Encryption_Metadata_Valid : Boolean := True;
   end record;

   --  Recovery_Report stores the public fields for this database abstraction.
   type Recovery_Report is record
      Status : Database.Status.Result := Database.Status.Success;
      Deterministic : Boolean := True;
      Replayed_Records : Natural := 0;
      Violations : Natural := 0;
   end record;

   --  Return verify recovery for the supplied database state or arguments.
   --  @param First first argument supplied to the operation.
   --  @param Second second argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Recovery
     (First  : Recovery_Expectation;
      Second : Recovery_Expectation) return Recovery_Report;

   --  Return simulate crash and verify for the supplied database state or arguments.
   --  @param Point point argument supplied to the operation.
   --  @param Expected expected value used for validation.
   --  @return Result produced by the function.
   function Simulate_Crash_And_Verify
     (Point : Database.Fault_Injection.Crash_Point;
      Expected : Recovery_Expectation) return Recovery_Report;

   --  Build a real WAL, replay it twice into the same database file, and verify
   --  that replay converges to the same durable page image each time.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_WAL_Replay_Convergence return Recovery_Report;

   --  Validate that page corruption injected through File_IO is rejected by the
   --  page validation/check path and is reported as ordinary corruption.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Page_Corruption_Rejected return Recovery_Report;

   --  Validate encrypted-buffer tamper rejection using the same authentication
   --  helper used by encrypted storage diagnostics.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Encrypted_Tamper_Rejected return Recovery_Report;

   --  Exercise every declared crash point through the concrete subsystem hook
   --  or WAL boundary model, and fail if any crash point is only declared-but-unwired.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_All_Crash_Points return Recovery_Report;

   --  Exercise all non-crash fault kinds that have production/test hooks and
   --  verify they fail closed with structured status values.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Fault_Hooks return Recovery_Report;

   --  Create, close, reopen, replay, validate, backup, restore, and revalidate
   --  a real persistent database handle repeatedly. This is the concrete
   --  long-running recovery convergence hook used by hardening tests.
   --  @param Cycles cycles argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Open_Close_Recovery_Cycles
     (Cycles : Positive := 3) return Recovery_Report;

   --  Validate encryption metadata from a real encrypted database handle and
   --  verify that tampered metadata/authentication state is rejected without
   --  exposing plaintext or key material.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Encrypted_Metadata_Tamper_Rejected return Recovery_Report;

   --  Artifact-level security validation: corrupt real encrypted database,
   --  backup, WAL, and logical-export artifacts and verify that open, replay,
   --  restore, or import fail closed with structured status results.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Encrypted_Artifact_Tamper_Rejected return Recovery_Report;

   --  End-to-end recovery convergence validation.  This verifies that:
   --  * independent WAL replay targets converge to the same durable page image,
   --  * replaying the same committed WAL repeatedly is idempotent,
   --  * uncommitted WAL frames remain absent,
   --  * checkpoint/reopen converges,
   --  * physical backup/restore converges,
   --  * logical export/import converges, and
   --  * encrypted metadata survives reopen and rejects tamper checks.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Recovery_Convergence return Recovery_Report;

   --  End-to-end engine validation case: persistent typed table writes,
   --  secondary index creation, reopen, backup/restore, export/import,
   --  encryption metadata checks, and Validate_Database traversal.

   --  Full crash-simulation matrix.  Unlike Verify_All_Crash_Points, this
   --  validates each crash point against a durable table/index oracle: a
   --  committed row must survive reopen/replay, an uncommitted WAL frame must
   --  remain absent, page/index/MVCC invariants must traverse cleanly, and
   --  crash-created backup/restore/import/export artifacts must not be
   --  accepted as successful recovery sources.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Full_Crash_Simulation return Recovery_Report;

   --  Run the external process/power-loss crash harness through a separately
   --  built child executable.  This verifies real process termination, torn
   --  page/WAL artifacts, truncated encrypted-page artifacts, and partial
   --  backup manifests without falling back to in-process crash hooks.
   --  @param Child_Executable child executable argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_External_Process_Power_Loss_Crash
     (Child_Executable : String) return Recovery_Report;

   --  Return verify end to end engine validation for the supplied database state or arguments.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_End_To_End_Engine_Validation return Recovery_Report;
end Database.Testing;
