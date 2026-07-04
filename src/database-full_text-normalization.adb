with Ada.Strings.Wide_Wide_Unbounded;
package body Database.Full_Text.Normalization is
   function Default_Config return Normalization_Config is
   begin
      return (Case_Insensitive => True, Accents => Preserve_Accents);
   end Default_Config;

   function Lower (C : Wide_Wide_Character) return Wide_Wide_Character is
      P : constant Natural := Wide_Wide_Character'Pos (C);
   begin
      if C >= 'A' and then C <= 'Z' then
         return Wide_Wide_Character'Val (P + 32);
      elsif P in 16#00C0# .. 16#00D6# or else P in 16#00D8# .. 16#00DE# then
         return Wide_Wide_Character'Val (P + 32);
      else
         return C;
      end if;
   end Lower;

   function Strip (C : Wide_Wide_Character) return Wide_Wide_Character is
   begin
      case Wide_Wide_Character'Pos (C) is
         when 16#00E0# | 16#00E1# | 16#00E2# | 16#00E3# | 16#00E4# | 16#00E5# => return 'a';
         when 16#00E7# => return 'c';
         when 16#00E8# | 16#00E9# | 16#00EA# | 16#00EB# => return 'e';
         when 16#00EC# | 16#00ED# | 16#00EE# | 16#00EF# => return 'i';
         when 16#00F1# => return 'n';
         when 16#00F2# | 16#00F3# | 16#00F4# | 16#00F5# | 16#00F6# => return 'o';
         when 16#00F9# | 16#00FA# | 16#00FB# | 16#00FC# => return 'u';
         when 16#00FD# | 16#00FF# => return 'y';
         when others => return C;
      end case;
   end Strip;

   function Normalize
     (Text   : Wide_Wide_String;
      Config : Normalization_Config := Default_Config) return Wide_Wide_String is
      R : Unbounded_Wide_Wide_String;
      C : Wide_Wide_Character;
   begin
      for Ch of Text loop
         C := Ch;
         if Config.Case_Insensitive then
            C := Lower (C);
         end if;
         if Config.Accents = Strip_Basic_Latin_Accents then
            C := Strip (C);
         end if;
         Append (R, C);
      end loop;
      return To_Wide_Wide_String (R);
   end Normalize;
end Database.Full_Text.Normalization;
