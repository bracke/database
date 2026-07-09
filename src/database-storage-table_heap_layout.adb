package body Database.Storage.Table_Heap_Layout
  with SPARK_Mode => On
is
   use type Database.Byte;

   function Raw_U32_Value
     (Buffer : Byte_Array;
      Offset : Natural) return Long_Long_Integer
   is
   begin
      return
        Long_Long_Integer (Buffer (Offset)) * 16#1000000#
        + Long_Long_Integer (Buffer (Offset + 1)) * 16#10000#
        + Long_Long_Integer (Buffer (Offset + 2)) * 16#100#
        + Long_Long_Integer (Buffer (Offset + 3));
   end Raw_U32_Value;

   function Read_U32
     (Buffer : Byte_Array;
      Offset : Natural) return Natural
   is
      Raw : constant Long_Long_Integer := Raw_U32_Value (Buffer, Offset);
   begin
      return Natural (Raw);
   end Read_U32;

   procedure Put_U32
     (Buffer : in out Byte_Array;
      Offset : Natural;
      Value  : Natural)
   is
   begin
      Buffer (Offset)     := Encoded_U32_Byte (Value, 0);
      Buffer (Offset + 1) := Encoded_U32_Byte (Value, 1);
      Buffer (Offset + 2) := Encoded_U32_Byte (Value, 2);
      Buffer (Offset + 3) := Encoded_U32_Byte (Value, 3);
   end Put_U32;

   function Metadata_At
     (Buffer : Byte_Array;
      Offset : Natural) return Slot_Metadata_Image
   is
      Base      : constant Natural := Header_Size + Offset;
      Flag_Byte : constant Byte := Buffer (Base);
   begin
      return
        (Created_By_Tx   => Read_U32 (Buffer, Base + 1),
         Created_Version => Read_U32 (Buffer, Base + 5),
         Deleted_By_Tx   => Read_U32 (Buffer, Base + 9),
         Deleted_Version => Read_U32 (Buffer, Base + 13),
         Deleted         => (Flag_Byte and Byte (1)) /= Byte (0),
         Tombstone       => (Flag_Byte and Byte (2)) /= Byte (0));
   end Metadata_At;

   procedure Put_Metadata
     (Buffer   : in out Byte_Array;
      Offset   : Natural;
      Metadata : Slot_Metadata_Image)
   is
      Base : constant Natural := Header_Size + Offset;
   begin
      Buffer (Base) := Encoded_Flags (Metadata.Deleted, Metadata.Tombstone);
      Put_U32 (Buffer, Base + 1, Metadata.Created_By_Tx);
      Put_U32 (Buffer, Base + 5, Metadata.Created_Version);
      Put_U32 (Buffer, Base + 9, Metadata.Deleted_By_Tx);
      Put_U32 (Buffer, Base + 13, Metadata.Deleted_Version);
   end Put_Metadata;

   function Slot_Length
     (Buffer : Byte_Array;
      Offset : Natural) return Natural
   is
   begin
      return Read_U32 (Buffer, Header_Size + Offset + 17);
   end Slot_Length;

   procedure Put_Slot_Length
     (Buffer : in out Byte_Array;
      Offset : Natural;
      Length : Natural)
   is
   begin
      Put_U32 (Buffer, Header_Size + Offset + 17, Length);
   end Put_Slot_Length;
end Database.Storage.Table_Heap_Layout;
