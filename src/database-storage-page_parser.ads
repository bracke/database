with Interfaces;
with Database.Checksums;

package Database.Storage.Page_Parser
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   --  Byte defines a public database type used by this package.
   subtype Byte is Interfaces.Unsigned_8;
   --  Word_32 defines a public database type used by this package.
   subtype Word_32 is Interfaces.Unsigned_32;
   --  Page_Id_Type defines a public database type used by this package.
   subtype Page_Id_Type is Word_32;

   --  Byte_Array defines a public database type used by this package.
   type Byte_Array is array (Natural range <>) of Byte;

   --  Durable page binary layout, little-endian:
   --
   --    0 .. 3   magic: "DPAG"
   --    4        format version
   --    5        page kind
   --    6 .. 7   reserved, must be zero
   --    8 .. 11  page id
   --    12 .. 15 previous page id, or 0
   --    16 .. 19 next page id, or 0
   --    20 .. 23 used payload bytes
   --    24 .. 27 page LSN
   --    28 .. 31 payload checksum
   --    32 .. 35 header checksum
   --    36 ..    payload
   --
   --  Header checksum is Page_Checksum (Page_Id, bytes 0 .. 31).
   --  Payload checksum is Page_Checksum (Page_Id, payload 0 .. Used_Length - 1).
   --
   --  This package validates only page syntax and checksums. Higher-level
   --  packages validate table/index/MVCC semantics.

   Header_Length       : constant Natural := 36;
   --  Max_Payload_Length is a public constant used by this package.
   Max_Payload_Length  : constant Natural := 16#0010_0000#;

   --  Magic_0 is a public constant used by this package.
   Magic_0 : constant Byte := 16#44#;
   -- 'D'
   --  Magic_1 is a public constant used by this package.
   Magic_1 : constant Byte := 16#50#;
   -- 'P'
   --  Magic_2 is a public constant used by this package.
   Magic_2 : constant Byte := 16#41#;
   -- 'A'
   --  Magic_3 is a public constant used by this package.
   Magic_3 : constant Byte := 16#47#;
   -- 'G'

   --  Current_Format_Version is a public constant used by this package.
   Current_Format_Version : constant Byte := 1;

   --  Page_Kind defines a public database type used by this package.
   type Page_Kind is
     (Meta_Page,
      Catalog_Page,
      Heap_Page,
      BTree_Internal_Page,
      BTree_Leaf_Page,
      Free_List_Page,
      Overflow_Page,
      Unknown_Page);

   --  Parse_Status defines a public database type used by this package.
   type Parse_Status is
     (Parse_OK,
      Page_Too_Short,
      Invalid_Magic,
      Unsupported_Format,
      Invalid_Reserved_Bytes,
      Invalid_Page_Kind,
      Invalid_Page_Id,
      Invalid_Linkage,
      Invalid_Used_Length,
      Header_Checksum_Mismatch,
      Payload_Checksum_Mismatch,
      Page_LSN_Order_Violation);

   --  Page_Header stores the public fields for this database abstraction.
   type Page_Header is record
      Kind             : Page_Kind := Unknown_Page;
      Version          : Byte := 0;
      Page_Id          : Page_Id_Type := 0;
      Previous_Page_Id : Page_Id_Type := 0;
      Next_Page_Id     : Page_Id_Type := 0;
      Used_Length      : Natural := 0;
      Page_LSN         : Word_32 := 0;
      Payload_Checksum : Word_32 := 0;
      Header_Checksum  : Word_32 := 0;
   end record;

   --  Return is known kind for the supplied database state or arguments.
   --  @param Kind kind selector controlling the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Known_Kind (Kind : Page_Kind) return Boolean is
     (Kind /= Unknown_Page);

   --  Return header is well formed for the supplied database state or arguments.
   --  @param Header header argument supplied to the operation.
   --  @return Result produced by the function.
   function Header_Is_Well_Formed (Header : Page_Header) return Boolean is
     (Is_Known_Kind (Header.Kind)
      and then Header.Version = Current_Format_Version
      and then Header.Page_Id /= 0
      and then Header.Used_Length <= Max_Payload_Length);

   --  Return read u32 le for the supplied database state or arguments.
   --  @param Data byte data processed by the operation.
   --  @param First first argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_U32_LE
     (Data  : Byte_Array;
      First : Natural) return Word_32
     with
       Global => null,
       Pre => First in Data'Range
         and then First <= Natural'Last - 3
         and then Data'Last - First >= 3,
       Depends => (Read_U32_LE'Result => (Data, First));

   --  Return decode kind for the supplied database state or arguments.
   --  @param Raw raw argument supplied to the operation.
   --  @return Result produced by the function.
   function Decode_Kind (Raw : Byte) return Page_Kind
     with
       Global => null,
       Depends => (Decode_Kind'Result => Raw);

   --  Validate the durable page header without interpreting higher-level contents.
   --  @param Data byte data processed by the operation.
   --  @param Minimum_LSN minimum lsn argument supplied to the operation.
   --  @param Header header argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   procedure Validate_Header_Only
     (Data         : Byte_Array;
      Minimum_LSN  : Word_32;
      Header       : out Page_Header;
      Status       : out Parse_Status)
     with
       Global => null,
       Depends =>
         (Status => (Data, Minimum_LSN),
          Header => (Data, Minimum_LSN)),
       Post =>
         (if Status = Parse_OK then
            Header_Is_Well_Formed (Header)
            and then Data'First <= Natural'Last - Header_Length
            and then
              Data'First <= Natural'Last - Header_Length - Header.Used_Length
            and then Data'First <= Data'Last
            and then
              Data'Last - Data'First >= Header_Length + Header.Used_Length - 1);

   --  Validate a complete durable page, including header and payload checksums.
   --  @param Data byte data processed by the operation.
   --  @param Minimum_LSN minimum lsn argument supplied to the operation.
   --  @param Header header argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   procedure Validate_Page
     (Data         : Byte_Array;
      Minimum_LSN  : Word_32;
      Header       : out Page_Header;
      Status       : out Parse_Status)
     with
       Global => null,
       Depends =>
         (Status => (Data, Minimum_LSN),
          Header => (Data, Minimum_LSN)),
       Post =>
         (if Status = Parse_OK then Header_Is_Well_Formed (Header));

   --  Return build header checksum for the supplied database state or arguments.
   --  @param Data byte data processed by the operation.
   --  @param Page_Id page id argument supplied to the operation.
   --  @return Computed checksum or checksum-verification result.
   function Build_Header_Checksum
     (Data    : Byte_Array;
      Page_Id : Page_Id_Type) return Word_32
     with
       Global => null,
       Pre => Data'Length >= 32
         and then Data'First <= Natural'Last - 31,
       Depends => (Build_Header_Checksum'Result => (Data, Page_Id));

   --  Compute the checksum expected for a durable page payload.
   --  @param Page_Id page id argument supplied to the operation.
   --  @param Payload byte data processed by the operation.
   --  @return Computed checksum or checksum-verification result.
   function Payload_Checksum
     (Page_Id : Page_Id_Type;
      Payload : Byte_Array) return Word_32
     with
       Global => null,
       Depends => (Payload_Checksum'Result => (Page_Id, Payload));

end Database.Storage.Page_Parser;
