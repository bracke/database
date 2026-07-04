--  Deterministic stress-workload descriptions and runners.
with Database.Status;

--  Bounded deterministic stress workload runner.
package Database.Stress is
   --  Workload_Options stores the public fields for this database abstraction.
   type Workload_Options is record
      Seed : Natural := 1;
      Operations : Natural := 100;
      Allow_Checkpoints : Boolean := True;
      Allow_Backups : Boolean := True;
      Allow_Vacuum : Boolean := True;
      Allow_Rollback : Boolean := True;
   end record;

   --  Stress_Budget stores the public fields for this database abstraction.
   type Stress_Budget is record
      --  Hard caps used by the bounded stress harness. These bounds are
      --  checked by the runner and reported as Verification_Failure if a
      --  workload would exceed them. They make long-running reliability
      --  tests deterministic and suitable for CI as well as overnight runs.
      Max_Seeds                  : Positive := 4;
      Max_Operations_Per_Seed    : Positive := 128;
      Max_Page_File_Checks       : Positive := 64;
      Max_Backup_Restore_Cycles  : Natural := 8;
      Max_Export_Import_Cycles   : Natural := 8;
      Max_Recovery_Cycles        : Natural := 8;
      Max_Concurrent_Readers     : Natural := 4;
      Max_Writers                : Natural := 1;
   end record;

   --  Stress_Report stores the public fields for this database abstraction.
   type Stress_Report is record
      Status : Database.Status.Result := Database.Status.Success;
      Seed : Natural := 1;
      Operations_Attempted : Natural := 0;
      Seeds_Executed : Natural := 0;
      Budget_Violations : Natural := 0;
      Reader_Cycles : Natural := 0;
      Writer_Cycles : Natural := 0;
      Recovery_Cycles : Natural := 0;
      Commits : Natural := 0;
      Rollbacks : Natural := 0;
      Checkpoints : Natural := 0;
      Backups : Natural := 0;
      Restores : Natural := 0;
      Page_File_Checks : Natural := 0;
      Table_Workloads : Natural := 0;
      Schema_Workloads : Natural := 0;
      Index_Workloads : Natural := 0;
      Full_Text_Workloads : Natural := 0;
      Encryption_Workloads : Natural := 0;
      Export_Import_Cycles : Natural := 0;
      Verification_Failures : Natural := 0;
   end record;

   --  Return run deterministic for the supplied database state or arguments.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Run_Deterministic (Options : Workload_Options) return Stress_Report;

   --  Run a bounded matrix of deterministic stress workloads. The matrix
   --  covers WAL/replay, page traversal, application-level table/index IO,
   --  backup/restore, export/import, encryption, repeated recovery, and
   --  logical concurrent reader/single-writer scheduling while enforcing
   --  explicit operation/resource caps.
   --  @param Base_Seed base seed argument supplied to the operation.
   --  @param Budget budget argument supplied to the operation.
   --  @return Result produced by the function.
   function Run_Bounded
     (Base_Seed : Natural;
      Budget    : Stress_Budget) return Stress_Report;
end Database.Stress;
