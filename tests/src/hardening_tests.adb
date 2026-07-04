with AUnit.Assertions;
with Ada.Streams;
with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Fault_Injection;
with Database.Fuzzing;
with Database.Invariant_Checks;
with Database.Metrics;
with Database.Randomized; use Database.Randomized;
with Database.Status; use Database.Status;
with Database.Storage.Pages;
with Database.Log_Sequence;
with Database.WAL;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Table_Heap;
with Database.Stress; use Database.Stress;
with Database.Testing;
with Database.Types;
with Database.Values;
with Database.Schema;

package body Hardening_Tests is
   use AUnit.Assertions;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("hardening");
   end Name;

   procedure Deterministic_Faults (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Database.Metrics.Metrics_Snapshot;
   begin
      Database.Metrics.Reset_Metrics;
      Database.Fault_Injection.Reset;
      Database.Fault_Injection.Set_Seed (12345);
      Database.Fault_Injection.Arm_Fault_After
        (Database.Fault_Injection.Fail_WAL_Flush, 2);
      Assert
        (not Database.Fault_Injection.Should_Fail
               (Database.Fault_Injection.Fail_WAL_Flush),
         "first wal flush attempt should pass");
      Assert
        (not Database.Fault_Injection.Should_Fail
               (Database.Fault_Injection.Fail_WAL_Flush),
         "second wal flush attempt should pass");
      Assert
        (Database.Fault_Injection.Should_Fail
           (Database.Fault_Injection.Fail_WAL_Flush),
         "third wal flush attempt should fail");
      Assert
        (not Database.Fault_Injection.Fault_Enabled
               (Database.Fault_Injection.Fail_WAL_Flush),
         "one-shot fault consumed");
      S := Database.Metrics.Snapshot_Metrics;
      Assert (S.Fault_Injections = 1, "fault metric counted");
      Assert (Database.Fault_Injection.Current_Seed = 12345, "seed retained");
   end Deterministic_Faults;

   procedure Invariant_Validation (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Good : constant Database.Invariant_Checks.Integer_Array := (1, 2, 3, 4);
      Bad  : constant Database.Invariant_Checks.Integer_Array := (1, 4, 3, 5);
      P    : Database.Storage.Pages.Page;
      R    : Database.Invariant_Checks.Check_Report;
   begin
      R := Database.Invariant_Checks.Validate_Sorted_Keys (Good);
      Assert (Database.Status.Is_Ok (R.Result), "sorted keys valid");
      Assert (R.Checked_Items = 4, "all keys checked");
      R := Database.Invariant_Checks.Validate_Sorted_Keys (Bad);
      Assert
        (R.Result.Code = Database.Status.Invariant_Failure,
         "unsorted keys rejected");
      Database.Storage.Pages.Initialize
        (P, 1, Database.Storage.Pages.Table_Heap_Page);
      R := Database.Invariant_Checks.Validate_Page_Header (P);
      Assert (Database.Status.Is_Ok (R.Result), "fresh page header valid");
      R := Database.Invariant_Checks.Validate_Page_Chain ((2, 3, 4));
      Assert (Database.Status.Is_Ok (R.Result), "page chain valid");
      R := Database.Invariant_Checks.Validate_Free_List_Links ((2, 3, 4));
      Assert (Database.Status.Is_Ok (R.Result), "free-list links valid");
      R :=
        Database.Invariant_Checks.Validate_BTree_Links
          (((Parent => 10, Child => 11), (Parent => 10, Child => 12)));
      Assert
        (Database.Status.Is_Ok (R.Result), "btree parent child links valid");
      R :=
        Database.Invariant_Checks.Validate_MVCC_Chain
          (((Transaction   => 1,
             Begin_Version => 1,
             End_Version   => 2,
             Deleted       => False),
            (Transaction   => 2,
             Begin_Version => 2,
             End_Version   => 0,
             Deleted       => False)));
      Assert (Database.Status.Is_Ok (R.Result), "mvcc chain valid");
      R :=
        Database.Invariant_Checks.Validate_Index_References
          (((Index_Page => 20, Heap_Page => 30),
            (Index_Page => 21, Heap_Page => 31)));
      Assert (Database.Status.Is_Ok (R.Result), "index references valid");
      R :=
        Database.Invariant_Checks.Validate_Import_Header
          ("DATABASE_LOGICAL_EXPORT_20", 20);
      Assert (Database.Status.Is_Ok (R.Result), "import header valid");
      R := Database.Invariant_Checks.Validate_Encryption_Metadata (1, 1, True);
      Assert (Database.Status.Is_Ok (R.Result), "encryption metadata valid");
      R := Database.Invariant_Checks.Validate_Free_List_Links ((2, 2));
      Assert
        (R.Result.Code = Database.Status.Invariant_Failure,
         "duplicate free-list page rejected");

      declare
         F    : Database.Storage.File_IO.File_Handle;
         P2   : Database.Storage.Pages.Page;
         P3   : Database.Storage.Pages.Page;
         Path : constant Wide_Wide_String := "hardening_invariant_pages.db";
         SR   : Database.Status.Result;
      begin
         SR := Database.Storage.File_IO.Delete_File (Path);
         Assert
           (Database.Status.Is_Ok (SR),
            "removed stale page traversal database");
         SR := Database.Storage.File_IO.Create (F, Path);
         Assert
           (Database.Status.Is_Ok (SR), "created page traversal database");

         Database.Storage.Pages.Initialize
           (P2, 2, Database.Storage.Pages.Table_Heap_Page, 3);
         Database.Storage.Pages.Initialize
           (P3, 3, Database.Storage.Pages.Table_Heap_Page);
         SR := Database.Storage.File_IO.Write_Page (F, P2);
         Assert (Database.Status.Is_Ok (SR), "wrote linked heap page 2");
         SR := Database.Storage.File_IO.Write_Page (F, P3);
         Assert (Database.Status.Is_Ok (SR), "wrote linked heap page 3");

         R := Database.Invariant_Checks.Validate_Page_File (F);
         Assert
           (Database.Status.Is_Ok (R.Result),
            "page file traversal validates linked heap chain");
         Assert
           (R.Checked_Items >= 4,
            "page file traversal visits physical and linked pages");

         R := Database.Invariant_Checks.Validate_Free_Page_Set (F);
         Assert
           (Database.Status.Is_Ok (R.Result),
            "deep free-page traversal accepts file without free pages");

         declare
            A     : Database.Storage.Free_List.Allocator;
            First : Database.Storage.Pages.Page_Id;
            HS    : Database.Schema.Table_Schema;
         begin
            HS.Table_Id := 44;
            HS.Name :=
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("heap_deep");
            Database.Schema.Add_Column
              (HS, "id", Database.Types.Integer_Value, False, True);
            Database.Storage.Free_List.Initialize_From_File (A, F);
            SR := Database.Storage.Table_Heap.Create_Heap (F, A, First);
            Assert
              (Database.Status.Is_Ok (SR),
               "created heap for deep invariant traversal");
            R :=
              Database.Invariant_Checks.Validate_Table_Heap_Deep
                (F, First, HS);
            Assert
              (Database.Status.Is_Ok (R.Result),
               "deep heap traversal accepts empty heap chain");
         end;

         Database.Storage.Pages.Initialize
           (P3, 3, Database.Storage.Pages.Table_Heap_Page, 99);
         SR := Database.Storage.File_IO.Write_Page (F, P3);
         Assert
           (Database.Status.Is_Ok (SR), "wrote invalid next pointer page");
         R := Database.Invariant_Checks.Validate_Page_File (F);
         Assert
           (R.Result.Code = Database.Status.Invariant_Failure,
            "page file traversal rejects next pointer outside file");

         SR := Database.Storage.File_IO.Close (F);
         Assert (Database.Status.Is_Ok (SR), "closed page traversal database");
         SR := Database.Storage.File_IO.Delete_File (Path);
         Assert
           (Database.Status.Is_Ok (SR), "removed page traversal database");
      end;
   end Invariant_Validation;

   procedure Randomized_Replay (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : Database.Randomized.Generator;
      B : Database.Randomized.Generator;
   begin
      Database.Randomized.Reset (A, 777);
      Database.Randomized.Reset (B, 777);
      for I in 1 .. 25 loop
         Assert
           (Database.Randomized.Next_Natural (A, 10_000)
            = Database.Randomized.Next_Natural (B, 10_000),
            "same seed must replay same sequence");
      end loop;
      Assert
        (Database.Randomized.Seed (A) = 777,
         "seed available for reproduction");
   end Randomized_Replay;

   procedure Rich_Randomized_Generation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1 : Database.Randomized.Generator;
      G2 : Database.Randomized.Generator;
      S1 : Database.Schema.Table_Schema;
      S2 : Database.Schema.Table_Schema;
      B1 : Database.Values.Byte_Vectors.Vector;
      B2 : Database.Values.Byte_Vectors.Vector;
   begin
      Database.Randomized.Reset (G1, 909);
      Database.Randomized.Reset (G2, 909);
      S1 := Database.Randomized.Next_Schema (G1, "r", 5);
      S2 := Database.Randomized.Next_Schema (G2, "r", 5);
      Assert
        (Database.Schema.Column_Count (S1) = Database.Schema.Column_Count (S2),
         "random schema replays by seed");
      Assert
        (Database.Schema.Column_Count (S1) >= 1,
         "random schema has a primary key column");
      Assert
        (Database.Randomized.Next_Predicate_Kind (G1)
         = Database.Randomized.Next_Predicate_Kind (G2),
         "predicate kind replays");
      B1 := Database.Randomized.Next_Blob (G1, 16);
      B2 := Database.Randomized.Next_Blob (G2, 16);
      Assert
        (Natural (B1.Length) = Natural (B2.Length), "blob length replays");
      Assert
        (Database.Values.Equal
           (Database.Randomized.Next_Value_For_Kind
              (G1, Database.Types.UUID_Value),
            Database.Randomized.Next_Value_For_Kind
              (G2, Database.Types.UUID_Value)),
         "UUID values replay");
      Assert
        (Database.Values.Equal
           (Database.Randomized.Next_Value_For_Kind
              (G1, Database.Types.Date_Time_Value),
            Database.Randomized.Next_Value_For_Kind
              (G2, Database.Types.Date_Time_Value)),
         "date/time values replay");
      Assert
        (Database.Values.Equal
           (Database.Randomized.Next_Value_For_Kind
              (G1, Database.Types.Decimal_Value),
            Database.Randomized.Next_Value_For_Kind
              (G2, Database.Types.Decimal_Value)),
         "decimal values replay");
   end Rich_Randomized_Generation;

   procedure Fuzzing_Rejection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data : Ada.Streams.Stream_Element_Array (1 .. 3) := (others => 0);
      R    : Database.Fuzzing.Fuzz_Result;
      Opt  : constant Database.Fuzzing.Fuzz_Options :=
        (Max_Input_Length                    => 4_096,
         Include_Boundary_Cases              => True,
         Include_Mutations                   => True,
         Stop_On_First_Unexpected_Acceptance => False);
   begin
      R :=
        Database.Fuzzing.Fuzz_Input (Database.Fuzzing.WAL_Replay_Parser, Data);
      Assert
        (R.Status.Code = Database.Status.Corruption_Detected,
         "short wal rejected safely");
      Assert (R.Inputs_Rejected = 1, "rejection counted");
      R := Database.Fuzzing.Fuzz_Input (Database.Fuzzing.Record_Decoder, Data);
      Assert
        (R.Status.Code = Database.Status.Corruption_Detected,
         "short record rejected safely");
      R :=
        Database.Fuzzing.Fuzz_Input
          (Database.Fuzzing.Backup_Manifest_Parser, Data);
      Assert
        (R.Status.Code = Database.Status.Corruption_Detected,
         "short backup manifest rejected safely");
      R :=
        Database.Fuzzing.Fuzz_Deterministic
          (Database.Fuzzing.Encryption_Metadata_Parser, 19, 8, Opt);
      Assert (R.Inputs_Tested = 8, "deterministic fuzz count");
      Assert (R.Inputs_Rejected > 0, "malformed generated inputs rejected");
      Assert
        (R.Max_Input_Length_Observed <= Opt.Max_Input_Length,
         "deterministic fuzz obeys input cap");

      R :=
        Database.Fuzzing.Fuzz_Corpus
          (Database.Fuzzing.Page_Parser, 101, 4, Opt);
      Assert
        (R.Inputs_Tested >= 4,
         "page corpus fuzzed boundary and mutation inputs");
      Assert (R.Inputs_Rejected > 0, "page corpus rejects malformed pages");
      Assert
        (R.Minimal_Rejected_Length <= R.Max_Input_Length_Observed,
         "page corpus reports minimal rejected length");

      R :=
        Database.Fuzzing.Fuzz_Corpus
          (Database.Fuzzing.Full_Text_Structure_Parser, 102, 4, Opt);
      Assert
        (R.Inputs_Tested >= 4,
         "full-text corpus fuzzed boundary and mutation inputs");
      Assert
        (R.Inputs_Rejected > 0,
         "full-text corpus rejects malformed structures");

      R := Database.Fuzzing.Fuzz_All_Targets (211, 3, Opt);
      Assert (R.Inputs_Tested >= 7 * 3, "all fuzz targets exercised");
      Assert
        (R.Inputs_Rejected > 0,
         "all-target corpus rejects malformed durable artifacts");
      Assert
        (R.Max_Input_Length_Observed <= Opt.Max_Input_Length,
         "all-target fuzz obeys resource cap");
   end Fuzzing_Rejection;

   procedure Crash_And_Recovery_Verification
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Database.Testing.Recovery_Expectation :=
        (others => True);
      R        : Database.Testing.Recovery_Report;
   begin
      R :=
        Database.Testing.Simulate_Crash_And_Verify
          (Database.Fault_Injection.After_WAL_Commit_Marker, Expected);
      Assert (Database.Status.Is_Ok (R.Status), "crash simulation recovered");
      Assert (R.Deterministic, "recovery deterministic");
      R :=
        Database.Testing.Simulate_Crash_And_Verify
          (Database.Fault_Injection.During_Checkpoint, Expected);
      Assert
        (Database.Status.Is_Ok (R.Status), "checkpoint crash failed safely");
      R :=
        Database.Testing.Simulate_Crash_And_Verify
          (Database.Fault_Injection.During_Backup, Expected);
      Assert (Database.Status.Is_Ok (R.Status), "backup crash failed safely");
      R :=
        Database.Testing.Simulate_Crash_And_Verify
          (Database.Fault_Injection.During_Export, Expected);
      Assert (Database.Status.Is_Ok (R.Status), "export crash failed safely");
      R :=
        Database.Testing.Verify_Recovery
          (Expected,
           (Committed_Data_Preserved  => False,
            Uncommitted_Data_Absent   => True,
            Indexes_Valid             => True,
            MVCC_Valid                => True,
            Encryption_Metadata_Valid => True));
      Assert
        (R.Status.Code = Database.Status.Replay_Inconsistency,
         "divergent replay detected");
   end Crash_And_Recovery_Verification;

   procedure Stress_Report_Reproducible
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Options : constant Database.Stress.Workload_Options :=
        (Seed              => 44,
         Operations        => 40,
         Allow_Checkpoints => True,
         Allow_Backups     => True,
         Allow_Vacuum      => True,
         Allow_Rollback    => True);
      A       : constant Database.Stress.Stress_Report :=
        Database.Stress.Run_Deterministic (Options);
      B       : constant Database.Stress.Stress_Report :=
        Database.Stress.Run_Deterministic (Options);
   begin
      Assert (Database.Status.Is_Ok (A.Status), "stress status ok");
      Assert (A.Operations_Attempted = 40, "all stress operations attempted");
      Assert (A.Page_File_Checks > 0, "stress traversed real page files");
      Assert (A = B, "stress workload reproducible by seed");
   end Stress_Report_Reproducible;

   procedure Real_WAL_Fault_And_Replay
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path      : constant Wide_Wide_String := "hardening_wal_test.db";
      F         : Database.Storage.File_IO.File_Handle;
      W         : Database.WAL.WAL_Handle;
      P         : Database.Storage.Pages.Page;
      Read_Back : Database.Storage.Pages.Page;
      L         : Database.Log_Sequence.Log_Sequence_Number;
      R         : Database.Status.Result;
   begin
      R := Database.Storage.File_IO.Delete_File (Path);
      R := Database.WAL.Delete (Path);

      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "database file created");
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "WAL created");

      Database.Storage.Pages.Initialize
        (P, 4, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload (P, (0 => 16#42#));
      R := Database.WAL.Append_Page_Frame (W, 77, P, L);
      Assert (Database.Status.Is_Ok (R), "committed frame appended");
      R := Database.WAL.Append_Commit (W, 77, 1, L);
      Assert (Database.Status.Is_Ok (R), "commit marker appended");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "WAL flushed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "WAL closed");

      R := Database.WAL.Replay_Committed (Path, F);
      Assert (Database.Status.Is_Ok (R), "committed WAL replayed");
      R := Database.Storage.File_IO.Read_Raw_Page (F, 4, Read_Back);
      Assert (Database.Status.Is_Ok (R), "replayed page can be read");
      Assert
        (Database.Storage.Pages.Payload (Read_Back) (0) = 16#42#,
         "replayed payload preserved");

      R := Database.WAL.Open (W, Path);
      Assert (Database.Status.Is_Ok (R), "WAL reopened");
      Database.Fault_Injection.Reset;
      Database.Fault_Injection.Enable_Fault
        (Database.Fault_Injection.Corrupt_WAL_Frame);
      R := Database.WAL.Append_Checkpoint (W, L);
      Assert
        (R.Code = Database.Status.Fault_Injection_Error,
         "corrupt WAL frame injected");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "corrupt WAL closed");
      R := Database.WAL.Validate (Path);
      Assert (R.Code = Database.Status.WAL_Corruption, "corrupt WAL rejected");

      R := Database.Storage.File_IO.Close (F);
      R := Database.Storage.File_IO.Delete_File (Path);
      R := Database.WAL.Delete (Path);
   end Real_WAL_Fault_And_Replay;

   procedure Concrete_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Testing.Recovery_Report;
   begin
      R := Database.Testing.Verify_WAL_Replay_Convergence;
      Assert
        (Database.Status.Is_Ok (R.Status), "WAL replay convergence verified");
      Assert (R.Deterministic, "WAL convergence deterministic");

      R := Database.Testing.Verify_Page_Corruption_Rejected;
      Assert
        (Database.Status.Is_Ok (R.Status), "page corruption rejected safely");

      R := Database.Testing.Verify_Encrypted_Tamper_Rejected;
      Assert
        (Database.Status.Is_Ok (R.Status), "encrypted tamper rejected safely");
   end Concrete_Validation;

   procedure Exhaustive_Hooks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Testing.Recovery_Report;
   begin
      R := Database.Testing.Verify_All_Crash_Points;
      Assert
        (Database.Status.Is_Ok (R.Status),
         "all crash points have concrete safe paths");
      Assert
        (R.Deterministic, "all crash point verification is deterministic");

      R := Database.Testing.Verify_Full_Crash_Simulation;
      Assert
        (Database.Status.Is_Ok (R.Status),
         "full crash matrix preserves oracle state");
      Assert
        (R.Replayed_Records > 10,
         "full crash matrix traversed durable oracle state");

      R := Database.Testing.Verify_Fault_Hooks;
      Assert (Database.Status.Is_Ok (R.Status), "fault hooks fail closed");
      Assert
        (R.Replayed_Records >= 5, "multiple concrete fault hooks exercised");
   end Exhaustive_Hooks;

   procedure Repeated_Recovery_And_Encrypted_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Testing.Recovery_Report;
   begin
      R := Database.Testing.Verify_Open_Close_Recovery_Cycles (3);
      Assert
        (Database.Status.Is_Ok (R.Status),
         "repeated open/close backup/restore recovery converges");
      Assert
        (R.Replayed_Records > 0, "recovery cycles traversed durable pages");

      R := Database.Testing.Verify_Encrypted_Metadata_Tamper_Rejected;
      Assert
        (Database.Status.Is_Ok (R.Status),
         "encrypted database metadata tamper rejected");
      Assert
        (R.Replayed_Records >= 3, "encrypted metadata checks were executed");
   end Repeated_Recovery_And_Encrypted_Metadata;

   procedure Engine_Level_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Testing.Recovery_Report;
   begin
      R := Database.Testing.Verify_End_To_End_Engine_Validation;
      Assert
        (Database.Status.Is_Ok (R.Status),
         "end-to-end engine validation passed");
      Assert
        (R.Replayed_Records > 0,
         "engine validation traversed real invariants");

      R := Database.Testing.Verify_Encrypted_Artifact_Tamper_Rejected;
      Assert
        (Database.Status.Is_Ok (R.Status),
         "encrypted artifacts reject tampering");
      Assert
        (R.Replayed_Records >= 90,
         "exhaustive encrypted artifact tamper matrix exercised");
   end Engine_Level_Validation;

   procedure Recovery_Convergence_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Testing.Recovery_Report;
   begin
      R := Database.Testing.Verify_Recovery_Convergence;
      Assert (Database.Status.Is_Ok (R.Status), "recovery convergence passed");
      Assert (R.Deterministic, "recovery convergence deterministic");
      Assert
        (R.Replayed_Records > 10,
         "WAL, checkpoint, backup/restore, import/export, and encrypted metadata convergence paths executed");
   end Recovery_Convergence_Validation;

   procedure Bounded_Stress_Coverage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Budget : constant Database.Stress.Stress_Budget :=
        (Max_Seeds                 => 2,
         Max_Operations_Per_Seed   => 32,
         Max_Page_File_Checks      => 32,
         Max_Backup_Restore_Cycles => 8,
         Max_Export_Import_Cycles  => 8,
         Max_Recovery_Cycles       => 4,
         Max_Concurrent_Readers    => 3,
         Max_Writers               => 1);
      A      : constant Database.Stress.Stress_Report :=
        Database.Stress.Run_Bounded (91, Budget);
      B      : constant Database.Stress.Stress_Report :=
        Database.Stress.Run_Bounded (91, Budget);
   begin
      Assert (Database.Status.Is_Ok (A.Status), "bounded stress status ok");
      Assert (A = B, "bounded stress reproducible by base seed and budget");
      Assert
        (A.Seeds_Executed = Budget.Max_Seeds,
         "bounded stress executed seed matrix");
      Assert
        (A.Operations_Attempted
         <= Budget.Max_Seeds * Budget.Max_Operations_Per_Seed,
         "bounded stress obeyed operation cap");
      Assert
        (A.Budget_Violations = 0, "bounded stress had no budget violations");
      Assert
        (A.Reader_Cycles = Budget.Max_Seeds * Budget.Max_Concurrent_Readers,
         "bounded stress covered reader schedule");
      Assert
        (A.Writer_Cycles = Budget.Max_Seeds * Budget.Max_Writers,
         "bounded stress covered writer schedule");
      Assert
        (A.Recovery_Cycles > 0
         and then A.Recovery_Cycles <= Budget.Max_Recovery_Cycles,
         "bounded stress covered capped recovery cycles");
      Assert (A.Table_Workloads > 0, "bounded stress covered table workloads");
      Assert (A.Index_Workloads > 0, "bounded stress covered index workloads");
      Assert (A.Backups > 0, "bounded stress covered backup pressure");
      Assert
        (A.Restores > 0, "bounded stress covered restore/replay pressure");
      Assert
        (A.Export_Import_Cycles > 0,
         "bounded stress covered export/import pressure");
      Assert
        (A.Encryption_Workloads > 0,
         "bounded stress covered encryption pressure");
   end Bounded_Stress_Coverage;

   procedure External_Process_Crash_Harness_Requires_Child
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Database.Testing.Recovery_Report;
   begin
      R := Database.Testing.Verify_External_Process_Power_Loss_Crash ("");
      Assert
        (R.Status.Code = Database.Status.Invalid_Argument,
         "external crash harness must require an explicit child executable");
   end External_Process_Crash_Harness_Requires_Child;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Deterministic_Faults'Access, "deterministic fault injection");
      Register_Routine
        (T, Invariant_Validation'Access, "invariant validation");
      Register_Routine (T, Randomized_Replay'Access, "randomized seed replay");
      Register_Routine
        (T, Rich_Randomized_Generation'Access, "rich randomized generators");
      Register_Routine (T, Fuzzing_Rejection'Access, "fuzzing rejection");
      Register_Routine
        (T,
         Crash_And_Recovery_Verification'Access,
         "crash recovery verification");
      Register_Routine
        (T, Stress_Report_Reproducible'Access, "stress reproducibility");
      Register_Routine
        (T, Bounded_Stress_Coverage'Access, "bounded stress coverage");
      Register_Routine
        (T, Real_WAL_Fault_And_Replay'Access, "real WAL fault and replay");
      Register_Routine
        (T,
         Concrete_Validation'Access,
         "concrete validation paths");
      Register_Routine
        (T,
         Exhaustive_Hooks'Access,
         "exhaustive crash and fault hooks");
      Register_Routine
        (T,
         Repeated_Recovery_And_Encrypted_Metadata'Access,
         "repeated recovery and encrypted metadata validation");
      Register_Routine
        (T,
         Engine_Level_Validation'Access,
         "engine-level validation and encrypted artifact tamper");
      Register_Routine
        (T,
         Recovery_Convergence_Validation'Access,
         "full recovery convergence validation");
      Register_Routine
        (T,
         External_Process_Crash_Harness_Requires_Child'Access,
         "external process crash harness requires child executable");
   end Register_Tests;
end Hardening_Tests;
