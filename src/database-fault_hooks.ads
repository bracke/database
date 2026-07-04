--  Internal fault hook abstraction used by reliability builds.
--  Production subsystems depend on this neutral hook layer, not on the
--  public Database.Fault_Injection test-control package.
with Database.Status;

--  Public specification for this database subsystem.
package Database.Fault_Hooks is
   --  Fault_Kind defines a public database type used by this package.
   type Fault_Kind is
     (Fail_Page_Write,
      Fail_WAL_Flush,
      Truncate_WAL,
      Corrupt_Page,
      Corrupt_WAL_Frame,
      Fail_Checkpoint,
      Fail_Backup_Copy,
      Fail_Restore_Write,
      Fail_Import_Read,
      Fail_Encryption_Verification,
      Allocation_Failure,
      Random_IO_Failure,
      Partial_Metadata_Persistence);

   --  Crash_Point defines a public database type used by this package.
   type Crash_Point is
     (Before_WAL_Commit_Marker,
      After_WAL_Commit_Marker,
      During_Checkpoint,
      During_Page_Rewrite,
      During_Key_Rotation,
      During_Backup,
      During_Restore,
      During_Import,
      During_Export);

   --  Perform reset for the supplied database state or arguments.
   procedure Reset;
   --  Perform set seed for the supplied database state or arguments.
   --  @param Seed deterministic seed used for reproducible behavior.
   procedure Set_Seed (Seed : Natural);
   --  Return current seed for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Current_Seed return Natural;

   --  Perform enable fault for the supplied database state or arguments.
   --  @param Fault fault argument supplied to the operation.
   procedure Enable_Fault (Fault : Fault_Kind);
   --  Perform disable fault for the supplied database state or arguments.
   --  @param Fault fault argument supplied to the operation.
   procedure Disable_Fault (Fault : Fault_Kind);
   --  Return fault enabled for the supplied database state or arguments.
   --  @param Fault fault argument supplied to the operation.
   --  @return Result produced by the function.
   function Fault_Enabled (Fault : Fault_Kind) return Boolean;

   --  Perform arm fault after for the supplied database state or arguments.
   --  @param Fault fault argument supplied to the operation.
   --  @param Operations operations argument supplied to the operation.
   procedure Arm_Fault_After (Fault : Fault_Kind; Operations : Natural);
   --  Return should fail for the supplied database state or arguments.
   --  @param Fault fault argument supplied to the operation.
   --  @return Result produced by the function.
   function Should_Fail (Fault : Fault_Kind) return Boolean;

   --  Perform arm crash for the supplied database state or arguments.
   --  @param Point point argument supplied to the operation.
   procedure Arm_Crash (Point : Crash_Point);
   --  Perform clear crash for the supplied database state or arguments.
   --  @param Point point argument supplied to the operation.
   procedure Clear_Crash (Point : Crash_Point);
   --  Return crash armed for the supplied database state or arguments.
   --  @param Point point argument supplied to the operation.
   --  @return Result produced by the function.
   function Crash_Armed (Point : Crash_Point) return Boolean;
   --  Return should crash for the supplied database state or arguments.
   --  @param Point point argument supplied to the operation.
   --  @return Result produced by the function.
   function Should_Crash (Point : Crash_Point) return Boolean;

   --  Return injected failure for the supplied database state or arguments.
   --  @param Fault fault argument supplied to the operation.
   --  @return Result produced by the function.
   function Injected_Failure (Fault : Fault_Kind) return Database.Status.Result;
end Database.Fault_Hooks;
