with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;

package body Database.Types is

   function Decimal_Descriptor
     (Precision, Scale : Natural) return Type_Descriptor is
   begin
      return
        (Kind                  => Decimal_Value,
         Serialization_Version => 1,
         Precision             => Precision,
         Scale                 => Scale,
         Maximum_Length        => 0,
         Enum_Name             => Null_Unbounded_Wide_Wide_String,
         Enum_Rep              => Enum_By_Name,
         Element_Kind          => Null_Value,
         Collation_Name        => Null_Unbounded_Wide_Wide_String);
   end Decimal_Descriptor;

   function Bounded_Text_Descriptor
     (Maximum_Length : Natural;
      Collation_Name : Wide_Wide_String := "") return Type_Descriptor is
   begin
      return
        (Kind                  => Text_Value,
         Serialization_Version => 1,
         Precision             => 0,
         Scale                 => 0,
         Maximum_Length        => Maximum_Length,
         Enum_Name             => Null_Unbounded_Wide_Wide_String,
         Enum_Rep              => Enum_By_Name,
         Element_Kind          => Null_Value,
         Collation_Name        => To_Unbounded_Wide_Wide_String (Collation_Name));
   end Bounded_Text_Descriptor;

   function Enum_Descriptor
     (Name           : Wide_Wide_String;
      Representation : Enum_Representation := Enum_By_Name)
      return Type_Descriptor is
   begin
      return
        (Kind                  => Enum_Value,
         Serialization_Version => 1,
         Precision             => 0,
         Scale                 => 0,
         Maximum_Length        => 0,
         Enum_Name             => To_Unbounded_Wide_Wide_String (Name),
         Enum_Rep              => Representation,
         Element_Kind          => Null_Value,
         Collation_Name        => Null_Unbounded_Wide_Wide_String);
   end Enum_Descriptor;

   function Array_Descriptor
     (Element_Kind : Value_Kind) return Type_Descriptor is
   begin
      return
        (Kind                  => Array_Value,
         Serialization_Version => 1,
         Precision             => 0,
         Scale                 => 0,
         Maximum_Length        => 0,
         Enum_Name             => Null_Unbounded_Wide_Wide_String,
         Enum_Rep              => Enum_By_Name,
         Element_Kind          => Element_Kind,
         Collation_Name        => Null_Unbounded_Wide_Wide_String);
   end Array_Descriptor;

end Database.Types;
