with Database;

package Database.Storage.Table_Heap_Layout
  with SPARK_Mode => On
is
   use type Database.Byte;

   subtype Byte is Database.Byte;
   subtype Byte_Array is Database.Byte_Array;

   Header_Size      : constant Natural := 40;
   Payload_Capacity : constant Natural := 4096 - Header_Size;
   Slot_Header      : constant Natural := 21;
   Max_U32          : constant Long_Long_Integer := 16#FFFF_FFFF#;

   type Slot_Metadata_Image is record
      Created_By_Tx   : Natural := 0;
      Created_Version : Natural := 0;
      Deleted_By_Tx   : Natural := 0;
      Deleted_Version : Natural := 0;
      Deleted          : Boolean := False;
      Tombstone        : Boolean := False;
   end record;

   function U32_Offset_In_Bounds
     (Buffer : Byte_Array;
      Offset : Natural) return Boolean is
     (Offset in Buffer'Range
      and then Offset <= Natural'Last - 3
      and then Offset + 3 in Buffer'Range);

   function Raw_U32_Value
     (Buffer : Byte_Array;
      Offset : Natural) return Long_Long_Integer
     with
       Global => null,
       Pre => U32_Offset_In_Bounds (Buffer, Offset),
       Post => Raw_U32_Value'Result in 0 .. Max_U32;

   function Raw_U32_Fits_Natural
     (Buffer : Byte_Array;
      Offset : Natural) return Boolean is
     (Raw_U32_Value (Buffer, Offset) <= Long_Long_Integer (Natural'Last))
     with
       Global => null,
       Pre => U32_Offset_In_Bounds (Buffer, Offset);

   function Encoded_U32_Byte
     (Value : Natural;
      Index : Natural) return Byte is
     (case Index is
        when 0 => Byte ((Value / 16#1000000#) mod 256),
        when 1 => Byte ((Value / 16#10000#) mod 256),
        when 2 => Byte ((Value / 16#100#) mod 256),
        when others => Byte (Value mod 256))
     with
       Global => null,
       Pre => Index <= 3;

   function Encoded_Flags
     (Deleted   : Boolean;
      Tombstone : Boolean) return Byte is
     ((if Deleted then Byte (1) else Byte (0))
      or (if Tombstone then Byte (2) else Byte (0)))
     with Global => null;

   function Slot_Header_In_Bounds
     (Buffer : Byte_Array;
      Offset : Natural) return Boolean is
     (Offset <= Payload_Capacity
      and then Header_Size <= Natural'Last - Offset
      and then Header_Size + Offset <= Natural'Last - (Slot_Header - 1)
      and then Header_Size + Offset in Buffer'Range
      and then Header_Size + Offset + (Slot_Header - 1) in Buffer'Range);

   function Slot_Payload_In_Bounds
     (Used   : Natural;
      Offset : Natural;
      Length : Natural) return Boolean is
     (Used <= Payload_Capacity
      and then Offset <= Used
      and then Length <= Payload_Capacity
      and then Offset <= Natural'Last - Slot_Header
      and then Offset + Slot_Header <= Used
      and then Offset + Slot_Header <= Natural'Last - Length
      and then Offset + Slot_Header + Length <= Used);

   function Valid_Flags (Raw : Byte) return Boolean is
     (Raw <= 3);

   function Read_U32
     (Buffer : Byte_Array;
      Offset : Natural) return Natural
     with
       Global => null,
       Pre =>
         U32_Offset_In_Bounds (Buffer, Offset)
         and then Raw_U32_Fits_Natural (Buffer, Offset),
       Post => Long_Long_Integer (Read_U32'Result) = Raw_U32_Value (Buffer, Offset);

   procedure Put_U32
     (Buffer : in out Byte_Array;
      Offset : Natural;
      Value  : Natural)
     with
       Global => null,
       Pre =>
         U32_Offset_In_Bounds (Buffer, Offset),
       Post =>
         Buffer (Offset) = Encoded_U32_Byte (Value, 0)
         and then Buffer (Offset + 1) = Encoded_U32_Byte (Value, 1)
         and then Buffer (Offset + 2) = Encoded_U32_Byte (Value, 2)
         and then Buffer (Offset + 3) = Encoded_U32_Byte (Value, 3)
         and then
           (for all I in Buffer'Range =>
              (if I < Offset or else I > Offset + 3 then Buffer (I) = Buffer'Old (I)));

   function Metadata_At
     (Buffer : Byte_Array;
      Offset : Natural) return Slot_Metadata_Image
     with
       Global => null,
       Pre =>
         Slot_Header_In_Bounds (Buffer, Offset)
         and then Raw_U32_Fits_Natural (Buffer, Header_Size + Offset + 1)
         and then Raw_U32_Fits_Natural (Buffer, Header_Size + Offset + 5)
         and then Raw_U32_Fits_Natural (Buffer, Header_Size + Offset + 9)
         and then Raw_U32_Fits_Natural (Buffer, Header_Size + Offset + 13),
       Post =>
         Metadata_At'Result.Created_By_Tx = Read_U32 (Buffer, Header_Size + Offset + 1)
         and then Metadata_At'Result.Created_Version = Read_U32 (Buffer, Header_Size + Offset + 5)
         and then Metadata_At'Result.Deleted_By_Tx = Read_U32 (Buffer, Header_Size + Offset + 9)
         and then Metadata_At'Result.Deleted_Version = Read_U32 (Buffer, Header_Size + Offset + 13)
         and then Metadata_At'Result.Deleted =
           ((Buffer (Header_Size + Offset) and Byte (1)) /= Byte (0))
         and then Metadata_At'Result.Tombstone =
           ((Buffer (Header_Size + Offset) and Byte (2)) /= Byte (0));

   procedure Put_Metadata
     (Buffer   : in out Byte_Array;
      Offset   : Natural;
      Metadata : Slot_Metadata_Image)
     with
       Global => null,
       Pre => Slot_Header_In_Bounds (Buffer, Offset),
       Post => Buffer (Header_Size + Offset) =
         Encoded_Flags (Metadata.Deleted, Metadata.Tombstone);

   function Slot_Length
     (Buffer : Byte_Array;
      Offset : Natural) return Natural
     with
       Global => null,
       Pre =>
         Slot_Header_In_Bounds (Buffer, Offset)
         and then Raw_U32_Fits_Natural (Buffer, Header_Size + Offset + 17),
       Post => Long_Long_Integer (Slot_Length'Result) = Raw_U32_Value (Buffer, Header_Size + Offset + 17);

   procedure Put_Slot_Length
     (Buffer : in out Byte_Array;
      Offset : Natural;
      Length : Natural)
     with
       Global => null,
       Pre =>
         Slot_Header_In_Bounds (Buffer, Offset)
         and then Length <= Payload_Capacity,
       Post =>
         Buffer (Header_Size + Offset + 17) = Encoded_U32_Byte (Length, 0)
         and then Buffer (Header_Size + Offset + 18) = Encoded_U32_Byte (Length, 1)
         and then Buffer (Header_Size + Offset + 19) = Encoded_U32_Byte (Length, 2)
         and then Buffer (Header_Size + Offset + 20) = Encoded_U32_Byte (Length, 3);
end Database.Storage.Table_Heap_Layout;
