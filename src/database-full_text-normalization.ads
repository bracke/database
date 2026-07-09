--  Conservative Unicode normalization for full-text matching.
with Ada.Strings.Wide_Wide_Unbounded;

--  Public specification for this database subsystem.
package Database.Full_Text.Normalization is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Accent_Mode enumerates the supported values for this database abstraction.
   type Accent_Mode is (Preserve_Accents, Strip_Basic_Latin_Accents);
   --  Stem_Mode controls optional conservative stemming after case/accent
   --  normalization. Stemming is disabled by default to preserve exact term
   --  behavior unless callers opt in.
   type Stem_Mode is (No_Stemming, Simple_English_Stemming);
   --  Normalization_Config stores the public fields for this database abstraction.
   type Normalization_Config is record
      Case_Insensitive : Boolean := True;
      Accents          : Accent_Mode := Preserve_Accents;
      Stemming         : Stem_Mode := No_Stemming;
   end record;

   --  Return default config for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Default_Config return Normalization_Config;
   --  Return normalize for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @param Config configuration values controlling the operation.
   --  @return Result produced by the function.
   function Normalize
     (Text   : Wide_Wide_String;
      Config : Normalization_Config := Default_Config) return Wide_Wide_String;
end Database.Full_Text.Normalization;
