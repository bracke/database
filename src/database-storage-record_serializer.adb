with Interfaces;
package body Database.Storage.Record_Serializer
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;

   function Read_U32_LE
     (Data  : Byte_Array;
      First : Natural) return Word_32
   is
      B0 : constant Word_32 := Word_32 (Data (First));
      B1 : constant Word_32 := Word_32 (Data (First + 1));
      B2 : constant Word_32 := Word_32 (Data (First + 2));
      B3 : constant Word_32 := Word_32 (Data (First + 3));
   begin
      return B0
        or (B1 * 16#0000_0100#)
        or (B2 * 16#0001_0000#)
        or (B3 * 16#0100_0000#);
   end Read_U32_LE;

   procedure Write_U32_LE
     (Data  : in out Byte_Array;
      First : Natural;
      Value : Word_32)
   is
   begin
      Data (First)     := Byte (Value and 16#0000_00FF#);
      Data (First + 1) := Byte ((Value / 16#0000_0100#) and 16#0000_00FF#);
      Data (First + 2) := Byte ((Value / 16#0001_0000#) and 16#0000_00FF#);
      Data (First + 3) := Byte ((Value / 16#0100_0000#) and 16#0000_00FF#);
   end Write_U32_LE;

   function Encoded_Length
     (Field_Count    : Natural;
      Payload_Length : Natural) return Natural
   is
   begin
      return Header_Length + Field_Count * Directory_Entry_Length + Payload_Length;
   end Encoded_Length;

   procedure Validate_Record
     (Data   : Byte_Array;
      Header : out Record_Header;
      Status : out Parse_Status)
   is
      Payload_Length_Word : Word_32;
      Directory_Length    : Natural;
   begin
      Header := (others => <>);

      if Data'First > Data'Last then
         Status := Record_Too_Short;
         return;
      end if;

      if Data'First > Natural'Last - Header_Length then
         Status := Record_Too_Short;
         return;
      end if;

      if Data'Last - Data'First < Header_Length - 1 then
         Status := Record_Too_Short;
         return;
      end if;

      if Data (Data'First) /= Magic_0
        or else Data (Data'First + 1) /= Magic_1
        or else Data (Data'First + 2) /= Magic_2
        or else Data (Data'First + 3) /= Magic_3
      then
         Status := Invalid_Magic;
         return;
      end if;

      Header.Version := Data (Data'First + 4);
      if Header.Version /= Current_Format_Version then
         Status := Unsupported_Format;
         return;
      end if;

      Header.Field_Count := Natural (Data (Data'First + 5));
      if Header.Field_Count > Max_Field_Count then
         Status := Invalid_Field_Count;
         return;
      end if;

      if Data (Data'First + 6) /= 0
        or else Data (Data'First + 7) /= 0
      then
         Status := Invalid_Reserved_Bytes;
         return;
      end if;

      Payload_Length_Word := Read_U32_LE (Data, Data'First + 8);
      if Payload_Length_Word > Word_32 (Max_Payload_Length) then
         Status := Invalid_Payload_Length;
         return;
      end if;

      Header.Payload_Length := Natural (Payload_Length_Word);
      Header.Directory_First := Data'First + Header_Length;
      Directory_Length := Header.Field_Count * Directory_Entry_Length;

      if Header.Directory_First > Natural'Last - Directory_Length then
         Status := Directory_Out_Of_Bounds;
         return;
      end if;

      Header.Payload_First := Header.Directory_First + Directory_Length;

      if Data'Last - Data'First < Header_Length + Directory_Length - 1 then
         Status := Directory_Out_Of_Bounds;
         return;
      end if;

      if Header.Payload_Length > 0
        and then Data'Last - Data'First <
          Header_Length + Directory_Length + Header.Payload_Length - 1
      then
         Status := Invalid_Payload_Length;
         return;
      end if;

      if Header.Payload_First > Natural'Last - Header.Payload_Length then
         Status := Invalid_Payload_Length;
         return;
      end if;

      Status := Validate_Field_Directory (Data, Header);
   end Validate_Record;

   procedure Read_Field_Span
     (Data   : Byte_Array;
      Header : Record_Header;
      Index  : Natural;
      Span   : out Field_Span;
      Status : out Parse_Status)
   is
      Entry_First : Natural;
      Offset_Word : Word_32;
      Length_Word : Word_32;
   begin
      Span := (others => <>);

      if Index >= Header.Field_Count then
         Status := Invalid_Field_Count;
         return;
      end if;

      if Index > Natural'Last / Directory_Entry_Length then
         Status := Directory_Out_Of_Bounds;
         return;
      end if;

      Entry_First := Header.Directory_First + Index * Directory_Entry_Length;

      if Entry_First < Data'First
        or else Entry_First > Data'Last
        or else Data'Last - Entry_First < Directory_Entry_Length - 1
      then
         Status := Directory_Out_Of_Bounds;
         return;
      end if;

      Offset_Word := Read_U32_LE (Data, Entry_First);
      Length_Word := Read_U32_LE (Data, Entry_First + 4);

      if Offset_Word > Word_32 (Max_Payload_Length)
        or else Length_Word > Word_32 (Max_Payload_Length)
      then
         Status := Field_Out_Of_Bounds;
         return;
      end if;

      Span.Offset := Natural (Offset_Word);
      Span.Length := Natural (Length_Word);

      if Span.Offset > Header.Payload_Length then
         Status := Field_Out_Of_Bounds;
         return;
      end if;

      if Span.Length > Header.Payload_Length - Span.Offset then
         Status := Field_Out_Of_Bounds;
         return;
      end if;

      Status := Parse_OK;
   end Read_Field_Span;

   function Validate_Field_Directory
     (Data   : Byte_Array;
      Header : Record_Header) return Parse_Status
   is
      Previous_End : Natural := 0;
      Span         : Field_Span;
      Status       : Parse_Status;
   begin
      if Header.Field_Count = 0 then
         return Parse_OK;
      end if;

      for Index in 0 .. Header.Field_Count - 1 loop
         pragma Loop_Invariant (Previous_End <= Header.Payload_Length);

         Read_Field_Span (Data, Header, Index, Span, Status);
         if Status /= Parse_OK then
            return Status;
         end if;

         if Index > 0 and then Span.Offset < Previous_End then
            return Field_Order_Violation;
         end if;

         Previous_End := Span.Offset + Span.Length;
      end loop;

      return Parse_OK;
   end Validate_Field_Directory;

   procedure Build_Record
     (Payload : Byte_Array;
      Fields  : Field_Span_Array;
      Output  : in out Byte_Array;
      Status  : out Parse_Status)
   is
      Payload_Target  : Natural;
      Source_Index    : Natural;
      Target_Index    : Natural;
      Entry_First     : Natural;
      Previous_End    : Natural := 0;
      Field_Count     : constant Natural :=
        (if Fields'First > Fields'Last
         then 0
         else Fields'Last - Fields'First + 1);
      Payload_Length  : constant Natural :=
        (if Payload'First > Payload'Last
         then 0
         else Payload'Last - Payload'First + 1);
   begin
      if Output'First > Natural'Last - Header_Length then
         Status := Output_Buffer_Too_Small;
         return;
      end if;

      if Field_Count > Max_Field_Count then
         Status := Invalid_Field_Count;
         return;
      end if;

      if Payload_Length > Max_Payload_Length then
         Status := Invalid_Payload_Length;
         return;
      end if;

      declare
         Required_Length : constant Natural  :=
           Encoded_Length (Field_Count, Payload_Length);
      begin
         if Output'First > Output'Last then
            Status := Output_Buffer_Too_Small;
            return;
         end if;

         if Output'First > Natural'Last - Required_Length then
            Status := Output_Buffer_Too_Small;
            return;
         end if;

         if Output'Last - Output'First < Required_Length - 1 then
            Status := Output_Buffer_Too_Small;
            return;
         end if;

         pragma Assert (Output'First <= Natural'Last - Required_Length);
         pragma Assert (Required_Length >= Header_Length);
         pragma Assert (Required_Length >= Header_Length + Field_Count * Directory_Entry_Length);
         pragma Assert (Output'Last - Output'First >= Required_Length - 1);

         for Index in Fields'Range loop
            pragma Loop_Invariant (Previous_End <= Payload_Length);

            if Fields (Index).Offset > Payload_Length then
               Status := Field_Out_Of_Bounds;
               return;
            end if;

            if Fields (Index).Length > Payload_Length - Fields (Index).Offset then
               Status := Field_Out_Of_Bounds;
               return;
            end if;

            if Index /= Fields'First
              and then Fields (Index).Offset < Previous_End
            then
               Status := Field_Order_Violation;
               return;
            end if;

            Previous_End := Fields (Index).Offset + Fields (Index).Length;
         end loop;

         pragma Assert (Output'First in Output'Range);
         pragma Assert (Output'First <= Natural'Last - (Header_Length - 1));
         pragma Assert (Output'First + Header_Length - 1 <= Output'Last);

         Output (Output'First) := Magic_0;
         Output (Output'First + 1) := Magic_1;
         Output (Output'First + 2) := Magic_2;
         Output (Output'First + 3) := Magic_3;
         Output (Output'First + 4) := Current_Format_Version;
         Output (Output'First + 5) := Byte (Field_Count);
         Output (Output'First + 6) := 0;
         Output (Output'First + 7) := 0;
         Write_U32_LE (Output, Output'First + 8, Word_32 (Payload_Length));

         for Index in Fields'Range loop
            pragma Loop_Invariant (Index in Fields'Range);
            pragma Loop_Invariant (Output'First <= Natural'Last - Required_Length);
            pragma Loop_Invariant (Output'Last - Output'First >= Required_Length - 1);
            pragma Loop_Invariant (Required_Length >= Header_Length + Field_Count * Directory_Entry_Length);

            Entry_First := Output'First + Header_Length
              + (Index - Fields'First) * Directory_Entry_Length;

            pragma Assert (Index - Fields'First < Field_Count);
            pragma Assert (Entry_First in Output'Range);
            pragma Assert (Entry_First <= Natural'Last - 7);
            pragma Assert (Entry_First + 7 <= Output'Last);

            Write_U32_LE (Output, Entry_First, Word_32 (Fields (Index).Offset));
            Write_U32_LE
              (Output, Entry_First + 4, Word_32 (Fields (Index).Length));
         end loop;

         if Payload_Length > 0 then
            pragma Assert (Required_Length = Header_Length
              + Field_Count * Directory_Entry_Length + Payload_Length);
            Payload_Target := Output'First + Header_Length
              + Field_Count * Directory_Entry_Length;

            pragma Assert (Payload_Target in Output'Range);
            pragma Assert
              (Payload_Target + Payload_Length - 1 <= Output'Last);
            pragma Assert (Payload_Target <= Natural'Last - (Payload_Length - 1));
            pragma Assert (Payload'First <= Natural'Last - (Payload_Length - 1));

            for Offset in 0 .. Payload_Length - 1 loop
               pragma Loop_Invariant (Offset <= Payload_Length - 1);
               Source_Index := Payload'First + Offset;
               Target_Index := Payload_Target + Offset;
               pragma Assert (Source_Index in Payload'Range);
               pragma Assert (Target_Index in Output'Range);
               Output (Target_Index) := Payload (Source_Index);
            end loop;
         end if;
      end;

      Status := Parse_OK;
   end Build_Record;

end Database.Storage.Record_Serializer;
