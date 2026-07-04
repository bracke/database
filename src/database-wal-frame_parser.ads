with Interfaces;
with Database.Checksums;

package Database.WAL.Frame_Parser
  with SPARK_Mode => Off
is
   use type Interfaces.Unsigned_8;
   --  Byte defines a public database type used by this package.
   subtype Byte is Interfaces.Unsigned_8;
   --  Word_32 defines a public database type used by this package.
   subtype Word_32 is Interfaces.Unsigned_32;
   --  LSN defines a public database type used by this package.
   subtype LSN is Word_32;
   --  Page_Id_Type defines a public database type used by this package.
   subtype Page_Id_Type is Word_32;

   --  Byte_Array defines a public database type used by this package.
   type Byte_Array is array (Natural range <>) of Byte;

   --  WAL frame binary layout, little-endian:
   --
   --    0 .. 3   magic: "DWAL"
   --    4        format version
   --    5        frame kind
   --    6 .. 7   reserved, must be zero
   --    8 .. 11  LSN
   --    12 .. 15 previous LSN
   --    16 .. 19 page id
   --    20 .. 23 payload length
   --    24 .. 27 payload checksum
   --    28 .. 31 header checksum
   --    32 ..    payload
   --
   --  Header checksum is Page_Checksum (LSN, bytes 0 .. 27).
   --  Payload checksum is Page_Checksum (Page_Id, payload).

   Header_Length : constant Natural := 32;
   --  Max_Payload_Length is a public constant used by this package.
   Max_Payload_Length : constant Natural := 16#0010_0000#;

   --  Magic_0 is a public constant used by this package.
   Magic_0 : constant Byte := 16#44#;
   -- 'D'
   --  Magic_1 is a public constant used by this package.
   Magic_1 : constant Byte := 16#57#;
   -- 'W'
   --  Magic_2 is a public constant used by this package.
   Magic_2 : constant Byte := 16#41#;
   -- 'A'
   --  Magic_3 is a public constant used by this package.
   Magic_3 : constant Byte := 16#4C#;
   -- 'L'

   --  Current_Format_Version is a public constant used by this package.
   Current_Format_Version : constant Byte := 1;

   --  Frame_Kind defines a public database type used by this package.
   type Frame_Kind is
     (Page_Image,
      Commit_Marker,
      Checkpoint_Marker,
      Unknown_Frame);

   --  Parse_Status defines a public database type used by this package.
   type Parse_Status is
     (Parse_OK,
      Frame_Too_Short,
      Invalid_Magic,
      Unsupported_Format,
      Invalid_Reserved_Bytes,
      Invalid_Frame_Kind,
      Invalid_Payload_Length,
      Header_Checksum_Mismatch,
      Payload_Checksum_Mismatch,
      LSN_Order_Violation);

   --  Frame_Header stores the public fields for this database abstraction.
   type Frame_Header is record
      Kind             : Frame_Kind := Unknown_Frame;
      Version          : Byte := 0;
      Sequence         : LSN := 0;
      Previous_Sequence: LSN := 0;
      Page_Id          : Page_Id_Type := 0;
      Payload_Length   : Natural := 0;
      Payload_Checksum : Word_32 := 0;
      Header_Checksum  : Word_32 := 0;
   end record;

   --  Return is known kind for the supplied database state or arguments.
   --  @param Kind kind selector controlling the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Known_Kind (Kind : Frame_Kind) return Boolean is
     (Kind /= Unknown_Frame);

   --  Return header is well formed for the supplied database state or arguments.
   --  @param Header header argument supplied to the operation.
   --  @return Result produced by the function.
   function Header_Is_Well_Formed (Header : Frame_Header) return Boolean is
     (Is_Known_Kind (Header.Kind)
      and then Header.Version = Current_Format_Version
      and then Header.Payload_Length <= Max_Payload_Length);

   --  Read a little-endian 32-bit word from Data at First.
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

   --  Decode the serialized WAL frame-kind byte.
   --  @param Raw raw argument supplied to the operation.
   --  @return Result produced by the function.
   function Decode_Kind (Raw : Byte) return Frame_Kind
     with
       Global => null,
       Depends => (Decode_Kind'Result => Raw);

   --  Validate the WAL frame header without applying replay side effects.
   --  @param Data byte data processed by the operation.
   --  @param Expected_Previous expected previous argument supplied to the operation.
   --  @param Header header argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Header_Only
     (Data              : Byte_Array;
      Expected_Previous : LSN;
      Header            : out Frame_Header) return Parse_Status
     with
       Global => null,
       Depends =>
         (Validate_Header_Only'Result => (Data, Expected_Previous),
          Header => Data);

   --  Validate a complete WAL frame, including payload checksum.
   --  @param Data byte data processed by the operation.
   --  @param Expected_Previous expected previous argument supplied to the operation.
   --  @param Header header argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Frame
     (Data              : Byte_Array;
      Expected_Previous : LSN;
      Header            : out Frame_Header) return Parse_Status
     with
       Global => null,
       Depends =>
         (Validate_Frame'Result => (Data, Expected_Previous),
          Header => Data),
       Post =>
         (if Validate_Frame'Result = Parse_OK then Header_Is_Well_Formed (Header));

   --  Compute the checksum expected for the WAL frame header prefix.
   --  @param Data byte data processed by the operation.
   --  @param Seq seq argument supplied to the operation.
   --  @return Computed checksum or checksum-verification result.
   function Build_Header_Checksum
     (Data : Byte_Array;
      Seq  : LSN) return Word_32
     with
       Global => null,
       Pre => Data'Length >= 28,
       Depends => (Build_Header_Checksum'Result => (Data, Seq));

   --  Compute the checksum expected for a WAL frame payload.
   --  @param Page_Id page id argument supplied to the operation.
   --  @param Payload byte data processed by the operation.
   --  @return Computed checksum or checksum-verification result.
   function Payload_Checksum
     (Page_Id : Page_Id_Type;
      Payload : Byte_Array) return Word_32
     with
       Global => null,
       Depends => (Payload_Checksum'Result => (Page_Id, Payload));

end Database.WAL.Frame_Parser;
