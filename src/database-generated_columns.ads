with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Expressions;
with Database.Rows;
with Database.Schema;
with Database.Status;

--  Generated column metadata and evaluation support.
package Database.Generated_Columns is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Generated_Column_Kind enumerates the supported values for this database abstraction.
   type Generated_Column_Kind is (Stored, Virtual);

   --  Generated_Column stores the public fields for this database abstraction.
   type Generated_Column is record
      Column_Id  : Natural := 0;
      Name       : Unbounded_Wide_Wide_String;
      Expression : Database.Expressions.Expression;
      Kind       : Generated_Column_Kind := Stored;
   end record;

   --  Generated_Column_Vectors stores ordered generated column values for this package.
   package Generated_Column_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Generated_Column);

   --  Return create for the supplied database state or arguments.
   --  @param Column_Id column id argument supplied to the operation.
   --  @param Name logical name of the object.
   --  @param Expression expression argument supplied to the operation.
   --  @param Kind kind selector controlling the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Column_Id  : Natural;
      Name       : Wide_Wide_String;
      Expression : Database.Expressions.Expression;
      Kind       : Generated_Column_Kind := Stored) return Generated_Column;

   --  Return validate definition for the supplied database state or arguments.
   --  @param Column column argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Definition (Column : Generated_Column) return Database.Status.Result;

   --  Return recompute stored for the supplied database state or arguments.
   --  @param Columns columns argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Recompute_Stored
     (Columns : Generated_Column_Vectors.Vector;
      Schema  : Database.Schema.Table_Schema;
      Row     : in out Database.Rows.Row) return Database.Status.Result;

   --  Return validate stored for the supplied database state or arguments.
   --  @param Columns columns argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Stored
     (Columns : Generated_Column_Vectors.Vector;
      Schema  : Database.Schema.Table_Schema;
      Row     : Database.Rows.Row) return Database.Status.Result;
end Database.Generated_Columns;
