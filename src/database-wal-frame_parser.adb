with Interfaces;
with Database.Checksums;

package body Database.WAL.Frame_Parser is
   pragma SPARK_Mode (On);
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;

   function To_Checksum_Array
     (Data  : Byte_Array;
      First : Natural;
      Last  : Natural) return Database.Checksums.Byte_Array
   with
      Pre => First <= Last
        and then First in Data'Range
        and then Last in Data'Range
        and then Last - First <= Max_Payload_Length,
      Global => null
   is
      Result : Database.Checksums.Byte_Array (0 .. Last - First);
      Source : Natural;
   begin
      for Target in Result'Range loop
         pragma Loop_Invariant (Target in Result'Range);
         Source := First + Target;
         Result (Target) := Database.Checksums.Byte (Data (Source));
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
      if Payload'First > Payload'Last then
         declare
            Empty : constant Database.Checksums.Byte_Array (1 .. 0) := (others => 0);
         begin
            return Database.Checksums.Page_Checksum
              (Database.Checksums.Word_32 (Page_Id),
               Empty);
         end;
      elsif Payload'First > Natural'Last - Max_Payload_Length then
         return 0;
      elsif Payload'Last - Payload'First >= Max_Payload_Length then
         return 0;
      else
         declare
            Last_Target  : constant Natural := Payload'Last - Payload'First;
            Payload_Data : Database.Checksums.Byte_Array (0 .. Last_Target);
            Source       : Natural;
         begin
            for Target in Payload_Data'Range loop
               pragma Loop_Invariant (Target in Payload_Data'Range);
               Source := Payload'First + Target;
               Payload_Data (Target) := Database.Checksums.Byte (Payload (Source));
            end loop;

            return Database.Checksums.Page_Checksum
              (Database.Checksums.Word_32 (Page_Id),
               Payload_Data);
         end;
      end if;
   end Payload_Checksum;

   procedure Validate_Header_Only
     (Data              : Byte_Array;
      Expected_Previous : LSN;
      Header            : out Frame_Header;
      Status            : out Parse_Status)
   is
      Payload_Length_Word : Word_32;
   begin
      Header := (others => <>);

      if Data'First > Data'Last then
         Status := Frame_Too_Short;
         return;
      end if;

      if Data'First > Natural'Last - (Header_Length - 1) then
         Status := Frame_Too_Short;
         return;
      end if;

      if Data'Last - Data'First < Header_Length - 1 then
         Status := Frame_Too_Short;
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

      Header.Kind := Decode_Kind (Data (Data'First + 5));
      if Header.Kind = Unknown_Frame then
         Status := Invalid_Frame_Kind;
         return;
      end if;

      if Data (Data'First + 6) /= 0
        or else Data (Data'First + 7) /= 0
      then
         Status := Invalid_Reserved_Bytes;
         return;
      end if;

      Header.Sequence := LSN (Read_U32_LE (Data, Data'First + 8));
      Header.Previous_Sequence := LSN (Read_U32_LE (Data, Data'First + 12));
      Header.Page_Id := Page_Id_Type (Read_U32_LE (Data, Data'First + 16));
      Payload_Length_Word := Read_U32_LE (Data, Data'First + 20);
      Header.Payload_Checksum := Read_U32_LE (Data, Data'First + 24);
      Header.Header_Checksum := Read_U32_LE (Data, Data'First + 28);

      if Payload_Length_Word > Word_32 (Max_Payload_Length) then
         Status := Invalid_Payload_Length;
         return;
      end if;

      Header.Payload_Length := Natural (Payload_Length_Word);

      if Data'Last - Data'First < Header_Length + Header.Payload_Length - 1 then
         Status := Invalid_Payload_Length;
         return;
      end if;

      if Data'First > Natural'Last - Header_Length - Header.Payload_Length then
         Status := Invalid_Payload_Length;
         return;
      end if;

      if Header.Previous_Sequence /= Expected_Previous then
         Status := LSN_Order_Violation;
         return;
      end if;

      if Header.Header_Checksum /=
        Build_Header_Checksum (Data, Header.Sequence)
      then
         Status := Header_Checksum_Mismatch;
         return;
      end if;

      Status := Parse_OK;
   end Validate_Header_Only;

   procedure Validate_Frame
     (Data              : Byte_Array;
      Expected_Previous : LSN;
      Header            : out Frame_Header;
      Status            : out Parse_Status)
   is
      Header_Status : Parse_Status;
   begin
      Validate_Header_Only (Data, Expected_Previous, Header, Header_Status);

      if Header_Status /= Parse_OK then
         Status := Header_Status;
         return;
      end if;

      if Header.Payload_Length = 0 then
         declare
            Empty : constant Byte_Array (1 .. 0) := (others => 0);
         begin
            if Header.Payload_Checksum /=
              Payload_Checksum (Header.Page_Id, Empty)
            then
               Status := Payload_Checksum_Mismatch;
               return;
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
               Status := Payload_Checksum_Mismatch;
               return;
            end if;
         end;
      end if;

      Status := Parse_OK;
   end Validate_Frame;

end Database.WAL.Frame_Parser;
