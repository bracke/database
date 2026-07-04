with Interfaces;

package body Database.Checksums
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_32;

   function Low_16 (Value : Word_32) return Word_32 is
     (Value and 16#0000_FFFF#)
     with
       Global => null,
       Depends => (Low_16'Result => Value);

   function High_16 (Value : Word_32) return Word_32 is
     ((Value / 16#0001_0000#) and 16#0000_FFFF#)
     with
       Global => null,
       Depends => (High_16'Result => Value);

   function Combine (A, B : Word_32) return Word_32 is
     ((B * 16#0001_0000#) or A)
     with
       Global => null,
       Depends => (Combine'Result => (A, B)),
       Pre => A < 16#0001_0000# and then B < 16#0001_0000#;

   function Adler32 (Data : Byte_Array) return Word_32 is
   begin
      return Adler32_Update (1, Data);
   end Adler32;

   function Adler32_Update
     (Initial : Word_32;
      Data    : Byte_Array) return Word_32
   is
      A : Word_32 := Low_16 (Initial);
      B : Word_32 := High_16 (Initial);
   begin
      for Index in Data'Range loop
         pragma Loop_Invariant (A < Adler_Modulus);
         pragma Loop_Invariant (B < Adler_Modulus);

         A := (A + Word_32 (Data (Index))) mod Adler_Modulus;
         B := (B + A) mod Adler_Modulus;
      end loop;

      return Combine (A, B);
   end Adler32_Update;

   function Verify_Adler32
     (Data     : Byte_Array;
      Expected : Word_32) return Boolean
   is
   begin
      return Adler32 (Data) = Expected;
   end Verify_Adler32;

   function Page_Checksum
     (Page_Id : Word_32;
      Data    : Byte_Array) return Word_32
   is
      Prefix : constant Byte_Array (0 .. 3)  :=
        (0 => Byte (Page_Id and 16#0000_00FF#),
         1 => Byte ((Page_Id / 16#0000_0100#) and 16#0000_00FF#),
         2 => Byte ((Page_Id / 16#0001_0000#) and 16#0000_00FF#),
         3 => Byte ((Page_Id / 16#0100_0000#) and 16#0000_00FF#));
   begin
      return Adler32_Update (Adler32 (Prefix), Data);
   end Page_Checksum;

   function Verify_Page_Checksum
     (Page_Id  : Word_32;
      Data     : Byte_Array;
      Expected : Word_32) return Boolean
   is
   begin
      return Page_Checksum (Page_Id, Data) = Expected;
   end Verify_Page_Checksum;

end Database.Checksums;
