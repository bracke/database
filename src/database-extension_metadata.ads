--  Metadata shared by Ada-native extension registries and persistent dependency checks.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;

--  Durable extension dependency metadata.
package Database.Extension_Metadata is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Extension_Object_Kind defines a public database type used by this package.
   type Extension_Object_Kind is
     (Scalar_Function_Object,
      Aggregate_Function_Object,
      Collation_Object,
      Tokenizer_Object,
      Ranking_Function_Object,
      Validation_Hook_Object,
      Generated_Function_Object);

   --  Determinism_Level enumerates the supported values for this database abstraction.
   type Determinism_Level is (Non_Deterministic, Stable_For_Statement, Deterministic);

   --  Extension_Object_Metadata stores the public fields for this database abstraction.
   type Extension_Object_Metadata is record
      Extension_Name    : Unbounded_Wide_Wide_String;
      Object_Name       : Unbounded_Wide_Wide_String;
      Object_Kind       : Extension_Object_Kind := Scalar_Function_Object;
      Version           : Natural := 1;
      Compatibility_Id  : Unbounded_Wide_Wide_String;
      Determinism       : Determinism_Level := Deterministic;
      Nullable_Result   : Boolean := True;
      Argument_Count    : Natural := 0;
      Index_Compatible  : Boolean := False;
      Monotonic         : Boolean := False;
      Estimated_Cost    : Natural := 1;
   end record;

   --  Metadata_Vectors stores ordered metadata values for this package.
   package Metadata_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Extension_Object_Metadata);

   --  Dependency stores the public fields for this database abstraction.
   type Dependency is record
      Object_Name      : Unbounded_Wide_Wide_String;
      Object_Kind      : Extension_Object_Kind := Scalar_Function_Object;
      Required_Version : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
   end record;

   --  Dependency_Vectors stores ordered dependency values for this package.
   package Dependency_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Dependency);

   --  Return same object for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Same_Object
     (Left  : Extension_Object_Metadata;
      Right : Extension_Object_Metadata) return Boolean;

   --  Return dependency for for the supplied database state or arguments.
   --  @param Metadata metadata argument supplied to the operation.
   --  @return Result produced by the function.
   function Dependency_For
     (Metadata : Extension_Object_Metadata) return Dependency;
end Database.Extension_Metadata;
