with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
with Database.Types;
package body Database.Foreign_Keys is
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;

   overriding function "=" (Left, Right : Foreign_Key_Definition) return Boolean is
   begin
      return Left.Name = Right.Name
        and then Left.Referencing_Table = Right.Referencing_Table
        and then Left.Referenced_Table = Right.Referenced_Table;
   end "=";
   function Create
     (Name              : Wide_Wide_String;
      Referencing_Table : Natural;
      Referenced_Table  : Natural;
      Referencing_Cols  : Column_Id_Vectors.Vector;
      Referenced_Cols   : Column_Id_Vectors.Vector;
      On_Delete         : Foreign_Key_Action := Restrict;
      On_Update         : Foreign_Key_Action := Restrict;
      Deferred          : Boolean := False) return Foreign_Key_Definition is
   begin
      return (Name => To_Unbounded_Wide_Wide_String (Name), Referencing_Table => Referencing_Table,
              Referenced_Table => Referenced_Table, Referencing_Cols => Referencing_Cols,
              Referenced_Cols => Referenced_Cols, On_Delete => On_Delete, On_Update => On_Update,
              Deferred => Deferred);
   end Create;

   function Validate_Definition
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Referenced_Schema  : Database.Schema.Table_Schema) return Database.Status.Result is
      Ref_Pos, Parent_Pos : Natural;
   begin
      if Length (Definition.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "foreign key name must not be empty");
      elsif Definition.Referencing_Cols.Length = 0
        or else Definition.Referencing_Cols.Length /= Definition.Referenced_Cols.Length then
         return Database.Status.Failure (Database.Status.Invalid_Schema,
           "foreign key column lists must be non-empty and same length");
      elsif Definition.Referencing_Table /= Referencing_Schema.Table_Id
        or else Definition.Referenced_Table /= Referenced_Schema.Table_Id then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "foreign key table ids do not match schemas");
      end if;
      for I in 0 .. Natural (Definition.Referencing_Cols.Length) - 1 loop
         Ref_Pos := Database.Schema.Find_Column_Id_Position  (Referencing_Schema,
           Definition.Referencing_Cols.Element (I));
         Parent_Pos := Database.Schema.Find_Column_Id_Position  (Referenced_Schema,
           Definition.Referenced_Cols.Element (I));
         if Ref_Pos >= Database.Schema.Column_Count (Referencing_Schema)
           or else Parent_Pos >= Database.Schema.Column_Count (Referenced_Schema) then
            return Database.Status.Failure (Database.Status.Invalid_Schema, "foreign key references unknown column");
         elsif Referencing_Schema.Columns.Element (Ref_Pos).Kind
           /= Referenced_Schema.Columns.Element (Parent_Pos).Kind then
            return Database.Status.Failure (Database.Status.Invalid_Schema, "foreign key column types must match");
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_Definition;

   function Referencing_Key_Is_Null
     (Definition : Foreign_Key_Definition;
      Schema     : Database.Schema.Table_Schema;
      Row        : Database.Rows.Row) return Boolean is
      Pos : Natural;
      V : Database.Values.Value;
   begin
      for C of Definition.Referencing_Cols loop
         Pos := Database.Schema.Find_Column_Id_Position (Schema, C);
         if Pos < Database.Rows.Column_Count (Row) then
            V := Database.Rows.Get (Row, Pos);
            if V.Kind = Database.Types.Null_Value then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Referencing_Key_Is_Null;

   function Rows_Match
     (Left_Schema  : Database.Schema.Table_Schema;
      Left_Row     : Database.Rows.Row;
      Left_Cols    : Column_Id_Vectors.Vector;
      Right_Schema : Database.Schema.Table_Schema;
      Right_Row    : Database.Rows.Row;
      Right_Cols   : Column_Id_Vectors.Vector) return Boolean is
      LP, RP : Natural;
   begin
      if Left_Cols.Length /= Right_Cols.Length then
         return False;
      end if;
      for I in 0 .. Natural (Left_Cols.Length) - 1 loop
         LP := Database.Schema.Find_Column_Id_Position (Left_Schema, Left_Cols.Element (I));
         RP := Database.Schema.Find_Column_Id_Position (Right_Schema, Right_Cols.Element (I));
         if LP >= Database.Rows.Column_Count (Left_Row) or else RP >= Database.Rows.Column_Count (Right_Row) then
            return False;
         elsif not Database.Values.Equal (Database.Rows.Get (Left_Row, LP), Database.Rows.Get (Right_Row, RP)) then
            return False;
         end if;
      end loop;
      return True;
   end Rows_Match;

   function Validate_Insert_Or_Update
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Referenced_Schema  : Database.Schema.Table_Schema;
      Referencing_Row    : Database.Rows.Row;
      Referenced_Rows    : Row_Vectors.Vector) return Database.Status.Result is
   begin
      if Referencing_Key_Is_Null (Definition, Referencing_Schema, Referencing_Row) then
         return Database.Status.Success;
      end if;
      for Parent of Referenced_Rows loop
         if Rows_Match (Referencing_Schema, Referencing_Row, Definition.Referencing_Cols,
                        Referenced_Schema, Parent, Definition.Referenced_Cols) then
            return Database.Status.Success;
         end if;
      end loop;
      return Database.Status.Failure (Database.Status.Constraint_Error, "foreign key referenced row not found: "
        & To_Wide_Wide_String (Definition.Name));
   end Validate_Insert_Or_Update;

   function Validate_Referenced_Delete
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Referenced_Schema  : Database.Schema.Table_Schema;
      Referenced_Row     : Database.Rows.Row;
      Referencing_Rows   : Row_Vectors.Vector) return Database.Status.Result is
   begin
      if Definition.On_Delete /= Restrict then
         return Database.Status.Success;
      end if;
      for Child of Referencing_Rows loop
         if Rows_Match (Referencing_Schema, Child, Definition.Referencing_Cols,
                        Referenced_Schema, Referenced_Row, Definition.Referenced_Cols) then
            return Database.Status.Failure (Database.Status.Constraint_Error,
              "foreign key restrict delete failed: " & To_Wide_Wide_String (Definition.Name));
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_Referenced_Delete;

   procedure Apply_Set_Null
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Row                : in out Database.Rows.Row) is
      Pos : Natural;
   begin
      for C of Definition.Referencing_Cols loop
         Pos := Database.Schema.Find_Column_Id_Position (Referencing_Schema, C);
         if Pos < Database.Rows.Column_Count (Row) then
            Database.Rows.Replace (Row, Pos, Database.Values.Null_Value);
         end if;
      end loop;
   end Apply_Set_Null;
end Database.Foreign_Keys;
