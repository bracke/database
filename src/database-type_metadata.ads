--  Rich logical type metadata validation for schemas and catalog persistence.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;
with Database.Types;

--  Richer type metadata descriptors.
package Database.Type_Metadata is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Enum_Literal stores the public fields for this database abstraction.
   type Enum_Literal is record
      Name    : Unbounded_Wide_Wide_String;
      Ordinal : Natural := 0;
   end record;

   --  Enum_Literal_Vectors stores ordered enum literal values for this package.
   package Enum_Literal_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Enum_Literal);

   --  Enum_Descriptor stores the public fields for this database abstraction.
   type Enum_Descriptor is record
      Name    : Unbounded_Wide_Wide_String;
      Literals : Enum_Literal_Vectors.Vector;
      Representation : Database.Types.Enum_Representation := Database.Types.Enum_By_Name;
   end record;

   --  Return validate type for the supplied database state or arguments.
   --  @param Descriptor descriptor argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Type (Descriptor : Database.Types.Type_Descriptor) return Database.Status.Result;
   --  Return validate enum for the supplied database state or arguments.
   --  @param Descriptor descriptor argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Enum (Descriptor : Enum_Descriptor) return Database.Status.Result;
   --  Return contains literal for the supplied database state or arguments.
   --  @param Descriptor descriptor argument supplied to the operation.
   --  @param Literal literal argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Contains_Literal (Descriptor : Enum_Descriptor; Literal : Wide_Wide_String) return Boolean;
end Database.Type_Metadata;
