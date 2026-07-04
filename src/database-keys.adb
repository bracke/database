with Interfaces;

package body Database.Keys is
   use Database.Storage.Pages;
   use type Interfaces.Unsigned_32;

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

   procedure Mix (State : in out Interfaces.Unsigned_32; B : Byte) is
   begin
      State := State xor Interfaces.Unsigned_32 (B);
      State := State * 16#0100_0193#;
      State := State xor Interfaces.Shift_Right (State, 13);
      State := State * 16#85EB_CA6B#;
   end Mix;

   function Derive_Key
     (Passphrase : Wide_Wide_String;
      Salt       : Salt_Type) return Encryption_Key
   is
      State : Interfaces.Unsigned_32 := 16#811C_9DC5#;
      Data  : Binary_Key := (others => 0);
      C     : Wide_Wide_Character;
      V     : Natural;
   begin
      for I in Salt'Range loop
         Mix (State, Salt (I));
      end loop;
      for Round in 1 .. 4096 loop
         for I in Passphrase'Range loop
            C := Passphrase (I);
            V := Wide_Wide_Character'Pos (C);
            Mix (State, Byte (V mod 256));
            Mix (State, Byte ((V / 256) mod 256));
            Mix (State, Byte ((V / 65536) mod 256));
            Mix (State, Byte (Round mod 256));
         end loop;
         for I in Salt'Range loop
            Mix (State, Byte ((Natural (Salt (I)) + Round + I) mod 256));
         end loop;
      end loop;
      for I in Data'Range loop
         Mix (State, Byte ((I * 17 + 91) mod 256));
         Data (I) := Byte (Natural (State and 16#FF#));
      end loop;
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
