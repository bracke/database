with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Keys;
with Database.Log_Sequence;
with Database.Status;

package body Database.Encrypted_Persistence is
   use Ada.Streams;
   use type Database.Crypto.Byte;
   use type Database.Crypto_Checks.Encrypted_Artifact_Kind;
   use type Database.Keys.Key_Id;
   use type Database.Log_Sequence.Log_Sequence_Number;

   Header_Size : constant Natural := 108;
   Magic       : constant Database.Crypto.Byte_Array (0 .. 7)  :=
     (Database.Crypto.Byte (Character'Pos ('D')),
      Database.Crypto.Byte (Character'Pos ('B')),
      Database.Crypto.Byte (Character'Pos ('E')),
      Database.Crypto.Byte (Character'Pos ('A')),
      Database.Crypto.Byte (Character'Pos ('R')),
      Database.Crypto.Byte (Character'Pos ('T')),
      Database.Crypto.Byte (Character'Pos ('1')),
      0);

   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   function To_Stream (Data : Database.Crypto.Byte_Array) return Stream_Element_Array is
      Result : Stream_Element_Array
        (Stream_Element_Offset (0) .. Stream_Element_Offset (Data'Length - 1));
   begin
      for I in Data'Range loop
         Result (Stream_Element_Offset (I - Data'First)) := Stream_Element (Data (I));
      end loop;
      return Result;
   end To_Stream;

   function To_Crypto (Data : Stream_Element_Array) return Database.Crypto.Byte_Array is
      Result : Database.Crypto.Byte_Array (0 .. Natural (Data'Length) - 1);
   begin
      for I in Result'Range loop
         Result (I) := Database.Crypto.Byte (Data (Data'First + Stream_Element_Offset (I)));
      end loop;
      return Result;
   end To_Crypto;

   procedure Put_U32
     (Data   : in out Database.Crypto.Byte_Array;
      Offset : Natural;
      Value  : Natural) is
   begin
      Data (Offset + 0) := Database.Crypto.Byte ((Value / 16#1000000#) mod 256);
      Data (Offset + 1) := Database.Crypto.Byte ((Value / 16#10000#) mod 256);
      Data (Offset + 2) := Database.Crypto.Byte ((Value / 16#100#) mod 256);
      Data (Offset + 3) := Database.Crypto.Byte (Value mod 256);
   end Put_U32;

   function Get_U32
     (Data   : Database.Crypto.Byte_Array;
      Offset : Natural) return Natural is
   begin
      return Natural (Data (Offset + 0)) * 16#1000000#
        + Natural (Data (Offset + 1)) * 16#10000#
        + Natural (Data (Offset + 2)) * 16#100#
        + Natural (Data (Offset + 3));
   end Get_U32;

   procedure Put_U64
     (Data   : in out Database.Crypto.Byte_Array;
      Offset : Natural;
      Value  : Database.Log_Sequence.Log_Sequence_Number) is
      X : Database.Log_Sequence.Log_Sequence_Number := Value;
   begin
      for I in reverse 0 .. 7 loop
         Data (Offset + I) := Database.Crypto.Byte (Natural (X mod 256));
         X := X / 256;
      end loop;
   end Put_U64;

   function Get_U64
     (Data   : Database.Crypto.Byte_Array;
      Offset : Natural) return Database.Log_Sequence.Log_Sequence_Number is
      Result : Database.Log_Sequence.Log_Sequence_Number := 0;
   begin
      for I in 0 .. 7 loop
         Result := Result * 256
           + Database.Log_Sequence.Log_Sequence_Number (Data (Offset + I));
      end loop;
      return Result;
   end Get_U64;

   function Status_For
     (Kind : Database.Crypto_Checks.Encrypted_Artifact_Kind)
      return Database.Status.Status_Code is
   begin
      case Kind is
         when Database.Crypto_Checks.Encrypted_Page_Artifact =>
            return Database.Status.Corrupt_Encrypted_Page;
         when Database.Crypto_Checks.Encrypted_WAL_Frame_Artifact =>
            return Database.Status.Corrupt_Encrypted_WAL;
         when Database.Crypto_Checks.Encrypted_Backup_Artifact |
              Database.Crypto_Checks.Encrypted_Backup_Manifest_Artifact =>
            return Database.Status.Corrupt_Backup;
         when Database.Crypto_Checks.Encrypted_Export_Artifact =>
            return Database.Status.Import_Error;
         when Database.Crypto_Checks.Encrypted_Key_Metadata_Artifact =>
            return Database.Status.Invalid_Key;
         when Database.Crypto_Checks.Encrypted_Full_Text_Artifact =>
            return Database.Status.Full_Text_Index_Error;
      end case;
   end Status_For;

   function Default_Header
     (Kind           : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key            : Database.Keys.Encryption_Key;
      Format_Version : Natural;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number;
      Plaintext_Size : Natural) return Persisted_Header is
   begin
      return
        (Kind           => Kind,
         Format_Version => Format_Version,
         Key_Id         => Database.Keys.Identifier (Key),
         Object_Id      => Object_Id,
         LSN            => LSN,
         Plaintext_Size => Plaintext_Size);
   end Default_Header;

   procedure Encode_Header
     (Header : Persisted_Header;
      Nonce  : Database.Crypto.Nonce;
      Tag    : Database.Crypto.Authentication_Tag;
      Bytes  : out Database.Crypto.Byte_Array) is
   begin
      Bytes := (others => 0);
      for I in Magic'Range loop
         Bytes (I) := Magic (I);
      end loop;
      Put_U32 (Bytes, 8, Database.Crypto_Checks.Encrypted_Artifact_Kind'Pos (Header.Kind));
      Put_U32 (Bytes, 12, Header.Format_Version);
      Put_U32 (Bytes, 16, Natural (Header.Key_Id));
      Put_U32 (Bytes, 20, Header.Object_Id);
      Put_U64 (Bytes, 24, Header.LSN);
      Put_U32 (Bytes, 32, Header.Plaintext_Size);
      for I in Nonce'Range loop
         Bytes (36 + I) := Nonce (I);
      end loop;
      for I in Tag'Range loop
         Bytes (60 + I) := Tag (I);
      end loop;
      Put_U32 (Bytes, 92, Header_Size);
      Put_U32 (Bytes, 96, 0);
      Put_U32 (Bytes, 100, 0);
      Put_U32 (Bytes, 104, 0);
   end Encode_Header;

   function Decode_Header
     (Bytes    : Database.Crypto.Byte_Array;
      Expected : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Header   : out Persisted_Header;
      Nonce    : out Database.Crypto.Nonce;
      Tag      : out Database.Crypto.Authentication_Tag) return Database.Status.Result is
      Kind_Pos : Natural;
   begin
      Header := (Kind => Expected, others => <>);
      Nonce := (others => 0);
      Tag := (others => 0);
      if Bytes'Length < Header_Size then
         return Database.Status.Failure (Database.Status.Corruption_Detected,
           "encrypted artifact header is truncated");
      end if;
      for I in Magic'Range loop
         if Bytes (I) /= Magic (I) then
            return Database.Status.Failure (Status_For (Expected),
              "encrypted artifact magic rejected");
         end if;
      end loop;

      Kind_Pos := Get_U32 (Bytes, 8);
      if Kind_Pos > Database.Crypto_Checks.Encrypted_Artifact_Kind'Pos
           (Database.Crypto_Checks.Encrypted_Artifact_Kind'Last)
      then
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact kind is invalid");
      end if;

      Header.Kind := Database.Crypto_Checks.Encrypted_Artifact_Kind'Val (Kind_Pos);
      Header.Format_Version := Get_U32 (Bytes, 12);
      Header.Key_Id := Database.Keys.Key_Id (Get_U32 (Bytes, 16));
      Header.Object_Id := Get_U32 (Bytes, 20);
      Header.LSN := Get_U64 (Bytes, 24);
      Header.Plaintext_Size := Get_U32 (Bytes, 32);

      if Header.Kind /= Expected then
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact kind mismatch");
      end if;
      if Get_U32 (Bytes, 92) /= Header_Size then
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact header size mismatch");
      end if;
      if Get_U32 (Bytes, 96) /= 0 or else
         Get_U32 (Bytes, 100) /= 0 or else
         Get_U32 (Bytes, 104) /= 0
      then
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact reserved header bytes were modified");
      end if;

      for I in Nonce'Range loop
         Nonce (I) := Bytes (36 + I);
      end loop;
      for I in Tag'Range loop
         Tag (I) := Bytes (60 + I);
      end loop;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact header rejected");
   end Decode_Header;

   function Read_All (Path : Wide_Wide_String; Data : out Database.Crypto.Byte_Array)
      return Database.Status.Result is
      File : Ada.Streams.Stream_IO.File_Type;
      Raw  : Stream_Element_Array (0 .. Stream_Element_Offset (Data'Length - 1));
      Last : Stream_Element_Offset;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Native (Path));
      Ada.Streams.Stream_IO.Read (File, Raw, Last);
      Ada.Streams.Stream_IO.Close (File);
      if Last /= Raw'Last then
         return Database.Status.Failure (Database.Status.Corruption_Detected,
           "encrypted artifact short read");
      end if;
      Data := To_Crypto (Raw);
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception when others => null;
         end;
         return Database.Status.Failure (Database.Status.IOError,
           "could not read encrypted artifact");
   end Read_All;

   function Write_Artifact
     (Path           : Wide_Wide_String;
      Kind           : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key            : Database.Keys.Encryption_Key;
      Format_Version : Natural;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number;
      Plaintext      : Database.Crypto.Byte_Array) return Database.Status.Result is
      Header     : constant Persisted_Header  :=
        Default_Header (Kind, Key, Format_Version, Object_Id, LSN, Plaintext'Length);
      Nonce      : constant Database.Crypto.Nonce := Database.Crypto.Generate_Nonce (Object_Id, LSN);
      AD         : constant Database.Crypto.Byte_Array  :=
        Database.Crypto_Checks.Artifact_Associated_Data
          (Kind, Format_Version, Database.Keys.Identifier (Key), Object_Id, LSN);
      Ciphertext : Database.Crypto.Byte_Array (Plaintext'Range);
      Tag        : Database.Crypto.Authentication_Tag;
      H          : Database.Crypto.Byte_Array (0 .. Header_Size - 1);
      File       : Ada.Streams.Stream_IO.File_Type;
      Tmp_Path   : constant Wide_Wide_String := Path & ".write.tmp";
      R          : Database.Status.Result;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key,
           "cannot write encrypted artifact with invalid key");
      end if;
      if Plaintext'Length = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Argument,
           "empty encrypted artifact plaintext rejected");
      end if;
      R := Database.Crypto_Checks.Validate_Key_Metadata (Key, Format_Version);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Crypto.Encrypt (Key, Nonce, AD, Plaintext, Ciphertext, Tag);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Encode_Header (Header, Nonce, Tag, H);

      --  Write the replacement container completely before touching the
      --  previous authenticated artifact.  This preserves the last good
      --  sidecar if an I/O failure occurs while writing the replacement.
      if Ada.Directories.Exists (Native (Tmp_Path)) then
         Ada.Directories.Delete_File (Native (Tmp_Path));
      end if;
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Native (Tmp_Path));
      Ada.Streams.Stream_IO.Write (File, To_Stream (H));
      Ada.Streams.Stream_IO.Write (File, To_Stream (Ciphertext));
      Ada.Streams.Stream_IO.Flush (File);
      Ada.Streams.Stream_IO.Close (File);

      if Ada.Directories.Exists (Native (Path)) then
         Ada.Directories.Delete_File (Native (Path));
      end if;
      Ada.Directories.Rename (Native (Tmp_Path), Native (Path));
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
            if Ada.Directories.Exists (Native (Tmp_Path)) then
               Ada.Directories.Delete_File (Native (Tmp_Path));
            end if;
         exception when others => null;
         end;
         return Database.Status.Failure (Database.Status.IOError,
           "could not write encrypted artifact");
   end Write_Artifact;

   function Read_Artifact
     (Path      : Wide_Wide_String;
      Expected  : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key       : Database.Keys.Encryption_Key;
      Plaintext : out Database.Crypto.Byte_Array) return Read_Result is
      Size       : Natural;
      Header     : Persisted_Header;
      Nonce      : Database.Crypto.Nonce;
      Tag        : Database.Crypto.Authentication_Tag;
      R          : Database.Status.Result;
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return (Result => Database.Status.Failure (Status_For (Expected),
                   "encrypted artifact is missing"),
                 Header => (Kind => Expected, others => <>));
      end if;
      Size := Natural (Ada.Directories.Size (Native (Path)));
      if Size < Header_Size then
         return (Result => Database.Status.Failure (Status_For (Expected),
                   "encrypted artifact is truncated"),
                 Header => (Kind => Expected, others => <>));
      end if;
      if Size /= Header_Size + Plaintext'Length then
         --  Reject impossible size before allocating a file-sized buffer.
         --  Malformed sidecars must not be able to force unbounded memory
         --  use during page read, verification, or fuzzing.
         return (Result => Database.Status.Failure (Status_For (Expected),
                   "encrypted artifact file size does not match expected plaintext size"),
                 Header => (Kind => Expected, others => <>));
      end if;
      declare
         All_Data   : Database.Crypto.Byte_Array (0 .. Size - 1);
      begin
         R := Read_All (Path, All_Data);
         if not Database.Status.Is_Ok (R) then
            return (Result => R, Header => (Kind => Expected, others => <>));
         end if;
         R := Decode_Header (All_Data (0 .. Header_Size - 1), Expected, Header, Nonce, Tag);
         if not Database.Status.Is_Ok (R) then
            return (Result => R, Header => Header);
         end if;
         if Header.Key_Id /= Database.Keys.Identifier (Key) then
            return (Result => Database.Status.Failure (Status_For (Expected),
                      "encrypted artifact key id mismatch"),
                    Header => Header);
         end if;
         if Header.Plaintext_Size = 0 then
            return (Result => Database.Status.Failure (Status_For (Expected),
                      "empty encrypted artifact rejected"),
                    Header => Header);
         end if;
         if Header.Plaintext_Size /= Plaintext'Length then
            return (Result => Database.Status.Failure (Status_For (Expected),
                      "encrypted artifact plaintext size mismatch"),
                    Header => Header);
         end if;
         if Size - Header_Size /= Header.Plaintext_Size then
            return (Result => Database.Status.Failure (Status_For (Expected),
                      "encrypted artifact ciphertext size mismatch"),
                    Header => Header);
         end if;
         declare
            Ciphertext : Database.Crypto.Byte_Array (0 .. Header.Plaintext_Size - 1);
            AD         : constant Database.Crypto.Byte_Array  :=
              Database.Crypto_Checks.Artifact_Associated_Data
                (Header.Kind, Header.Format_Version, Header.Key_Id,
                 Header.Object_Id, Header.LSN);
         begin
            for I in Ciphertext'Range loop
               Ciphertext (I) := All_Data (Header_Size + I);
            end loop;
            R := Database.Crypto.Decrypt (Key, Nonce, AD, Ciphertext, Tag, Plaintext);
            if not Database.Status.Is_Ok (R) then
               return (Result => Database.Status.Failure (Status_For (Expected),
                         "encrypted artifact authentication failed"),
                       Header => Header);
            end if;
         end;
      end;
      return (Result => Database.Status.Success, Header => Header);
   exception
      when others =>
         return (Result => Database.Status.Failure (Status_For (Expected),
                   "encrypted artifact rejected"),
                 Header => (Kind => Expected, others => <>));
   end Read_Artifact;

   function Verify_Artifact_File
     (Path     : Wide_Wide_String;
      Expected : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key      : Database.Keys.Encryption_Key)
      return Database.Crypto_Checks.Check_Result is
      Size : Natural := 0;
      R    : Database.Status.Result;
   begin
      R := Artifact_Plaintext_Size (Path, Expected, Key, Size);
      if not Database.Status.Is_Ok (R) then
         return (Result => R, Authenticated_Items => 0, Failed_Items => 1);
      end if;
      if Size = 0 then
         return
           (Result => Database.Status.Failure (Status_For (Expected),
              "empty encrypted artifact rejected"),
            Authenticated_Items => 0,
            Failed_Items => 1);
      end if;
      declare
         Plain : Database.Crypto.Byte_Array (0 .. Size - 1);
         RR    : constant Read_Result := Read_Artifact (Path, Expected, Key, Plain);
      begin
         Database.Crypto.Clear (Plain);
         if Database.Status.Is_Ok (RR.Result) then
            return (Result => RR.Result, Authenticated_Items => 1, Failed_Items => 0);
         else
            return (Result => RR.Result, Authenticated_Items => 0, Failed_Items => 1);
         end if;
      end;
   end Verify_Artifact_File;

   function Artifact_Plaintext_Size
     (Path     : Wide_Wide_String;
      Expected : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key      : Database.Keys.Encryption_Key;
      Size     : out Natural) return Database.Status.Result is
      File_Size : Natural;
      Header    : Persisted_Header;
      Nonce     : Database.Crypto.Nonce;
      Tag       : Database.Crypto.Authentication_Tag;
      R         : Database.Status.Result;
   begin
      Size := 0;
      if not Ada.Directories.Exists (Native (Path)) then
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact is missing");
      end if;
      File_Size := Natural (Ada.Directories.Size (Native (Path)));
      if File_Size < Header_Size then
         return Database.Status.Failure (Status_For (Expected),
           "encrypted artifact is truncated");
      end if;
      declare
         Bytes : Database.Crypto.Byte_Array (0 .. Header_Size - 1);
         File  : Ada.Streams.Stream_IO.File_Type;
         Raw   : Stream_Element_Array (0 .. Stream_Element_Offset (Header_Size - 1));
         Last  : Stream_Element_Offset;
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Native (Path));
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);
         if Last /= Raw'Last then
            return Database.Status.Failure (Status_For (Expected),
              "encrypted artifact header short read");
         end if;
         Bytes := To_Crypto (Raw);
         R := Decode_Header (Bytes, Expected, Header, Nonce, Tag);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         if Header.Key_Id /= Database.Keys.Identifier (Key) then
            return Database.Status.Failure (Status_For (Expected),
              "encrypted artifact key id mismatch");
         end if;
         if Header.Plaintext_Size = 0 then
            return Database.Status.Failure (Status_For (Expected),
              "empty encrypted artifact rejected");
         end if;
         if Header.Plaintext_Size /= File_Size - Header_Size then
            return Database.Status.Failure (Status_For (Expected),
              "encrypted artifact size metadata mismatch");
         end if;
         Size := Header.Plaintext_Size;
         return Database.Status.Success;
      exception
         when others =>
            begin
               if Ada.Streams.Stream_IO.Is_Open (File) then
                  Ada.Streams.Stream_IO.Close (File);
               end if;
            exception when others => null;
            end;
            return Database.Status.Failure (Database.Status.IOError,
              "could not read encrypted artifact header");
      end;
   end Artifact_Plaintext_Size;

   function Tamper_Byte
     (Path   : Wide_Wide_String;
      Offset : Natural;
      Mask   : Byte := 16#55#) return Database.Status.Result is
      File_Size : Natural;
      File      : Ada.Streams.Stream_IO.File_Type;

      function Existing_Path return Wide_Wide_String is
      begin
         if Ada.Directories.Exists (Native (Path)) then
            return Path;
         end if;
         declare
            Compact : Wide_Wide_String (Path'Range);
            Last    : Natural := Compact'First - 1;
         begin
            for I in Path'Range loop
               if Path (I) /= ' ' then
                  Last := Last + 1;
                  Compact (Last) := Path (I);
               end if;
            end loop;
            if Last >= Compact'First
              and then Ada.Directories.Exists (Native (Compact (Compact'First .. Last)))
            then
               return Compact (Compact'First .. Last);
            end if;
         end;
         return "";
      end Existing_Path;
   begin
      declare
         Actual : constant Wide_Wide_String := Existing_Path;
      begin
      if Actual'Length = 0 then
         return Database.Status.Failure (Database.Status.Not_Found,
           "encrypted artifact to tamper does not exist");
      end if;
      File_Size := Natural (Ada.Directories.Size (Native (Actual)));
      if Offset >= File_Size then
         return Database.Status.Failure (Database.Status.Invalid_Argument,
           "tamper offset is outside encrypted artifact");
      end if;
         declare
            Data : Database.Crypto.Byte_Array (0 .. File_Size - 1);
         begin
            declare
               R : constant Database.Status.Result := Read_All (Actual, Data);
            begin
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end;
            Data (Offset) := Data (Offset) xor Mask;
            Ada.Directories.Delete_File (Native (Actual));
            Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Native (Actual));
            Ada.Streams.Stream_IO.Write (File, To_Stream (Data));
            Ada.Streams.Stream_IO.Close (File);
         end;
      end;
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception when others => null;
         end;
         return Database.Status.Failure (Database.Status.IOError,
           "could not tamper encrypted artifact");
   end Tamper_Byte;

   function Truncate_File
     (Path     : Wide_Wide_String;
      New_Size : Natural) return Database.Status.Result is
      File_Size : Natural;
      Inp       : Ada.Streams.Stream_IO.File_Type;
      Outp      : Ada.Streams.Stream_IO.File_Type;
      Tmp_Path  : constant Wide_Wide_String := Path & ".truncate.tmp";
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return Database.Status.Failure (Database.Status.Not_Found,
           "encrypted artifact to truncate does not exist");
      end if;
      File_Size := Natural (Ada.Directories.Size (Native (Path)));
      if New_Size > File_Size then
         return Database.Status.Failure (Database.Status.Invalid_Argument,
           "truncate size exceeds encrypted artifact size");
      end if;
      if Ada.Directories.Exists (Native (Tmp_Path)) then
         Ada.Directories.Delete_File (Native (Tmp_Path));
      end if;
      Ada.Streams.Stream_IO.Open (Inp, Ada.Streams.Stream_IO.In_File, Native (Path));
      Ada.Streams.Stream_IO.Create (Outp, Ada.Streams.Stream_IO.Out_File, Native (Tmp_Path));
      if New_Size > 0 then
         declare
            Data : Stream_Element_Array (0 .. Stream_Element_Offset (New_Size - 1));
            Last : Stream_Element_Offset;
         begin
            Ada.Streams.Stream_IO.Read (Inp, Data, Last);
            if Last /= Data'Last then
               Ada.Streams.Stream_IO.Close (Inp);
               Ada.Streams.Stream_IO.Close (Outp);
               begin
                  if Ada.Directories.Exists (Native (Tmp_Path)) then
                     Ada.Directories.Delete_File (Native (Tmp_Path));
                  end if;
               exception when others => null;
               end;
               return Database.Status.Failure (Database.Status.Corruption_Detected,
                 "encrypted artifact truncation short read");
            end if;
            Ada.Streams.Stream_IO.Write (Outp, Data);
         end;
      end if;
      Ada.Streams.Stream_IO.Close (Inp);
      Ada.Streams.Stream_IO.Close (Outp);
      Ada.Directories.Delete_File (Native (Path));
      Ada.Directories.Rename (Native (Tmp_Path), Native (Path));
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (Inp) then
               Ada.Streams.Stream_IO.Close (Inp);
            end if;
            if Ada.Streams.Stream_IO.Is_Open (Outp) then
               Ada.Streams.Stream_IO.Close (Outp);
            end if;
            if Ada.Directories.Exists (Native (Tmp_Path)) then
               Ada.Directories.Delete_File (Native (Tmp_Path));
            end if;
         exception when others => null;
         end;
         return Database.Status.Failure (Database.Status.IOError,
           "could not truncate encrypted artifact");
   end Truncate_File;

end Database.Encrypted_Persistence;
