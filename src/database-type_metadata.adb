with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
package body Database.Type_Metadata is
   use type Ada.Containers.Count_Type;
   function Validate_Type (Descriptor : Database.Types.Type_Descriptor) return Database.Status.Result is
      use type Database.Types.Value_Kind;
   begin
      if Descriptor.Serialization_Version /= 1 then
         return Database.Status.Failure (Database.Status.Unsupported_Type_Version, "unsupported type metadata version");
      end if;
      if Descriptor.Kind = Database.Types.Decimal_Value
        and then Descriptor.Precision > 0
        and then Descriptor.Scale > Descriptor.Precision
      then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "decimal scale exceeds precision");
      end if;
      if Descriptor.Kind = Database.Types.Array_Value and then Descriptor.Element_Kind = Database.Types.Null_Value then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "array metadata requires an element type");
      end if;
      return Database.Status.Success;
   end Validate_Type;

   function Validate_Enum (Descriptor : Enum_Descriptor) return Database.Status.Result is
   begin
      if Length (Descriptor.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "enum descriptor requires a name");
      end if;
      if Descriptor.Literals.Length = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "enum descriptor requires literals");
      end if;
      for I in 0 .. Natural (Descriptor.Literals.Length) - 1 loop
         if Length (Descriptor.Literals.Element (I).Name) = 0 then
            return Database.Status.Failure (Database.Status.Invalid_Enum_Value, "empty enum literal");
         end if;
         for J in I + 1 .. Natural (Descriptor.Literals.Length) - 1 loop
            if To_Wide_Wide_String (Descriptor.Literals.Element (I).Name)
              = To_Wide_Wide_String (Descriptor.Literals.Element (J).Name)
            then
               return Database.Status.Failure (Database.Status.Invalid_Enum_Value, "duplicate enum literal");
            end if;
         end loop;
      end loop;
      return Database.Status.Success;
   end Validate_Enum;

   function Contains_Literal (Descriptor : Enum_Descriptor; Literal : Wide_Wide_String) return Boolean is
   begin
      for L of Descriptor.Literals loop
         if To_Wide_Wide_String (L.Name) = Literal then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Literal;
end Database.Type_Metadata;
