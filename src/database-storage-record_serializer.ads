with Interfaces;

package Database.Storage.Record_Serializer
  with SPARK_Mode => Off
is
   use type Interfaces.Unsigned_8;
   --  Byte defines a public database type used by this package.
   subtype Byte is Interfaces.Unsigned_8;
   --  Word_32 defines a public database type used by this package.
   subtype Word_32 is Interfaces.Unsigned_32;

   --  Byte_Array defines a public database type used by this package.
   type Byte_Array is array (Natural range <>) of Byte;

   --  Deterministic low-level record serialization format:
   --
   --    0 .. 3   magic: "DREC"
   --    4        format version
   --    5        field count
   --    6 .. 7   reserved, must be zero
   --    8 .. 11  payload length
   --    12 ..    field directory, 8 bytes per field:
   --              field offset, little-endian u32, relative to payload start
   --              field length, little-endian u32
   --    ...      payload bytes
   --
   --  This package validates and builds only the low-level deterministic
   --  envelope. Higher-level typed value encoding remains the responsibility
   --  of Database.Storage.Record_Format.

   Header_Length      : constant Natural := 12;
   --  Directory_Entry_Length is a public constant used by this package.
   Directory_Entry_Length : constant Natural := 8;
   --  Max_Field_Count is a public constant used by this package.
   Max_Field_Count    : constant Natural := 64;
   --  Max_Payload_Length is a public constant used by this package.
   Max_Payload_Length : constant Natural := 16#0010_0000#;

   --  Magic_0 is a public constant used by this package.
   Magic_0 : constant Byte := 16#44#;
   -- 'D'
   --  Magic_1 is a public constant used by this package.
   Magic_1 : constant Byte := 16#52#;
   -- 'R'
   --  Magic_2 is a public constant used by this package.
   Magic_2 : constant Byte := 16#45#;
   -- 'E'
   --  Magic_3 is a public constant used by this package.
   Magic_3 : constant Byte := 16#43#;
   -- 'C'

   --  Current_Format_Version is a public constant used by this package.
   Current_Format_Version : constant Byte := 1;

   --  Parse_Status defines a public database type used by this package.
   type Parse_Status is
     (Parse_OK,
      Record_Too_Short,
      Invalid_Magic,
      Unsupported_Format,
      Invalid_Reserved_Bytes,
      Invalid_Field_Count,
      Invalid_Payload_Length,
      Directory_Out_Of_Bounds,
      Field_Out_Of_Bounds,
      Field_Order_Violation,
      Output_Buffer_Too_Small);

   --  Record_Header stores the public fields for this database abstraction.
   type Record_Header is record
      Version        : Byte := 0;
      Field_Count    : Natural := 0;
      Payload_Length : Natural := 0;
      Directory_First : Natural := 0;
      Payload_First   : Natural := 0;
   end record;

   --  Field_Span stores the public fields for this database abstraction.
   type Field_Span is record
      Offset : Natural := 0;
      Length : Natural := 0;
   end record;

   --  Field_Span_Array defines a public database type used by this package.
   type Field_Span_Array is array (Natural range <>) of Field_Span;

   --  Return header is well formed for the supplied database state or arguments.
   --  @param Header header argument supplied to the operation.
   --  @return Result produced by the function.
   function Header_Is_Well_Formed (Header : Record_Header) return Boolean is
     (Header.Version = Current_Format_Version
      and then Header.Field_Count <= Max_Field_Count
      and then Header.Payload_Length <= Max_Payload_Length
      and then Header.Payload_First >= Header_Length);

   --  Return read u32 le for the supplied database state or arguments.
   --  @param Data byte data processed by the operation.
   --  @param First first argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_U32_LE
     (Data  : Byte_Array;
      First : Natural) return Word_32
     with
       Global => null,
       Pre => First <= Data'Last
         and then Data'Last - First >= 3,
       Depends => (Read_U32_LE'Result => (Data, First));

   --  Write Value as a little-endian 32-bit word into Data at First.
   --  @param Data byte data processed by the operation.
   --  @param First first argument supplied to the operation.
   --  @param Value typed value supplied to the operation.
   procedure Write_U32_LE
     (Data  : in out Byte_Array;
      First : Natural;
      Value : Word_32)
     with
       Global => null,
       Pre => First <= Data'Last
         and then Data'Last - First >= 3,
       Depends => (Data => (Data, First, Value));

   --  Return the byte length required for the record envelope.
   --  @param Field_Count field count argument supplied to the operation.
   --  @param Payload_Length payload length argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Encoded_Length
     (Field_Count    : Natural;
      Payload_Length : Natural) return Natural
     with
       Global => null,
       Pre => Field_Count <= Max_Field_Count
         and then Payload_Length <= Max_Payload_Length,
       Depends => (Encoded_Length'Result => (Field_Count, Payload_Length));

   --  Validate a deterministic serialized record envelope.
   --  @param Data byte data processed by the operation.
   --  @param Header header argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Record
     (Data   : Byte_Array;
      Header : out Record_Header) return Parse_Status
     with
       Global => null,
       Depends =>
         (Validate_Record'Result => Data,
          Header => Data),
       Post =>
         (if Validate_Record'Result = Parse_OK then Header_Is_Well_Formed (Header));

   --  Return read field span for the supplied database state or arguments.
   --  @param Data byte data processed by the operation.
   --  @param Header header argument supplied to the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Span span argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_Field_Span
     (Data   : Byte_Array;
      Header : Record_Header;
      Index  : Natural;
      Span   : out Field_Span) return Parse_Status
     with
       Global => null,
       Pre => Header_Is_Well_Formed (Header),
       Depends =>
         (Read_Field_Span'Result => (Data, Header, Index),
          Span => (Data, Header, Index));

   --  Return validate field directory for the supplied database state or arguments.
   --  @param Data byte data processed by the operation.
   --  @param Header header argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Field_Directory
     (Data   : Byte_Array;
      Header : Record_Header) return Parse_Status
     with
       Global => null,
       Pre => Header_Is_Well_Formed (Header),
       Depends => (Validate_Field_Directory'Result => (Data, Header));

   --  Build a deterministic record envelope into Output.
   --  @param Payload byte data processed by the operation.
   --  @param Fields fields argument supplied to the operation.
   --  @param Output output argument supplied to the operation.
   --  @return Result produced by the function.
   function Build_Record
     (Payload : Byte_Array;
      Fields  : Field_Span_Array;
      Output  : in out Byte_Array) return Parse_Status
     with
       Global => null,
       Pre => Fields'Length <= Max_Field_Count
         and then Payload'Length <= Max_Payload_Length,
       Depends =>
         (Build_Record'Result => (Payload, Fields, Output),
          Output => (Payload, Fields, Output));

end Database.Storage.Record_Serializer;
