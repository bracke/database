with Interfaces;
package body Database.Storage.Record_Serializer is
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

   function Validate_Record
     (Data   : Byte_Array;
      Header : out Record_Header) return Parse_Status
   is
      Payload_Length_Word : Word_32;
      Directory_Length    : Natural;
   begin
      Header := (others => <>);

      if Data'Length < Header_Length then
         return Record_Too_Short;
      end if;

      if Data (Data'First) /= Magic_0
        or else Data (Data'First + 1) /= Magic_1
        or else Data (Data'First + 2) /= Magic_2
        or else Data (Data'First + 3) /= Magic_3
      then
         return Invalid_Magic;
      end if;

      Header.Version := Data (Data'First + 4);
      if Header.Version /= Current_Format_Version then
         return Unsupported_Format;
      end if;

      Header.Field_Count := Natural (Data (Data'First + 5));
      if Header.Field_Count > Max_Field_Count then
         return Invalid_Field_Count;
      end if;

      if Data (Data'First + 6) /= 0
        or else Data (Data'First + 7) /= 0
      then
         return Invalid_Reserved_Bytes;
      end if;

      Payload_Length_Word := Read_U32_LE (Data, Data'First + 8);
      if Payload_Length_Word > Word_32 (Max_Payload_Length) then
         return Invalid_Payload_Length;
      end if;

      Header.Payload_Length := Natural (Payload_Length_Word);
      Header.Directory_First := Data'First + Header_Length;
      Directory_Length := Header.Field_Count * Directory_Entry_Length;
      Header.Payload_First := Header.Directory_First + Directory_Length;

      if Data'Length < Header_Length + Directory_Length then
         return Directory_Out_Of_Bounds;
      end if;

      if Data'Length < Header_Length + Directory_Length + Header.Payload_Length then
         return Invalid_Payload_Length;
      end if;

      return Validate_Field_Directory (Data, Header);
   end Validate_Record;

   function Read_Field_Span
     (Data   : Byte_Array;
      Header : Record_Header;
      Index  : Natural;
      Span   : out Field_Span) return Parse_Status
   is
      Entry_First : Natural;
      Offset_Word : Word_32;
      Length_Word : Word_32;
   begin
      Span := (others => <>);

      if Index >= Header.Field_Count then
         return Invalid_Field_Count;
      end if;

      Entry_First := Header.Directory_First + Index * Directory_Entry_Length;

      if Entry_First < Data'First
        or else Entry_First > Data'Last
        or else Data'Last - Entry_First < Directory_Entry_Length - 1
      then
         return Directory_Out_Of_Bounds;
      end if;

      Offset_Word := Read_U32_LE (Data, Entry_First);
      Length_Word := Read_U32_LE (Data, Entry_First + 4);

      if Offset_Word > Word_32 (Max_Payload_Length)
        or else Length_Word > Word_32 (Max_Payload_Length)
      then
         return Field_Out_Of_Bounds;
      end if;

      Span.Offset := Natural (Offset_Word);
      Span.Length := Natural (Length_Word);

      if Span.Offset > Header.Payload_Length then
         return Field_Out_Of_Bounds;
      end if;

      if Span.Length > Header.Payload_Length - Span.Offset then
         return Field_Out_Of_Bounds;
      end if;

      return Parse_OK;
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

         Status := Read_Field_Span (Data, Header, Index, Span);
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

   function Build_Record
     (Payload : Byte_Array;
      Fields  : Field_Span_Array;
      Output  : in out Byte_Array) return Parse_Status
   is
      Required_Length : constant Natural  :=
        Encoded_Length (Fields'Length, Payload'Length);
      Payload_Target  : Natural;
      Source_Index    : Natural;
      Entry_First     : Natural;
      Previous_End    : Natural := 0;
   begin
      if Fields'Length > Max_Field_Count then
         return Invalid_Field_Count;
      end if;

      if Payload'Length > Max_Payload_Length then
         return Invalid_Payload_Length;
      end if;

      if Output'Length < Required_Length then
         return Output_Buffer_Too_Small;
      end if;

      for Index in Fields'Range loop
         pragma Loop_Invariant (Previous_End <= Payload'Length);

         if Fields (Index).Offset > Payload'Length then
            return Field_Out_Of_Bounds;
         end if;

         if Fields (Index).Length > Payload'Length - Fields (Index).Offset then
            return Field_Out_Of_Bounds;
         end if;

         if Index /= Fields'First
           and then Fields (Index).Offset < Previous_End
         then
            return Field_Order_Violation;
         end if;

         Previous_End := Fields (Index).Offset + Fields (Index).Length;
      end loop;

      Output (Output'First) := Magic_0;
      Output (Output'First + 1) := Magic_1;
      Output (Output'First + 2) := Magic_2;
      Output (Output'First + 3) := Magic_3;
      Output (Output'First + 4) := Current_Format_Version;
      Output (Output'First + 5) := Byte (Fields'Length);
      Output (Output'First + 6) := 0;
      Output (Output'First + 7) := 0;
      Write_U32_LE (Output, Output'First + 8, Word_32 (Payload'Length));

      for Index in Fields'Range loop
         pragma Loop_Invariant (Index in Fields'Range);

         Entry_First := Output'First + Header_Length
           + (Index - Fields'First) * Directory_Entry_Length;

         Write_U32_LE (Output, Entry_First, Word_32 (Fields (Index).Offset));
         Write_U32_LE (Output, Entry_First + 4, Word_32 (Fields (Index).Length));
      end loop;

      if Payload'Length > 0 then
         Payload_Target := Output'First + Header_Length
           + Fields'Length * Directory_Entry_Length;
         Source_Index := Payload'First;

         for Target in Payload_Target .. Payload_Target + Payload'Length - 1 loop
            pragma Loop_Invariant (Source_Index in Payload'Range);
            Output (Target) := Payload (Source_Index);
            Source_Index := Source_Index + 1;
         end loop;
      end if;

      return Parse_OK;
   end Build_Record;

end Database.Storage.Record_Serializer;
