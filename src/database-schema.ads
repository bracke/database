--  Table schema metadata with stable table ids, schema versions, and column ids.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Types;
with Database.Indexes;

   --  Public nested package `Database.Schema`.
package Database.Schema is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Public type `Column`.
   type Column is record
      Id          : Natural := 0;
      Name        : Unbounded_Wide_Wide_String;
      Kind        : Database.Types.Value_Kind := Database.Types.Null_Value;
      Nullable    : Boolean := True;
      Primary_Key : Boolean := False;
      Type_Info   : Database.Types.Type_Descriptor;
   end record;

   --  Public nested package `Column_Vectors`.
   package Column_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Column);

   --  Public type `Table_Schema`.
   type Table_Schema is record
      Table_Id           : Natural := 0;
      Schema_Version     : Natural := 1;
      Next_Column_Id     : Natural := 0;
      Name               : Unbounded_Wide_Wide_String;
      Columns            : Column_Vectors.Vector;
      Heap_First_Page    : Natural := 0;
      Primary_Index_Root : Natural := 0;
      Indexes            : Database.Indexes.Index_Metadata_Vectors.Vector;
      Primary_Key_Columns : Database.Indexes.Column_Id_Vectors.Vector;
   end record;

   --  Public operation `Add_Column`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param S s argument supplied to the operation.
   --  @param Name logical name of the object.
   --  @param Kind kind selector controlling the operation.
   --  @param Nullable nullable argument supplied to the operation.
   --  @param Primary_Key primary key argument supplied to the operation.
   procedure Add_Column
     (S           : in out Table_Schema;
      Name        : Wide_Wide_String;
      Kind        : Database.Types.Value_Kind;
      Nullable    : Boolean := True;
      Primary_Key : Boolean := False);

   --  Public operation `Column_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param S s argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Column_Count (S : Table_Schema) return Natural;
   --  Public operation `Primary_Key_Index`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param S s argument supplied to the operation.
   --  @return Result produced by the function.
   function Primary_Key_Index (S : Table_Schema) return Natural;
   --  Return primary key column count for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Primary_Key_Column_Count (S : Table_Schema) return Natural;
   --  Return is primary key column for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @param Column_Id column id argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Primary_Key_Column (S : Table_Schema; Column_Id : Natural) return Boolean;
   --  Public operation `Contains_Column_Name`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param S s argument supplied to the operation.
   --  @param Name logical name of the object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Contains_Column_Name (S : Table_Schema; Name : Wide_Wide_String) return Boolean;
   --  Public operation `Find_Column_Position`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param S s argument supplied to the operation.
   --  @param Name logical name of the object.
   --  @return Requested value or optional value according to the package contract.
   function Find_Column_Position (S : Table_Schema; Name : Wide_Wide_String) return Natural;
   --  Public operation `Find_Column_Id_Position`. See the package documentation for transaction, ownership, and
   --  error-result semantics.
   --  @param S s argument supplied to the operation.
   --  @param Column_Id column id argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Find_Column_Id_Position (S : Table_Schema; Column_Id : Natural) return Natural;
   --  Public operation `Next_Id`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param S s argument supplied to the operation.
   --  @return Result produced by the function.
   function Next_Id (S : Table_Schema) return Natural;
end Database.Schema;
