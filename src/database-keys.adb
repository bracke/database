with Ada.Streams;
with CryptoLib.Macs;
with CryptoLib.Secure_Wipe;

package body Database.Keys is
   use type Ada.Streams.Stream_Element_Offset;
   use Database.Storage.Pages;

   subtype Stream_Array is Ada.Streams.Stream_Element_Array;

   function Empty_Key return Encryption_Key is
   begin
      return (Valid => False, Id => 0, Data => (others => 0));
   end Empty_Key;

   function Is_Valid (Key : Encryption_Key) return Boolean is (Key.Valid);
   function Identifier (Key : Encryption_Key) return Key_Id is (Key.Id);

   function Default_Salt return Fixed_Salt is
      S : Fixed_Salt;
   begin
      for I in S'Range loop
         S (I) := Byte ((I * 37 + 113) mod 256);
      end loop;
      return S;
   end Default_Salt;

   function Salt_To_Stream (Salt : Salt_Type) return Stream_Array is
      Result : Stream_Array (1 .. Ada.Streams.Stream_Element_Offset (Salt'Length));
      Pos    : Ada.Streams.Stream_Element_Offset := Result'First;
   begin
      for I in Salt'Range loop
         Result (Pos) := Ada.Streams.Stream_Element (Salt (I));
         Pos := Pos + 1;
      end loop;
      return Result;
   end Salt_To_Stream;

   function Passphrase_To_Stream (Passphrase : Wide_Wide_String) return Stream_Array is
      Result : Stream_Array (1 .. Ada.Streams.Stream_Element_Offset (Passphrase'Length * 4));
      Pos    : Ada.Streams.Stream_Element_Offset := Result'First;
      V      : Natural;
   begin
      for C of Passphrase loop
         V := Wide_Wide_Character'Pos (C);
         Result (Pos + 0) := Ada.Streams.Stream_Element (V mod 256);
         Result (Pos + 1) := Ada.Streams.Stream_Element ((V / 256) mod 256);
         Result (Pos + 2) := Ada.Streams.Stream_Element ((V / 65536) mod 256);
         Result (Pos + 3) := Ada.Streams.Stream_Element ((V / 16777216) mod 256);
         Pos := Pos + 4;
      end loop;
      return Result;
   end Passphrase_To_Stream;

   function Derive_Key
     (Passphrase : Wide_Wide_String;
      Salt       : Salt_Type) return Encryption_Key
   is
      Password_Data : Stream_Array := Passphrase_To_Stream (Passphrase);
      Salt_Data     : Stream_Array := Salt_To_Stream (Salt);
      Derived       : Stream_Array := CryptoLib.Macs.PBKDF2_HMAC_SHA256
        (Password_Data, Salt_Data, 100_000, 32);
      Data          : Binary_Key := (others => 0);
   begin
      for I in Data'Range loop
         Data (I) := Byte (Derived (Derived'First + Ada.Streams.Stream_Element_Offset (I)));
      end loop;
      CryptoLib.Secure_Wipe.Wipe (Password_Data'Address, Password_Data'Length);
      CryptoLib.Secure_Wipe.Wipe (Salt_Data'Address, Salt_Data'Length);
      CryptoLib.Secure_Wipe.Wipe (Derived'Address, Derived'Length);
      return (Valid => True, Id => 1, Data => Data);
   end Derive_Key;

   function From_Binary_Key
     (Bytes : Binary_Key;
      Id    : Key_Id := 1) return Encryption_Key is
   begin
      return (Valid => True, Id => Id, Data => Bytes);
   end From_Binary_Key;

   procedure Clear (Key : in out Encryption_Key) is
   begin
      CryptoLib.Secure_Wipe.Wipe (Key.Data'Address, Key.Data'Length);
      Key.Data := (others => 0);
      Key.Id := 0;
      Key.Valid := False;
   end Clear;

   function Validate_Format (Bytes : Key_Bytes) return Database.Status.Result is
      Any_Nonzero : Boolean := False;
   begin
      if Bytes'Length /= 32 then
         return Database.Status.Failure (Database.Status.Invalid_Key,
           "binary encryption keys must be exactly 32 bytes");
      end if;
      for I in Bytes'Range loop
         if Bytes (I) /= 0 then
            Any_Nonzero := True;
         end if;
      end loop;
      if not Any_Nonzero then
         return Database.Status.Failure (Database.Status.Invalid_Key, "all-zero encryption key rejected");
      end if;
      return Database.Status.Success;
   end Validate_Format;

   function Byte_At (Key : Encryption_Key; Index : Natural) return Byte is
   begin
      return Key.Data (Index mod Key.Data'Length);
   end Byte_At;
end Database.Keys;
