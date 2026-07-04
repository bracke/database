with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Extension_Metadata is
   use Ada.Strings.Wide_Wide_Unbounded;

   function Same_Object
     (Left  : Extension_Object_Metadata;
      Right : Extension_Object_Metadata) return Boolean is
   begin
      return Left.Object_Kind = Right.Object_Kind
        and then To_Wide_Wide_String (Left.Object_Name) = To_Wide_Wide_String (Right.Object_Name);
   end Same_Object;

   function Dependency_For
     (Metadata : Extension_Object_Metadata) return Dependency is
      D : Dependency;
   begin
      D.Object_Name := Metadata.Object_Name;
      D.Object_Kind := Metadata.Object_Kind;
      D.Required_Version := Metadata.Version;
      D.Compatibility_Id := Metadata.Compatibility_Id;
      return D;
   end Dependency_For;
end Database.Extension_Metadata;
