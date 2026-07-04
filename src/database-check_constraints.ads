with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Expressions;
with Database.Rows;
with Database.Schema;
with Database.Status;

--  Check constraint metadata and validation.
package Database.Check_Constraints is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Check_Constraint stores the public fields for this database abstraction.
   type Check_Constraint is record
      Name       : Unbounded_Wide_Wide_String;
      Expression : Database.Expressions.Expression;
      Deferred   : Boolean := False;
   end record;

   --  Check_Constraint_Vectors stores ordered check constraint values for this package.
   package Check_Constraint_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Check_Constraint);

   --  Return create for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Expression expression argument supplied to the operation.
   --  @param Deferred deferred argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Name       : Wide_Wide_String;
      Expression : Database.Expressions.Expression;
      Deferred   : Boolean := False) return Check_Constraint;

   --  Return validate definition for the supplied database state or arguments.
   --  @param Constraint constraint argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Definition (Constraint : Check_Constraint) return Database.Status.Result;

   --  Return validate row for the supplied database state or arguments.
   --  @param Constraint constraint argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Row
     (Constraint : Check_Constraint;
      Schema     : Database.Schema.Table_Schema;
      Row        : Database.Rows.Row) return Database.Status.Result;

   --  Return validate all for the supplied database state or arguments.
   --  @param Constraints constraints argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @param Include_Deferred include deferred argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_All
     (Constraints : Check_Constraint_Vectors.Vector;
      Schema      : Database.Schema.Table_Schema;
      Row         : Database.Rows.Row;
      Include_Deferred : Boolean := False) return Database.Status.Result;
end Database.Check_Constraints;
