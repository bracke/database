with Interfaces;

package body Database.Crypto is
   use type Interfaces.Unsigned_64;
   use type Database.Storage.Pages.Byte;

   procedure Absorb (S : in out Interfaces.Unsigned_64; B : Byte) is
   begin
      S := S xor Interfaces.Unsigned_64 (B);
      S := S * 16#0000_0100_0000_01B3#;
      S := S xor Interfaces.Shift_Right (S, 29);
   end Absorb;

   function Generate_Nonce
     (Object_Id : Natural;
      LSN       : Database.Log_Sequence.Log_Sequence_Number) return Nonce
   is
      N : Nonce := (others => 0);
      X : Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Object_Id) * 16#9E37_79B9_7F4A_7C15#
        + Interfaces.Unsigned_64 (LSN);
   begin
      for I in N'Range loop
         X := X xor Interfaces.Shift_Left (X, 7);
         X := X xor Interfaces.Shift_Right (X, 9);
         X := X * 16#D6E8_FD93_1356_57AF# + Interfaces.Unsigned_64 (I + 1);
         N (I) := Byte (Natural (X and 16#FF#));
      end loop;
      return N;
   end Generate_Nonce;

   function Compute_MAC
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Ciphertext      : Byte_Array) return Authentication_Tag
   is
      S : Interfaces.Unsigned_64 := 16#CBF2_9CE4_8422_2325#;
      T : Authentication_Tag := (others => 0);
   begin
      for I in 0 .. 31 loop
         Absorb (S, Database.Keys.Byte_At (Key, I));
      end loop;
      for I in Nonce_Value'Range loop
         Absorb (S, Nonce_Value (I));
      end loop;
      for I in Associated_Data'Range loop
         Absorb (S, Associated_Data (I));
      end loop;
      for I in Ciphertext'Range loop
         Absorb (S, Ciphertext (I));
      end loop;
      for I in T'Range loop
         Absorb (S, Byte (I));
         T (I) := Byte (Natural (Interfaces.Shift_Right (S, (I mod 8) * 8) and 16#FF#));
      end loop;
      return T;
   end Compute_MAC;

   function Encrypt
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Plaintext       : Byte_Array;
      Ciphertext      : out Byte_Array;
      Tag             : out Authentication_Tag) return Database.Status.Result
   is
      S : Interfaces.Unsigned_64 := 16#243F_6A88_85A3_08D3#;
      K : Byte;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encryption key is not valid");
      end if;
      if Ciphertext'Length /= Plaintext'Length then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "ciphertext buffer has wrong length");
      end if;
      for I in Nonce_Value'Range loop
         Absorb (S, Nonce_Value (I));
      end loop;
      for I in Associated_Data'Range loop
         Absorb (S, Associated_Data (I));
      end loop;
      for I in Plaintext'Range loop
         Absorb (S, Database.Keys.Byte_At (Key, I));
         K := Byte (Natural ((S xor Interfaces.Shift_Right (S, 23)) and 16#FF#));
         Ciphertext (Ciphertext'First + (I - Plaintext'First)) := Plaintext (I) xor K;
         Absorb (S, Ciphertext (Ciphertext'First + (I - Plaintext'First)));
      end loop;
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
      Expected : constant Authentication_Tag := Compute_MAC (Key, Nonce_Value, Associated_Data, Ciphertext);
      S : Interfaces.Unsigned_64 := 16#243F_6A88_85A3_08D3#;
      K : Byte;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encryption key is not valid");
      end if;
      if Plaintext'Length /= Ciphertext'Length then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "plaintext buffer has wrong length");
      end if;
      if Expected /= Tag then
         return Database.Status.Failure (Database.Status.Authentication_Failure, "ciphertext authentication failed");
      end if;
      for I in Nonce_Value'Range loop
         Absorb (S, Nonce_Value (I));
      end loop;
      for I in Associated_Data'Range loop
         Absorb (S, Associated_Data (I));
      end loop;
      for I in Ciphertext'Range loop
         Absorb (S, Database.Keys.Byte_At (Key, I));
         K := Byte (Natural ((S xor Interfaces.Shift_Right (S, 23)) and 16#FF#));
         Plaintext (Plaintext'First + (I - Ciphertext'First)) := Ciphertext (I) xor K;
         Absorb (S, Ciphertext (I));
      end loop;
      return Database.Status.Success;
   end Decrypt;

   procedure Clear (Data : in out Byte_Array) is
   begin
      Data := (others => 0);
   end Clear;
end Database.Crypto;
