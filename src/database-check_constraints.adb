with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
package body Database.Check_Constraints is
   function Create
     (Name       : Wide_Wide_String;
      Expression : Database.Expressions.Expression;
      Deferred   : Boolean := False) return Check_Constraint is
   begin
      return (Name => To_Unbounded_Wide_Wide_String (Name), Expression => Expression, Deferred => Deferred);
   end Create;

   function Validate_Definition (Constraint : Check_Constraint) return Database.Status.Result is
   begin
      if Length (Constraint.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "check constraint name must not be empty");
      elsif not Database.Expressions.Is_Deterministic (Constraint.Expression) then
         return Database.Status.Failure (Database.Status.Invalid_Schema,
           "check constraint expression must be deterministic");
      else
         return Database.Status.Success;
      end if;
   end Validate_Definition;

   function Validate_Row
     (Constraint : Check_Constraint;
      Schema     : Database.Schema.Table_Schema;
      Row        : Database.Rows.Row) return Database.Status.Result is
      Passes : Boolean := False;
      R : Database.Status.Result;
   begin
      R := Validate_Definition (Constraint);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Expressions.Evaluate_Boolean (Constraint.Expression, Schema, Row, Passes);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if not Passes then
         return Database.Status.Failure (Database.Status.Constraint_Error, "check constraint failed: "
           & To_Wide_Wide_String (Constraint.Name));
      end if;
      return Database.Status.Success;
   end Validate_Row;

   function Validate_All
     (Constraints : Check_Constraint_Vectors.Vector;
      Schema      : Database.Schema.Table_Schema;
      Row         : Database.Rows.Row;
      Include_Deferred : Boolean := False) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      for C of Constraints loop
         if Include_Deferred or else not C.Deferred then
            R := Validate_Row (C, Schema, Row);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_All;
end Database.Check_Constraints;
