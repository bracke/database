with Ada.Streams;
with CryptoLib.Ciphers;
with CryptoLib.Constant_Time;
with CryptoLib.Errors;
with CryptoLib.Hashes;
with CryptoLib.Macs;
with CryptoLib.Secure_Wipe;
with Interfaces;

package body Database.Crypto is
   use type Ada.Streams.Stream_Element_Offset;
   use type CryptoLib.Errors.Status;
   use type Interfaces.Unsigned_64;
   use type Database.Storage.Pages.Byte;

   subtype Stream_Array is Ada.Streams.Stream_Element_Array;

   function To_Stream (Data : Byte_Array) return Stream_Array is
      Result : Stream_Array (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
      Pos    : Ada.Streams.Stream_Element_Offset := Result'First;
   begin
      for I in Data'Range loop
         Result (Pos) := Ada.Streams.Stream_Element (Data (I));
         Pos := Pos + 1;
      end loop;
      return Result;
   end To_Stream;

   procedure Copy_From_Stream
     (Source : Stream_Array;
      Target : out Byte_Array)
   is
      Pos : Ada.Streams.Stream_Element_Offset := Source'First;
   begin
      for I in Target'Range loop
         Target (I) := Byte (Source (Pos));
         Pos := Pos + 1;
      end loop;
   end Copy_From_Stream;

   function Key_To_Stream (Key : Database.Keys.Encryption_Key) return Stream_Array is
      Result : Stream_Array (1 .. 32);
   begin
      for I in Result'Range loop
         Result (I) := Ada.Streams.Stream_Element
           (Database.Keys.Byte_At (Key, Natural (I - Result'First)));
      end loop;
      return Result;
   end Key_To_Stream;

   procedure Put_U32
     (Data   : in out Stream_Array;
      Offset : Ada.Streams.Stream_Element_Offset;
      Value  : Natural) is
   begin
      Data (Offset + 0) := Ada.Streams.Stream_Element ((Value / 16#1000000#) mod 256);
      Data (Offset + 1) := Ada.Streams.Stream_Element ((Value / 16#10000#) mod 256);
      Data (Offset + 2) := Ada.Streams.Stream_Element ((Value / 16#100#) mod 256);
      Data (Offset + 3) := Ada.Streams.Stream_Element (Value mod 256);
   end Put_U32;

   function Nonce_IV (Nonce_Value : Nonce) return Stream_Array is
      Digest : constant CryptoLib.Hashes.SHA256_Digest :=
        CryptoLib.Hashes.SHA256 (To_Stream (Nonce_Value));
      Result : Stream_Array (1 .. 16);
   begin
      for I in Result'Range loop
         Result (I) := Digest (Positive (I));
      end loop;
      return Result;
   end Nonce_IV;

   function Generate_Nonce
     (Object_Id : Natural;
      LSN       : Database.Log_Sequence.Log_Sequence_Number) return Nonce
   is
      Seed : Stream_Array (1 .. 16) := (others => 0);
      D1   : CryptoLib.Hashes.SHA256_Digest;
      D2   : CryptoLib.Hashes.SHA256_Digest;
      N    : Nonce := (others => 0);
   begin
      Put_U32 (Seed, 1, Object_Id);
      Put_U32 (Seed, 5, Natural (Interfaces.Shift_Right (Interfaces.Unsigned_64 (LSN), 32)));
      Put_U32 (Seed, 9, Natural (Interfaces.Unsigned_64 (LSN) and 16#FFFF_FFFF#));
      Seed (13) := Ada.Streams.Stream_Element (Character'Pos ('D'));
      Seed (14) := Ada.Streams.Stream_Element (Character'Pos ('B'));
      Seed (15) := Ada.Streams.Stream_Element (Character'Pos ('N'));
      Seed (16) := Ada.Streams.Stream_Element (Character'Pos ('1'));
      D1 := CryptoLib.Hashes.SHA256 (Seed);
      Seed (16) := Ada.Streams.Stream_Element (Character'Pos ('2'));
      D2 := CryptoLib.Hashes.SHA256 (Seed);
      for I in 0 .. 15 loop
         N (I) := Byte (D1 (I + 1));
      end loop;
      for I in 16 .. 23 loop
         N (I) := Byte (D2 (I - 15));
      end loop;
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
      return N;
   end Generate_Nonce;

   function MAC_Message
     (Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Ciphertext      : Byte_Array) return Stream_Array
   is
      Domain : constant String := "DBENC1";
      Total  : constant Ada.Streams.Stream_Element_Offset :=
        Ada.Streams.Stream_Element_Offset
          (Domain'Length + 4 + Nonce_Value'Length + 4 + Associated_Data'Length + 4 + Ciphertext'Length);
      Result : Stream_Array (1 .. Total);
      Pos    : Ada.Streams.Stream_Element_Offset := Result'First;
   begin
      for C of Domain loop
         Result (Pos) := Ada.Streams.Stream_Element (Character'Pos (C));
         Pos := Pos + 1;
      end loop;
      Put_U32 (Result, Pos, Nonce_Value'Length);
      Pos := Pos + 4;
      for I in Nonce_Value'Range loop
         Result (Pos) := Ada.Streams.Stream_Element (Nonce_Value (I));
         Pos := Pos + 1;
      end loop;
      Put_U32 (Result, Pos, Associated_Data'Length);
      Pos := Pos + 4;
      for I in Associated_Data'Range loop
         Result (Pos) := Ada.Streams.Stream_Element (Associated_Data (I));
         Pos := Pos + 1;
      end loop;
      Put_U32 (Result, Pos, Ciphertext'Length);
      Pos := Pos + 4;
      for I in Ciphertext'Range loop
         Result (Pos) := Ada.Streams.Stream_Element (Ciphertext (I));
         Pos := Pos + 1;
      end loop;
      return Result;
   end MAC_Message;

   function Compute_MAC
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Ciphertext      : Byte_Array) return Authentication_Tag
   is
      Key_Data : Stream_Array (1 .. 32) := Key_To_Stream (Key);
      Message  : Stream_Array := MAC_Message (Nonce_Value, Associated_Data, Ciphertext);
      Digest   : constant CryptoLib.Macs.HMAC_SHA256_Digest :=
        CryptoLib.Macs.HMAC_SHA256 (Key_Data, Message);
      T        : Authentication_Tag := (others => 0);
   begin
      for I in T'Range loop
         T (I) := Byte (Digest (I + 1));
      end loop;
      CryptoLib.Secure_Wipe.Wipe (Key_Data'Address, Key_Data'Length);
      CryptoLib.Secure_Wipe.Wipe (Message'Address, Message'Length);
      return T;
   end Compute_MAC;

   function Transform_AES256_CTR
     (Key        : Database.Keys.Encryption_Key;
      Nonce_Value : Nonce;
      Input      : Byte_Array;
      Output     : out Byte_Array;
      Encrypting : Boolean) return Database.Status.Result
   is
      State     : CryptoLib.Ciphers.Cipher_State;
      Key_Data  : Stream_Array (1 .. 32) := Key_To_Stream (Key);
      IV_Data   : Stream_Array (1 .. 16) := Nonce_IV (Nonce_Value);
      In_Data   : Stream_Array := To_Stream (Input);
      Out_Data  : Stream_Array (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Status    : CryptoLib.Errors.Status;
   begin
      Status := CryptoLib.Ciphers.Initialize
        (State, "aes256-ctr", CryptoLib.Ciphers.Client_To_Server, Key_Data, IV_Data);
      if not CryptoLib.Errors.Is_Success (Status) then
         CryptoLib.Secure_Wipe.Wipe (Key_Data'Address, Key_Data'Length);
         CryptoLib.Secure_Wipe.Wipe (IV_Data'Address, IV_Data'Length);
         CryptoLib.Secure_Wipe.Wipe (In_Data'Address, In_Data'Length);
         return Database.Status.Failure
           (Database.Status.Encryption_Error,
            "cryptolib AES-256-CTR initialization failed");
      end if;

      if Encrypting then
         Status := CryptoLib.Ciphers.Encrypt (State, In_Data, Out_Data);
      else
         Status := CryptoLib.Ciphers.Decrypt (State, In_Data, Out_Data);
      end if;

      CryptoLib.Ciphers.Reset (State);
      CryptoLib.Secure_Wipe.Wipe (Key_Data'Address, Key_Data'Length);
      CryptoLib.Secure_Wipe.Wipe (IV_Data'Address, IV_Data'Length);
      CryptoLib.Secure_Wipe.Wipe (In_Data'Address, In_Data'Length);

      if not CryptoLib.Errors.Is_Success (Status) then
         CryptoLib.Secure_Wipe.Wipe (Out_Data'Address, Out_Data'Length);
         return Database.Status.Failure
           (Database.Status.Encryption_Error,
            "cryptolib AES-256-CTR transform failed");
      end if;

      Copy_From_Stream (Out_Data, Output);
      CryptoLib.Secure_Wipe.Wipe (Out_Data'Address, Out_Data'Length);
      return Database.Status.Success;
   end Transform_AES256_CTR;

   function Encrypt
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Plaintext       : Byte_Array;
      Ciphertext      : out Byte_Array;
      Tag             : out Authentication_Tag) return Database.Status.Result
   is
      R : Database.Status.Result;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encryption key is not valid");
      end if;
      if Ciphertext'Length /= Plaintext'Length then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "ciphertext buffer has wrong length");
      end if;

      R := Transform_AES256_CTR (Key, Nonce_Value, Plaintext, Ciphertext, True);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      Tag := Compute_MAC (Key, Nonce_Value, Associated_Data, Ciphertext);
      return Database.Status.Success;
   end Encrypt;

   function Decrypt
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Ciphertext      : Byte_Array;
      Tag             : Authentication_Tag;
      Plaintext       : out Byte_Array) return Database.Status.Result
   is
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encryption key is not valid");
      end if;
      if Plaintext'Length /= Ciphertext'Length then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "plaintext buffer has wrong length");
      end if;

      declare
         Expected : constant Authentication_Tag :=
           Compute_MAC (Key, Nonce_Value, Associated_Data, Ciphertext);
      begin
         if not CryptoLib.Constant_Time.Equal (To_Stream (Expected), To_Stream (Tag)) then
            return Database.Status.Failure
              (Database.Status.Authentication_Failure, "ciphertext authentication failed");
         end if;

         return Transform_AES256_CTR (Key, Nonce_Value, Ciphertext, Plaintext, False);
      end;
   end Decrypt;

   procedure Clear (Data : in out Byte_Array) is
   begin
      CryptoLib.Secure_Wipe.Wipe (Data'Address, Data'Length);
      Data := (others => 0);
   end Clear;
end Database.Crypto;
