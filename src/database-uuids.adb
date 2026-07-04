with Ada.Calendar;
with Ada.Numerics.Discrete_Random;
package body Database.UUIDs is
   package Random_Byte is new Ada.Numerics.Discrete_Random (Byte);
   Gen : Random_Byte.Generator;
   Seeded : Boolean := False;

   function Nil_UUID return UUID is
   begin
      return (others => 0);
   end Nil_UUID;

   function Generate_UUID return UUID is
      U : UUID;
   begin
      if not Seeded then
         Random_Byte.Reset (Gen, Integer (Ada.Calendar.Seconds (Ada.Calendar.Clock) * 1000.0));
         Seeded := True;
      end if;
      for I in U'Range loop
         U (I) := Random_Byte.Random (Gen);
      end loop;
      U (6) := (U (6) mod 16) + 16#40#;
      U (8) := (U (8) mod 64) + 16#80#;
      return U;
   end Generate_UUID;

   function Hex_Val (C : Wide_Wide_Character) return Integer is
   begin
      if C in '0' .. '9' then
         return Wide_Wide_Character'Pos (C) - Wide_Wide_Character'Pos ('0');
      end if;
      if C in 'a' .. 'f' then
         return 10 + Wide_Wide_Character'Pos (C) - Wide_Wide_Character'Pos ('a');
      end if;
      if C in 'A' .. 'F' then
         return 10 + Wide_Wide_Character'Pos (C) - Wide_Wide_Character'Pos ('A');
      end if;
      return -1;
   end Hex_Val;

   function Parse_UUID (Text : Wide_Wide_String; Value : out UUID) return Database.Status.Result is
      Clean : Wide_Wide_String (1 .. 32);
      P : Natural := 0;
   begin
      Value := Nil_UUID;
      if Text'Length /= 36 then
         return Database.Status.Failure (Database.Status.Invalid_UUID, "UUID must have canonical 36-character form");
      end if;
      for I in Text'Range loop
         if I in Text'First + 8 | Text'First + 13 | Text'First + 18 | Text'First + 23 then
            if Text (I) /= '-' then
               return Database.Status.Failure (Database.Status.Invalid_UUID, "UUID hyphen misplaced");
            end if;
         else
            P := P + 1;
            if P > 32 or else Hex_Val (Text (I)) < 0 then
               return Database.Status.Failure (Database.Status.Invalid_UUID, "UUID contains non-hex digit");
            end if;
            Clean (P) := Text (I);
         end if;
      end loop;
      for I in 0 .. 15 loop
         Value (I) := Byte (Hex_Val (Clean (I * 2 + 1)) * 16 + Hex_Val (Clean (I * 2 + 2)));
      end loop;
      return Database.Status.Success;
   end Parse_UUID;

   function Hex_Char (N : Byte) return Wide_Wide_Character is
      Hex_Digits : constant Wide_Wide_String := "0123456789abcdef";
   begin
      return Hex_Digits (Natural (N) + 1);
   end Hex_Char;

   function UUID_To_String (Value : UUID) return Wide_Wide_String is
      S : Wide_Wide_String (1 .. 36);
      P : Natural := 1;
   begin
      for I in Value'Range loop
         if I in 4 | 6 | 8 | 10 then
            S (P) := '-';
            P := P + 1;
         end if;
         S (P) := Hex_Char (Byte (Value (I) / 16));
         P := P + 1;
         S (P) := Hex_Char (Byte (Value (I) mod 16));
         P := P + 1;
      end loop;
      return S;
   end UUID_To_String;

   function Compare (Left, Right : UUID) return Integer is
   begin
      for I in UUID'Range loop
         if Left (I) < Right (I) then
            return -1;
         end if;
         if Left (I) > Right (I) then
            return 1;
         end if;
      end loop;
      return 0;
   end Compare;
end Database.UUIDs;
