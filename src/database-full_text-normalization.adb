with Ada.Strings.Wide_Wide_Unbounded;
package body Database.Full_Text.Normalization is
   function Default_Config return Normalization_Config is
   begin
      return
        (Case_Insensitive => True,
         Accents          => Preserve_Accents,
         Stemming         => No_Stemming);
   end Default_Config;

   function Lower (C : Wide_Wide_Character) return Wide_Wide_Character is
      P : constant Natural := Wide_Wide_Character'Pos (C);
   begin
      if C >= 'A' and then C <= 'Z' then
         return Wide_Wide_Character'Val (P + 32);
      elsif P in 16#00C0# .. 16#00D6# or else P in 16#00D8# .. 16#00DE# then
         return Wide_Wide_Character'Val (P + 32);
      else
         case P is
            when 16#0100# | 16#0102# | 16#0104# => return Wide_Wide_Character'Val (P + 1);
            when 16#0106# | 16#0108# | 16#010A# | 16#010C# => return Wide_Wide_Character'Val (P + 1);
            when 16#010E# | 16#0110# => return Wide_Wide_Character'Val (P + 1);
            when 16#0112# | 16#0114# | 16#0116# | 16#0118# | 16#011A# => return Wide_Wide_Character'Val (P + 1);
            when 16#011C# | 16#011E# | 16#0120# | 16#0122# => return Wide_Wide_Character'Val (P + 1);
            when 16#0124# | 16#0126# => return Wide_Wide_Character'Val (P + 1);
            when 16#0128# | 16#012A# | 16#012C# | 16#012E# | 16#0130# => return Wide_Wide_Character'Val (P + 1);
            when 16#0132# | 16#0134# => return Wide_Wide_Character'Val (P + 1);
            when 16#0136# | 16#0139# | 16#013B# | 16#013D# | 16#013F# => return Wide_Wide_Character'Val (P + 1);
            when 16#0141# | 16#0143# | 16#0145# | 16#0147# => return Wide_Wide_Character'Val (P + 1);
            when 16#014A# | 16#014C# | 16#014E# | 16#0150# => return Wide_Wide_Character'Val (P + 1);
            when 16#0152# | 16#0154# | 16#0156# | 16#0158# => return Wide_Wide_Character'Val (P + 1);
            when 16#015A# | 16#015C# | 16#015E# | 16#0160# => return Wide_Wide_Character'Val (P + 1);
            when 16#0162# | 16#0164# | 16#0166# => return Wide_Wide_Character'Val (P + 1);
            when 16#0168# | 16#016A# | 16#016C#
               | 16#016E# | 16#0170# | 16#0172# =>
               return Wide_Wide_Character'Val (P + 1);
            when 16#0174# | 16#0176# => return Wide_Wide_Character'Val (P + 1);
            when 16#0178# => return Wide_Wide_Character'Val (16#00FF#);
            when 16#0179# | 16#017B# | 16#017D# => return Wide_Wide_Character'Val (P + 1);
            when others => return C;
         end case;
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
         when 16#00E6# => return 'a';
         when 16#00F8# => return 'o';
         when 16#00FE# => return 't';
         when 16#00DF# => return 's';
         when 16#0101# | 16#0103# | 16#0105# => return 'a';
         when 16#0107# | 16#0109# | 16#010B# | 16#010D# => return 'c';
         when 16#010F# | 16#0111# => return 'd';
         when 16#0113# | 16#0115# | 16#0117# | 16#0119# | 16#011B# => return 'e';
         when 16#011D# | 16#011F# | 16#0121# | 16#0123# => return 'g';
         when 16#0125# | 16#0127# => return 'h';
         when 16#0129# | 16#012B# | 16#012D# | 16#012F# | 16#0131# => return 'i';
         when 16#0135# => return 'j';
         when 16#0137# => return 'k';
         when 16#013A# | 16#013C# | 16#013E# | 16#0140# | 16#0142# => return 'l';
         when 16#0144# | 16#0146# | 16#0148# | 16#014B# => return 'n';
         when 16#014D# | 16#014F# | 16#0151# => return 'o';
         when 16#0155# | 16#0157# | 16#0159# => return 'r';
         when 16#015B# | 16#015D# | 16#015F# | 16#0161# => return 's';
         when 16#0163# | 16#0165# | 16#0167# => return 't';
         when 16#0169# | 16#016B# | 16#016D# | 16#016F# | 16#0171# | 16#0173# => return 'u';
         when 16#0175# => return 'w';
         when 16#0177# => return 'y';
         when 16#017A# | 16#017C# | 16#017E# => return 'z';
         when others => return C;
      end case;
   end Strip;

   function Ends_With (Text, Suffix : Wide_Wide_String) return Boolean is
   begin
      return Suffix'Length <= Text'Length
        and then Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix;
   end Ends_With;

   function Stem_Simple_English (Text : Wide_Wide_String) return Wide_Wide_String is
      Last : Natural := Text'Last;
   begin
      if Text'Length <= 3 then
         return Text;
      end if;

      if Text'Length > 5 and then Ends_With (Text, "ies") then
         return Text (Text'First .. Text'Last - 3) & "y";
      elsif Text'Length > 5 and then Ends_With (Text, "ing") then
         Last := Text'Last - 3;
      elsif Text'Length > 4 and then Ends_With (Text, "ed") then
         Last := Text'Last - 2;
      elsif Text'Length > 5
        and then (Ends_With (Text, "sses")
                  or else Ends_With (Text, "ches")
                  or else Ends_With (Text, "shes")
                  or else Ends_With (Text, "xes")
                  or else Ends_With (Text, "zes"))
      then
         Last := Text'Last - 2;
      elsif Text'Length > 3 and then Ends_With (Text, "s") then
         Last := Text'Last - 1;
      end if;

      if Last < Text'First then
         return Text;
      end if;

      return Text (Text'First .. Last);
   end Stem_Simple_English;

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
      declare
         Normalized : constant Wide_Wide_String := To_Wide_Wide_String (R);
      begin
         case Config.Stemming is
            when No_Stemming =>
               return Normalized;
            when Simple_English_Stemming =>
               return Stem_Simple_English (Normalized);
         end case;
      end;
   end Normalize;
end Database.Full_Text.Normalization;
