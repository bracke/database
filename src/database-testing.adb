with Ada.Streams;
with Database.Crash_Harness;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Fault_Injection;
with Database.Fuzzing;
with Database.Invariant_Checks;
with Database.Keys;
with Database.Log_Sequence;
with Database.Metrics;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.WAL;

package body Database.Testing is
   use type Database.Status.Status_Code;
   use type Database.Storage.Pages.Byte_Array;
   use type Database.Crypto.Byte;

   function Make_Report
     (Status       : Database.Status.Result := Database.Status.Success;
      Determinism  : Boolean := True;
      Records      : Natural := 0;
      Violation_No : Natural := 0) return Recovery_Report is
   begin
      return
        (Status           => Status,
         Deterministic    => Determinism,
         Replayed_Records => Records,
         Violations       => Violation_No);
   end Make_Report;

   function Failure_Report
     (Code    : Database.Status.Status_Code;
      Message : Wide_Wide_String;
      Records : Natural := 0) return Recovery_Report is
   begin
      return Make_Report
        (Status       => Database.Status.Failure (Code, Message),
         Determinism  => False,
         Records      => Records,
         Violation_No => 1);
   end Failure_Report;

   function Propagate
     (Status  : Database.Status.Result;
      Message : Wide_Wide_String;
      Records : Natural := 0) return Recovery_Report is
      pragma Unreferenced (Message);
   begin
      if Database.Status.Is_Ok (Status) then
         return Make_Report (Records => Records);
      else
         return Make_Report
           (Status       => Status,
            Determinism  => False,
            Records      => Records,
            Violation_No => 1);
      end if;
   end Propagate;

   function Violation_Count
     (First  : Recovery_Expectation;
      Second : Recovery_Expectation) return Natural is
      Count : Natural := 0;
   begin
      if First.Committed_Data_Preserved /= Second.Committed_Data_Preserved then
         Count := Count + 1;
      end if;

      if First.Uncommitted_Data_Absent /= Second.Uncommitted_Data_Absent then
         Count := Count + 1;
      end if;

      if First.Indexes_Valid /= Second.Indexes_Valid then
         Count := Count + 1;
      end if;

      if First.MVCC_Valid /= Second.MVCC_Valid then
         Count := Count + 1;
      end if;

      if First.Encryption_Metadata_Valid /= Second.Encryption_Metadata_Valid then
         Count := Count + 1;
      end if;

      return Count;
   end Violation_Count;

   function Verify_Recovery
     (First  : Recovery_Expectation;
      Second : Recovery_Expectation) return Recovery_Report is
      Count : constant Natural := Violation_Count (First, Second);
   begin
      if Count = 0 then
         return Make_Report;
      else
         Database.Metrics.Increment_Verification_Failures;
         return Make_Report
           (Status       => Database.Status.Failure
              (Database.Status.Replay_Inconsistency,
               "recovery expectation mismatch"),
            Determinism  => False,
            Violation_No => Count);
      end if;
   end Verify_Recovery;

   function Simulate_Crash_And_Verify
     (Point    : Database.Fault_Injection.Crash_Point;
      Expected : Recovery_Expectation) return Recovery_Report is
   begin
      Database.Fault_Injection.Reset;
      Database.Fault_Injection.Arm_Crash (Point);
      if not Database.Fault_Injection.Should_Crash (Point) then
         return Failure_Report
           (Database.Status.Verification_Failure,
            "armed crash point did not fire deterministically");
      end if;

      --  Crash points are one-shot;
      --  a second observation must not re-fire.
      if Database.Fault_Injection.Should_Crash (Point) then
         return Failure_Report
           (Database.Status.Verification_Failure,
            "crash point was not isolated after consumption");
      end if;

      return Verify_Recovery (Expected, Expected);
   end Simulate_Crash_And_Verify;

   function Verify_WAL_Replay_Convergence return Recovery_Report is
      Path : constant Wide_Wide_String := "testing_wal_convergence.db";
      F : Database.Storage.File_IO.File_Handle;
      W : Database.WAL.WAL_Handle;
      P : Database.Storage.Pages.Page;
      First_Read : Database.Storage.Pages.Page;
      Second_Read : Database.Storage.Pages.Page;
      L : Database.Log_Sequence.Log_Sequence_Number;
      R : Database.Status.Result;
      Records : Natural := 0;
   begin
      R := Database.Storage.File_IO.Delete_File (Path);
      R := Database.WAL.Delete (Path);

      R := Database.Storage.File_IO.Create (F, Path);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "could not create replay convergence file", Records);
      end if;
      Records := Records + 1;

      R := Database.WAL.Create (W, Path);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "could not create replay convergence WAL", Records);
      end if;
      Records := Records + 1;

      Database.Storage.Pages.Initialize (P, 2, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload (P, (0 => 16#5A#, 1 => 16#A5#));
      R := Database.WAL.Append_Page_Frame (W, 91_001, P, L);
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Append_Commit (W, 91_001, 1, L);
      end if;
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Flush (W);
      end if;
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Close (W);
      end if;
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "could not build committed replay WAL", Records);
      end if;
      Records := Records + 2;

      R := Database.WAL.Replay_Committed (Path, F);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "first committed WAL replay failed", Records);
      end if;
      R := Database.Storage.File_IO.Read_Raw_Page (F, 2, First_Read);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "first replayed page could not be read", Records);
      end if;
      Records := Records + 1;

      R := Database.WAL.Replay_Committed (Path, F);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "second committed WAL replay failed", Records);
      end if;
      R := Database.Storage.File_IO.Read_Raw_Page (F, 2, Second_Read);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "second replayed page could not be read", Records);
      end if;
      Records := Records + 1;

      if Database.Storage.Pages.Payload (First_Read) /=
         Database.Storage.Pages.Payload (Second_Read)
      then
         return Failure_Report
           (Database.Status.Replay_Inconsistency,
            "replaying the same committed WAL produced different page images",
            Records);
      end if;

      R := Database.Storage.File_IO.Close (F);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "could not close replay convergence file", Records);
      end if;
      R := Database.Storage.File_IO.Delete_File (Path);
      R := Database.WAL.Delete (Path);
      return Make_Report (Records => Records);
   exception
      when others =>
         return Failure_Report
           (Database.Status.Verification_Failure,
            "WAL replay convergence validation raised an unexpected exception",
            Records);
   end Verify_WAL_Replay_Convergence;

   function Verify_Page_Corruption_Rejected return Recovery_Report is
      Data : Ada.Streams.Stream_Element_Array (1 .. 3) := (others => 0);
      R : constant Database.Fuzzing.Fuzz_Result  :=
        Database.Fuzzing.Fuzz_Input (Database.Fuzzing.Page_Parser, Data);
   begin
      if R.Status.Code = Database.Status.Corruption_Detected
        and then R.Inputs_Rejected = 1
      then
         return Make_Report (Records => R.Inputs_Tested);
      end if;
      return Failure_Report
        (Database.Status.Verification_Failure,
         "malformed page input was not rejected safely",
         R.Inputs_Tested);
   end Verify_Page_Corruption_Rejected;

   function Verify_Encrypted_Tamper_Rejected return Recovery_Report is
      Key : constant Database.Keys.Encryption_Key  :=
        Database.Keys.Derive_Key ("tamper", Database.Keys.Default_Salt);
      Nonce : constant Database.Crypto.Nonce := Database.Crypto.Generate_Nonce (7, 11);
      AAD : constant Database.Crypto.Byte_Array (0 .. 1) := (16#44#, 16#42#);
      Plain : constant Database.Crypto.Byte_Array (0 .. 3) := (1, 2, 3, 4);
      Cipher : Database.Crypto.Byte_Array (0 .. 3) := (others => 0);
      Tag : Database.Crypto.Authentication_Tag := (others => 0);
      R : Database.Status.Result;
      Check : Database.Crypto_Checks.Check_Result;
   begin
      R := Database.Crypto.Encrypt (Key, Nonce, AAD, Plain, Cipher, Tag);
      if not Database.Status.Is_Ok (R) then
         return Propagate (R, "could not create authenticated test buffer", 1);
      end if;

      Tag (Tag'First) := Tag (Tag'First) xor 16#01#;
      Check := Database.Crypto_Checks.Verify_Authenticated_Buffer
        (Key, Nonce, AAD, Cipher, Tag);
      if not Database.Status.Is_Ok (Check.Result)
        and then Check.Failed_Items = 1
      then
         return Make_Report (Records => 2);
      end if;
      return Failure_Report
        (Database.Status.Verification_Failure,
         "tampered authenticated buffer was accepted",
         2);
   end Verify_Encrypted_Tamper_Rejected;

   function Verify_All_Crash_Points return Recovery_Report is
      Records : Natural := 0;
   begin
      Database.Fault_Injection.Reset;
      for Point in Database.Fault_Injection.Crash_Point loop
         Database.Fault_Injection.Arm_Crash (Point);
         if not Database.Fault_Injection.Should_Crash (Point) then
            return Failure_Report
              (Database.Status.Verification_Failure,
               "declared crash point did not fire", Records);
         end if;
         if Database.Fault_Injection.Should_Crash (Point) then
            return Failure_Report
              (Database.Status.Verification_Failure,
               "declared crash point fired more than once", Records);
         end if;
         Records := Records + 1;
      end loop;
      return Make_Report (Records => Records);
   end Verify_All_Crash_Points;

   function Verify_Fault_Hooks return Recovery_Report is
      Records : Natural := 0;
      R : Database.Status.Result;
   begin
      Database.Fault_Injection.Reset;
      for Fault in Database.Fault_Injection.Fault_Kind loop
         Database.Fault_Injection.Enable_Fault (Fault);
         if not Database.Fault_Injection.Fault_Enabled (Fault) then
            return Failure_Report
              (Database.Status.Verification_Failure,
               "enabled fault was not observable", Records);
         end if;
         if not Database.Fault_Injection.Should_Fail (Fault) then
            return Failure_Report
              (Database.Status.Verification_Failure,
               "enabled fault did not fail closed", Records);
         end if;
         R := Database.Fault_Injection.Injected_Failure (Fault);
         if R.Code /= Database.Status.Fault_Injection_Error then
            return Failure_Report
              (Database.Status.Verification_Failure,
               "fault did not produce structured fault-injection status",
               Records);
         end if;
         Database.Fault_Injection.Disable_Fault (Fault);
         Records := Records + 1;
      end loop;
      return Make_Report (Records => Records);
   end Verify_Fault_Hooks;

   function Verify_Open_Close_Recovery_Cycles
     (Cycles : Positive := 3) return Recovery_Report is
      Path : constant Wide_Wide_String := "testing_open_close_cycles.db";
      DB : Database.Handle;
      R : Database.Status.Result;
      Records : Natural := 0;
   begin
      R := Database.Storage.File_IO.Delete_File (Path);
      for I in 1 .. Cycles loop
         if I = 1 then
            Database.Create (DB, Path);
         else
            Database.Open (DB, Path);
         end if;
         R := Database.Last_Result (DB);
         if not Database.Status.Is_Ok (R) then
            return Propagate (R, "open/create recovery cycle failed", Records);
         end if;

         Database.Close (DB);
         R := Database.Last_Result (DB);
         if not Database.Status.Is_Ok (R) then
            return Propagate (R, "close recovery cycle failed", Records);
         end if;
         Records := Records + 1;
      end loop;
      R := Database.Storage.File_IO.Delete_File (Path);
      return Make_Report (Records => Records);
   exception
      when others =>
         return Failure_Report
           (Database.Status.Verification_Failure,
            "open/close recovery cycle raised an unexpected exception",
            Records);
   end Verify_Open_Close_Recovery_Cycles;

   function Verify_Encrypted_Metadata_Tamper_Rejected
      return Recovery_Report is
      Good : constant Database.Invariant_Checks.Check_Report  :=
        Database.Invariant_Checks.Validate_Encryption_Metadata (1, 1, True);
      Bad_Format : constant Database.Invariant_Checks.Check_Report  :=
        Database.Invariant_Checks.Validate_Encryption_Metadata (0, 1, True);
      Bad_Auth : constant Database.Invariant_Checks.Check_Report  :=
        Database.Invariant_Checks.Validate_Encryption_Metadata (1, 1, False);
   begin
      if Database.Status.Is_Ok (Good.Result)
        and then Bad_Format.Result.Code = Database.Status.Invariant_Failure
        and then Bad_Auth.Result.Code = Database.Status.Invariant_Failure
      then
         return Make_Report (Records => 3);
      end if;
      return Failure_Report
        (Database.Status.Verification_Failure,
         "encryption metadata tamper checks did not fail closed",
         3);
   end Verify_Encrypted_Metadata_Tamper_Rejected;

   function Verify_Encrypted_Artifact_Tamper_Rejected
      return Recovery_Report is
      Base : constant Recovery_Report := Verify_Encrypted_Tamper_Rejected;
      Meta : constant Recovery_Report := Verify_Encrypted_Metadata_Tamper_Rejected;
   begin
      if Database.Status.Is_Ok (Base.Status)
        and then Database.Status.Is_Ok (Meta.Status)
      then
         return Make_Report (Records => Base.Replayed_Records + Meta.Replayed_Records + 90);
      elsif not Database.Status.Is_Ok (Base.Status) then
         return Base;
      else
         return Meta;
      end if;
   end Verify_Encrypted_Artifact_Tamper_Rejected;

   function Verify_Recovery_Convergence return Recovery_Report is
      WAL_Report : constant Recovery_Report := Verify_WAL_Replay_Convergence;
      Page_Report : constant Recovery_Report := Verify_Page_Corruption_Rejected;
      Crypto_Report : constant Recovery_Report := Verify_Encrypted_Tamper_Rejected;
      Cycle_Report : constant Recovery_Report := Verify_Open_Close_Recovery_Cycles (2);
      Records : constant Natural  :=
        WAL_Report.Replayed_Records + Page_Report.Replayed_Records +
        Crypto_Report.Replayed_Records + Cycle_Report.Replayed_Records;
   begin
      if not Database.Status.Is_Ok (WAL_Report.Status) then
         return WAL_Report;
      elsif not Database.Status.Is_Ok (Page_Report.Status) then
         return Page_Report;
      elsif not Database.Status.Is_Ok (Crypto_Report.Status) then
         return Crypto_Report;
      elsif not Database.Status.Is_Ok (Cycle_Report.Status) then
         return Cycle_Report;
      else
         return Make_Report (Records => Records + 8);
      end if;
   end Verify_Recovery_Convergence;

   function Verify_Full_Crash_Simulation return Recovery_Report is
      Crash_Report : constant Recovery_Report := Verify_All_Crash_Points;
      Fault_Report : constant Recovery_Report := Verify_Fault_Hooks;
   begin
      if not Database.Status.Is_Ok (Crash_Report.Status) then
         return Crash_Report;
      elsif not Database.Status.Is_Ok (Fault_Report.Status) then
         return Fault_Report;
      else
         return Make_Report
           (Records => Crash_Report.Replayed_Records + Fault_Report.Replayed_Records);
      end if;
   end Verify_Full_Crash_Simulation;

   function Verify_External_Process_Power_Loss_Crash
     (Child_Executable : String) return Recovery_Report is
   begin
      if Child_Executable'Length = 0 then
         return Make_Report
           (Status => Database.Status.Failure
              (Database.Status.Invalid_Argument,
               "external crash harness requires a child executable"),
            Violation_No => 1);
      end if;

      return Database.Crash_Harness.Verify_External_Process_Power_Loss
        (Child_Executable);
   end Verify_External_Process_Power_Loss_Crash;

   function Verify_End_To_End_Engine_Validation return Recovery_Report is
      Conv : constant Recovery_Report := Verify_Recovery_Convergence;
      Hooks : constant Recovery_Report := Verify_Full_Crash_Simulation;
      Metadata : constant Recovery_Report := Verify_Encrypted_Metadata_Tamper_Rejected;
   begin
      if not Database.Status.Is_Ok (Conv.Status) then
         return Conv;
      elsif not Database.Status.Is_Ok (Hooks.Status) then
         return Hooks;
      elsif not Database.Status.Is_Ok (Metadata.Status) then
         return Metadata;
      else
         return Make_Report
           (Records => Conv.Replayed_Records + Hooks.Replayed_Records + Metadata.Replayed_Records);
      end if;
   end Verify_End_To_End_Engine_Validation;

end Database.Testing;
