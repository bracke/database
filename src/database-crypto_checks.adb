with Database.Status;
with Database.Crypto;
with Database.Keys;
with Database.Log_Sequence;

package body Database.Crypto_Checks is
   use type Database.Log_Sequence.Log_Sequence_Number;

   function Status_For (Kind : Encrypted_Artifact_Kind) return Database.Status.Status_Code is
   begin
      case Kind is
         when Encrypted_Page_Artifact =>
            return Database.Status.Corrupt_Encrypted_Page;
         when Encrypted_WAL_Frame_Artifact =>
            return Database.Status.Corrupt_Encrypted_WAL;
         when Encrypted_Backup_Artifact =>
            return Database.Status.Corrupt_Backup;
         when Encrypted_Export_Artifact =>
            return Database.Status.Import_Error;
         when Encrypted_Key_Metadata_Artifact =>
            return Database.Status.Invalid_Key;
         when Encrypted_Backup_Manifest_Artifact =>
            return Database.Status.Corrupt_Backup;
         when Encrypted_Full_Text_Artifact =>
            return Database.Status.Full_Text_Index_Error;
      end case;
   end Status_For;

   procedure Put_U32
     (Data   : in out Database.Crypto.Byte_Array;
      Offset : Natural;
      Value  : Natural)
   is
   begin
      Data (Offset + 0) := Database.Crypto.Byte ((Value / 16#1000000#) mod 256);
      Data (Offset + 1) := Database.Crypto.Byte ((Value / 16#10000#) mod 256);
      Data (Offset + 2) := Database.Crypto.Byte ((Value / 16#100#) mod 256);
      Data (Offset + 3) := Database.Crypto.Byte (Value mod 256);
   end Put_U32;

   function Artifact_Associated_Data
     (Kind           : Encrypted_Artifact_Kind;
      Format_Version : Natural;
      Key_Id         : Database.Keys.Key_Id;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number)
      return Database.Crypto.Byte_Array
   is
      Data : Database.Crypto.Byte_Array (0 .. 23) := (others => 0);
      L    : Natural := Natural (LSN mod Database.Log_Sequence.Log_Sequence_Number (Natural'Last));
   begin
      Data (0) := Database.Crypto.Byte (Character'Pos ('D'));
      Data (1) := Database.Crypto.Byte (Character'Pos ('B'));
      Data (2) := Database.Crypto.Byte (Character'Pos ('E'));
      Data (3) := Database.Crypto.Byte (Character'Pos ('A'));
      Put_U32 (Data, 4, Encrypted_Artifact_Kind'Pos (Kind));
      Put_U32 (Data, 8, Format_Version);
      Put_U32 (Data, 12, Natural (Key_Id));
      Put_U32 (Data, 16, Object_Id);
      Put_U32 (Data, 20, L);
      return Data;
   end Artifact_Associated_Data;

   function Verify_Encrypted_Artifact
     (Kind           : Encrypted_Artifact_Kind;
      Key            : Database.Keys.Encryption_Key;
      Format_Version : Natural;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number;
      Nonce_Value    : Database.Crypto.Nonce;
      Ciphertext     : Database.Crypto.Byte_Array;
      Tag            : Database.Crypto.Authentication_Tag) return Check_Result
   is
      Meta : constant Database.Status.Result := Validate_Key_Metadata (Key, Format_Version);
      AD   : constant Database.Crypto.Byte_Array  :=
        Artifact_Associated_Data
          (Kind, Format_Version, Database.Keys.Identifier (Key), Object_Id, LSN);
      Plain : Database.Crypto.Byte_Array (Ciphertext'Range);
      R : Database.Status.Result;
   begin
      if not Database.Status.Is_Ok (Meta) then
         return (Result => Meta, Authenticated_Items => 0, Failed_Items => 1);
      end if;
      if Ciphertext'Length = 0 then
         return
           (Result => Database.Status.Failure
              (Status_For (Kind), "empty encrypted artifact rejected"),
            Authenticated_Items => 0,
            Failed_Items => 1);
      end if;
      R := Database.Crypto.Decrypt (Key, Nonce_Value, AD, Ciphertext, Tag, Plain);
      if Database.Status.Is_Ok (R) then
         Database.Crypto.Clear (Plain);
         return (Result => R, Authenticated_Items => 1, Failed_Items => 0);
      else
         Database.Crypto.Clear (Plain);
         return
           (Result => Database.Status.Failure
              (Status_For (Kind), "encrypted artifact authentication failed"),
            Authenticated_Items => 0,
            Failed_Items => 1);
      end if;
   end Verify_Encrypted_Artifact;
   function Verify_Authenticated_Buffer
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Database.Crypto.Nonce;
      Associated_Data : Database.Crypto.Byte_Array;
      Ciphertext      : Database.Crypto.Byte_Array;
      Tag             : Database.Crypto.Authentication_Tag) return Check_Result
   is
      Plain : Database.Crypto.Byte_Array (Ciphertext'Range);
      R     : Database.Status.Result;
   begin
      R := Database.Crypto.Decrypt
        (Key, Nonce_Value, Associated_Data, Ciphertext, Tag, Plain);
      if Database.Status.Is_Ok (R) then
         Database.Crypto.Clear (Plain);
         return (Result => R, Authenticated_Items => 1, Failed_Items => 0);
      else
         return (Result => R, Authenticated_Items => 0, Failed_Items => 1);
      end if;
   end Verify_Authenticated_Buffer;

   function Validate_Key_Metadata
     (Key              : Database.Keys.Encryption_Key;
      Format_Version   : Natural) return Database.Status.Result is
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "invalid encryption key metadata");
      end if;
      if Format_Version /= 1 then
         return Database.Status.Failure (Database.Status.Unsupported_Encryption_Format,
           "unsupported encryption metadata version");
      end if;
      return Database.Status.Success;
   end Validate_Key_Metadata;
end Database.Crypto_Checks;
