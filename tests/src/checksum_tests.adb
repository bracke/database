with AUnit.Assertions;

with Database.Checksums;

package body Checksum_Tests is
   use AUnit.Assertions;
   use type Database.Checksums.Word_32;

   procedure Test_Adler32_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Adler32_Known_Vector
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Adler32_Update_Converges
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Page_Checksum_Uses_Page_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Verification_Rejects_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("checksum contracts and SPARK-friendly analysis");
   end Name;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Adler32_Empty'Access, "Adler32 empty stream");
      Register_Routine
        (T, Test_Adler32_Known_Vector'Access, "Adler32 known vector");
      Register_Routine
        (T,
         Test_Adler32_Update_Converges'Access,
         "Adler32 incremental convergence");
      Register_Routine
        (T,
         Test_Page_Checksum_Uses_Page_Id'Access,
         "page checksum includes page id");
      Register_Routine
        (T,
         Test_Verification_Rejects_Tamper'Access,
         "checksum verification rejects tamper");
   end Register_Tests;

   procedure Test_Adler32_Empty (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty : constant Database.Checksums.Byte_Array (1 .. 0) := (others => 0);
   begin
      Assert
        (Database.Checksums.Adler32 (Empty) = 1,
         "Adler32 of empty input must be initial state 1");
   end Test_Adler32_Empty;

   procedure Test_Adler32_Known_Vector
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ASCII "Wikipedia"; standard Adler-32 vector is 16#11E6_0398#.
      Data : constant Database.Checksums.Byte_Array (0 .. 8) :=
        (87, 105, 107, 105, 112, 101, 100, 105, 97);
   begin
      Assert
        (Database.Checksums.Adler32 (Data) = 16#11E6_0398#,
         "Adler32 known vector mismatch");
   end Test_Adler32_Known_Vector;

   procedure Test_Adler32_Update_Converges
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Full  : constant Database.Checksums.Byte_Array (0 .. 4) :=
        (1, 2, 3, 4, 5);
      Left  : constant Database.Checksums.Byte_Array (0 .. 1) := (1, 2);
      Right : constant Database.Checksums.Byte_Array (0 .. 2) := (3, 4, 5);
      State : constant Database.Checksums.Word_32 :=
        Database.Checksums.Adler32_Update
          (Database.Checksums.Adler32 (Left), Right);
   begin
      Assert
        (State = Database.Checksums.Adler32 (Full),
         "incremental checksum must equal one-shot checksum");
   end Test_Adler32_Update_Converges;

   procedure Test_Page_Checksum_Uses_Page_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Database.Checksums.Byte_Array (0 .. 3) :=
        (10, 20, 30, 40);
   begin
      Assert
        (Database.Checksums.Page_Checksum (1, Data)
         /= Database.Checksums.Page_Checksum (2, Data),
         "page checksum must bind data to page id");
   end Test_Page_Checksum_Uses_Page_Id;

   procedure Test_Verification_Rejects_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Original : constant Database.Checksums.Byte_Array (0 .. 2) := (1, 2, 3);
      Tampered : constant Database.Checksums.Byte_Array (0 .. 2) := (1, 2, 4);
      Sum      : constant Database.Checksums.Word_32 :=
        Database.Checksums.Adler32 (Original);
   begin
      Assert
        (Database.Checksums.Verify_Adler32 (Original, Sum),
         "original checksum must verify");
      Assert
        (not Database.Checksums.Verify_Adler32 (Tampered, Sum),
         "tampered data must not verify");
   end Test_Verification_Rejects_Tamper;

end Checksum_Tests;
