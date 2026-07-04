--  External process and power-loss crash harness for hardening.
--
--  This package deliberately separates the parent verifier from the child
--  crash actor.  The parent runs a separate executable, observes that it
--  terminates abruptly, then reopens and validates durable artifacts.  The
--  child writes real database/WAL/page artifacts and exits through OS_Exit
--  without normal database finalization to approximate process death.
with Database.Status;
with Database.Testing;

--  Public specification for this database subsystem.
package Database.Crash_Harness is
   --  External_Crash_Mode defines a public database type used by this package.
   type External_Crash_Mode is
     (Process_Before_WAL_Commit,
      Process_After_WAL_Commit,
      Process_During_Checkpoint,
      Power_Loss_Torn_Page,
      Power_Loss_Torn_WAL_Frame,
      Power_Loss_Truncated_Encrypted_Page,
      Power_Loss_Partial_Backup_Manifest);

   --  Harness_Report stores the public fields for this database abstraction.
   type Harness_Report is record
      Status             : Database.Status.Result := Database.Status.Success;
      Child_Exit_Status  : Integer := 0;
      Artifact_Checked   : Boolean := False;
      Recovery_Checked   : Boolean := False;
      Corruption_Rejected : Boolean := False;
      Violations         : Natural := 0;
   end record;

   --  Run one crash scenario in an already-built child executable.
   --  Child_Executable is intentionally explicit so production builds have no
   --  dependency on the test child.  The executable must implement Child_Main.
   --  @param Child_Executable child executable argument supplied to the operation.
   --  @param Work_Path work path argument supplied to the operation.
   --  @param Mode mode argument supplied to the operation.
   --  @return Result produced by the function.
   function Run_External_Crash
     (Child_Executable : String;
      Work_Path        : Wide_Wide_String;
      Mode             : External_Crash_Mode) return Harness_Report;

   --  Run all external-process and power-loss scenarios using the supplied
   --  child executable and return an aggregate report.
   --  @param Child_Executable child executable argument supplied to the operation.
   --  @param Work_Prefix work prefix argument supplied to the operation.
   --  @return Result produced by the function.
   function Run_All_External_Crashes
     (Child_Executable : String;
      Work_Prefix      : Wide_Wide_String := "external_crash") return Harness_Report;

   --  Child-side entry point.  A tiny standalone main calls this procedure.
   --  It parses command-line arguments, writes the requested artifact, and
   --  terminates abruptly with OS_Exit.  It does not return on success.
   procedure Child_Main;

   --  Testing facade used by Database.Testing and AUnit.  If Child_Executable
   --  is empty, the function returns Verification_Failure instead of silently
   --  falling back to in-process simulation.
   --  @param Child_Executable child executable argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_External_Process_Power_Loss
     (Child_Executable : String) return Database.Testing.Recovery_Report;
end Database.Crash_Harness;
