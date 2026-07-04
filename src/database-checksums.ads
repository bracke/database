with Interfaces;
use type Interfaces.Unsigned_32;

package Database.Checksums
  with SPARK_Mode => On
is
   --  Byte defines a public database type used by this package.
   subtype Byte is Interfaces.Unsigned_8;
   --  Word_32 defines a public database type used by this package.
   subtype Word_32 is Interfaces.Unsigned_32;

   --  Byte_Array defines a public database type used by this package.
   type Byte_Array is array (Natural range <>) of Byte;

   --  Adler_Modulus is a public constant used by this package.
   Adler_Modulus : constant Word_32 := 65_521;

   --  Compute an Adler-32 checksum.
   --
   --  This subprogram is intentionally small and SPARK-friendly so checksum
   --  behavior can be analyzed independently from the full storage engine.
   --  @param Data byte data processed by the operation.
   --  @return Result produced by the function.
   function Adler32 (Data : Byte_Array) return Word_32
     with
       Global => null,
       Depends => (Adler32'Result => Data);

   --  Update an existing Adler-32 state with additional data.
   --
   --  The initial Adler-32 state for an empty stream is 1.
   --  @param Initial initial argument supplied to the operation.
   --  @param Data byte data processed by the operation.
   --  @return Status result describing whether the operation succeeded.
   function Adler32_Update
     (Initial : Word_32;
      Data    : Byte_Array) return Word_32
     with
       Global => null,
       Depends => (Adler32_Update'Result => (Initial, Data));

   --  Verify that Data matches Expected.
   --  @param Data byte data processed by the operation.
   --  @param Expected expected value used for validation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Adler32
     (Data     : Byte_Array;
      Expected : Word_32) return Boolean
     with
       Global => null,
       Depends => (Verify_Adler32'Result => (Data, Expected)),
       Post => Verify_Adler32'Result = (Adler32 (Data) = Expected);

   --  Compute a deterministic 32-bit page checksum.
   --
   --  The page checksum is deliberately separate from encrypted authentication
   --  tags. It is a fast corruption-detection checksum used before deeper
   --  structural validation.
   --  @param Page_Id page id argument supplied to the operation.
   --  @param Data byte data processed by the operation.
   --  @return Computed checksum or checksum-verification result.
   function Page_Checksum
     (Page_Id : Word_32;
      Data    : Byte_Array) return Word_32
     with
       Global => null,
       Depends => (Page_Checksum'Result => (Page_Id, Data));

   --  Return True when Data matches the page-id-bound Expected checksum.
   --  @param Page_Id page id argument supplied to the operation.
   --  @param Data byte data processed by the operation.
   --  @param Expected expected value used for validation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Page_Checksum
     (Page_Id  : Word_32;
      Data     : Byte_Array;
      Expected : Word_32) return Boolean
     with
       Global => null,
       Depends => (Verify_Page_Checksum'Result => (Page_Id, Data, Expected)),
       Post => Verify_Page_Checksum'Result =
         (Page_Checksum (Page_Id, Data) = Expected);

end Database.Checksums;
