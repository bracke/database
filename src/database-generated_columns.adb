with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
with Database.Values;
package body Database.Generated_Columns is
   function Create
     (Column_Id  : Natural;
      Name       : Wide_Wide_String;
      Expression : Database.Expressions.Expression;
      Kind       : Generated_Column_Kind := Stored) return Generated_Column is
   begin
      return  (Column_Id => Column_Id,
        Name => To_Unbounded_Wide_Wide_String (Name),
        Expression => Expression,
        Kind => Kind);
   end Create;

   function Validate_Definition (Column : Generated_Column) return Database.Status.Result is
   begin
      if Length (Column.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "generated column name must not be empty");
      elsif not Database.Expressions.Is_Deterministic (Column.Expression) then
         return Database.Status.Failure (Database.Status.Invalid_Schema,
           "generated column expression must be deterministic");
      elsif Database.Expressions.Depends_On_Column (Column.Expression, Column.Column_Id) then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "generated column may not depend on itself");
      else
         return Database.Status.Success;
      end if;
   end Validate_Definition;

   function Recompute_Stored
     (Columns : Generated_Column_Vectors.Vector;
      Schema  : Database.Schema.Table_Schema;
      Row     : in out Database.Rows.Row) return Database.Status.Result is
      R : Database.Status.Result;
      V : Database.Values.Value;
      Pos : Natural;
   begin
      for C of Columns loop
         R := Validate_Definition (C);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         if C.Kind = Stored then
            R := Database.Expressions.Evaluate  (C.Expression,
              Schema,
              Row,
              V);
              if not Database.Status.Is_Ok (R) then
                 return R;
              end if;
            Pos := Database.Schema.Find_Column_Id_Position (Schema, C.Column_Id);
            if Pos >= Database.Rows.Column_Count (Row) then
               return Database.Status.Failure (Database.Status.Invalid_Argument,
                 "generated column position out of range");
            end if;
            Database.Rows.Replace (Row, Pos, V);
         end if;
      end loop;
      return Database.Status.Success;
   end Recompute_Stored;

   function Validate_Stored
     (Columns : Generated_Column_Vectors.Vector;
      Schema  : Database.Schema.Table_Schema;
      Row     : Database.Rows.Row) return Database.Status.Result is
      R : Database.Status.Result;
      V, Existing : Database.Values.Value;
      Pos : Natural;
   begin
      for C of Columns loop
         if C.Kind = Stored then
            R := Database.Expressions.Evaluate  (C.Expression,
              Schema,
              Row,
              V);
              if not Database.Status.Is_Ok (R) then
                 return R;
              end if;
            Pos := Database.Schema.Find_Column_Id_Position (Schema, C.Column_Id);
            Existing := Database.Rows.Get (Row, Pos);
            if not Database.Values.Equal (V, Existing) then
               return Database.Status.Failure (Database.Status.Constraint_Error,
                 "generated column value is stale: " & To_Wide_Wide_String (C.Name));
            end if;
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_Stored;
end Database.Generated_Columns;
