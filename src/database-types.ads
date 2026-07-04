--  Database value type descriptors, exact decimal values, and logical type metadata.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Date_Time;
with Database.UUIDs;

--  Core logical type definitions for schemas, values, and serialized fields.
package Database.Types is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Value_Kind defines a public database type used by this package.
   type Value_Kind is
     (Null_Value,
      Boolean_Value,
      Integer_Value,
      Long_Integer_Value,
      Float_Value,
      Decimal_Value,
      Text_Value,
      Blob_Value,
      Timestamp_Value,
      Enum_Value,
      Date_Value,
      Time_Value,
      Date_Time_Value,
      Duration_Value,
      UUID_Value,
      Array_Value);

   --  Decimal stores the public fields for this database abstraction.
   type Decimal is record
      Coefficient : Long_Long_Integer := 0;
      Scale       : Natural := 0;
   end record;

   --  Timestamp stores the public fields for this database abstraction.
   type Timestamp is record
      Year        : Integer range 1 .. 9999 := 1970;
      Month       : Integer range 1 .. 12 := 1;
      Day         : Integer range 1 .. 31 := 1;
      Hour        : Integer range 0 .. 23 := 0;
      Minute      : Integer range 0 .. 59 := 0;
      Second      : Integer range 0 .. 59 := 0;
      Nanosecond  : Natural range 0 .. 999_999_999 := 0;
   end record;

   --  Enum_Representation enumerates the supported values for this database abstraction.
   type Enum_Representation is (Enum_By_Name, Enum_By_Ordinal);

   --  Type_Descriptor stores the public fields for this database abstraction.
   type Type_Descriptor is record
      Kind                 : Value_Kind := Null_Value;
      Serialization_Version : Natural := 1;
      Precision            : Natural := 0;
      Scale                : Natural := 0;
      Maximum_Length       : Natural := 0;
      Enum_Name            : Unbounded_Wide_Wide_String;
      Enum_Rep             : Enum_Representation := Enum_By_Name;
      Element_Kind         : Value_Kind := Null_Value;
      Collation_Name       : Unbounded_Wide_Wide_String;
   end record;

   --  Return describe for the supplied database state or arguments.
   --  @param Kind kind selector controlling the operation.
   --  @return Result produced by the function.
   function Describe (Kind : Value_Kind) return Type_Descriptor is
     ((Kind => Kind, others => <>));

   --  Return decimal descriptor for the supplied database state or arguments.
   --  @param Precision precision argument supplied to the operation.
   --  @param Scale scale argument supplied to the operation.
   --  @return Result produced by the function.
   function Decimal_Descriptor (Precision, Scale : Natural) return Type_Descriptor;
   --  Return bounded text descriptor for the supplied database state or arguments.
   --  @param Maximum_Length maximum length argument supplied to the operation.
   --  @param Collation_Name collation name argument supplied to the operation.
   --  @return Result produced by the function.
   function Bounded_Text_Descriptor
     (Maximum_Length : Natural;
      Collation_Name : Wide_Wide_String := "") return Type_Descriptor;
   --  Return enum descriptor for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Representation representation argument supplied to the operation.
   --  @return Result produced by the function.
   function Enum_Descriptor
     (Name : Wide_Wide_String;
      Representation : Enum_Representation := Enum_By_Name) return Type_Descriptor;
   --  Return array descriptor for the supplied database state or arguments.
   --  @param Element_Kind element kind argument supplied to the operation.
   --  @return Result produced by the function.
   function Array_Descriptor (Element_Kind : Value_Kind) return Type_Descriptor;
end Database.Types;
