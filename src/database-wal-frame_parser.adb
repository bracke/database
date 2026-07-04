with Interfaces;
with Database.Checksums;

package body Database.WAL.Frame_Parser is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;

   function To_Checksum_Array
     (Data  : Byte_Array;
      First : Natural;
      Last  : Natural) return Database.Checksums.Byte_Array
   with
      Pre => First <= Last
        and then First in Data'Range
        and then Last in Data'Range,
      Global => null
   is
      Result : Database.Checksums.Byte_Array (0 .. Last - First);
      Target : Natural := 0;
   begin
      for Source in First .. Last loop
         pragma Loop_Invariant (Target <= Result'Length);
         Result (Target) := Database.Checksums.Byte (Data (Source));
         Target := Target + 1;
      end loop;

      return Result;
   end To_Checksum_Array;

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

   function Decode_Kind (Raw : Byte) return Frame_Kind is
   begin
      case Raw is
         when 1 =>
            return Page_Image;
         when 2 =>
            return Commit_Marker;
         when 3 =>
            return Checkpoint_Marker;
         when others =>
            return Unknown_Frame;
      end case;
   end Decode_Kind;

   function Build_Header_Checksum
     (Data : Byte_Array;
      Seq  : LSN) return Word_32
   is
      Header_Prefix : constant Database.Checksums.Byte_Array  :=
        To_Checksum_Array (Data, Data'First, Data'First + 27);
   begin
      return Database.Checksums.Page_Checksum
        (Database.Checksums.Word_32 (Seq),
         Header_Prefix);
   end Build_Header_Checksum;

   function Payload_Checksum
     (Page_Id : Page_Id_Type;
      Payload : Byte_Array) return Word_32
   is
   begin
      if Payload'Length = 0 then
         declare
            Empty : constant Database.Checksums.Byte_Array (1 .. 0) := (others => 0);
         begin
            return Database.Checksums.Page_Checksum
              (Database.Checksums.Word_32 (Page_Id),
               Empty);
         end;
      else
         declare
            Payload_Data : Database.Checksums.Byte_Array (0 .. Payload'Length - 1);
            Target       : Natural := 0;
         begin
            for Source in Payload'Range loop
               pragma Loop_Invariant (Target <= Payload_Data'Length);
               Payload_Data (Target) := Database.Checksums.Byte (Payload (Source));
               Target := Target + 1;
            end loop;

            return Database.Checksums.Page_Checksum
              (Database.Checksums.Word_32 (Page_Id),
               Payload_Data);
         end;
      end if;
   end Payload_Checksum;

   function Validate_Header_Only
     (Data              : Byte_Array;
      Expected_Previous : LSN;
      Header            : out Frame_Header) return Parse_Status
   is
      Payload_Length_Word : Word_32;
   begin
      Header := (others => <>);

      if Data'Length < Header_Length then
         return Frame_Too_Short;
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

      Header.Kind := Decode_Kind (Data (Data'First + 5));
      if Header.Kind = Unknown_Frame then
         return Invalid_Frame_Kind;
      end if;

      if Data (Data'First + 6) /= 0
        or else Data (Data'First + 7) /= 0
      then
         return Invalid_Reserved_Bytes;
      end if;

      Header.Sequence := LSN (Read_U32_LE (Data, Data'First + 8));
      Header.Previous_Sequence := LSN (Read_U32_LE (Data, Data'First + 12));
      Header.Page_Id := Page_Id_Type (Read_U32_LE (Data, Data'First + 16));
      Payload_Length_Word := Read_U32_LE (Data, Data'First + 20);
      Header.Payload_Checksum := Read_U32_LE (Data, Data'First + 24);
      Header.Header_Checksum := Read_U32_LE (Data, Data'First + 28);

      if Payload_Length_Word > Word_32 (Max_Payload_Length) then
         return Invalid_Payload_Length;
      end if;

      Header.Payload_Length := Natural (Payload_Length_Word);

      if Data'Length < Header_Length + Header.Payload_Length then
         return Invalid_Payload_Length;
      end if;

      if Header.Previous_Sequence /= Expected_Previous then
         return LSN_Order_Violation;
      end if;

      if Header.Header_Checksum /=
        Build_Header_Checksum (Data, Header.Sequence)
      then
         return Header_Checksum_Mismatch;
      end if;

      return Parse_OK;
   end Validate_Header_Only;

   function Validate_Frame
     (Data              : Byte_Array;
      Expected_Previous : LSN;
      Header            : out Frame_Header) return Parse_Status
   is
      Header_Status : Parse_Status;
   begin
      Header_Status := Validate_Header_Only (Data, Expected_Previous, Header);

      if Header_Status /= Parse_OK then
         return Header_Status;
      end if;

      if Header.Payload_Length = 0 then
         declare
            Empty : constant Byte_Array (1 .. 0) := (others => 0);
         begin
            if Header.Payload_Checksum /=
              Payload_Checksum (Header.Page_Id, Empty)
            then
               return Payload_Checksum_Mismatch;
            end if;
         end;
      else
         declare
            First_Payload : constant Natural := Data'First + Header_Length;
            Last_Payload  : constant Natural  :=
              First_Payload + Header.Payload_Length - 1;
            Payload       : constant Byte_Array  :=
              Data (First_Payload .. Last_Payload);
         begin
            if Header.Payload_Checksum /=
              Payload_Checksum (Header.Page_Id, Payload)
            then
               return Payload_Checksum_Mismatch;
            end if;
         end;
      end if;

      return Parse_OK;
   end Validate_Frame;

end Database.WAL.Frame_Parser;
