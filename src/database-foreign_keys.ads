with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Rows;
use Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Values;

--  Foreign-key metadata and enforcement.
package Database.Foreign_Keys is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Column_Id_Vectors stores ordered column id values for this package.
   package Column_Id_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Natural);
   --  Row_Vectors stores ordered row values for this package.
   package Row_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Database.Rows.Row);

   --  Foreign_Key_Action enumerates the supported values for this database abstraction.
   type Foreign_Key_Action is (Restrict, Cascade, Set_Null);

   --  Foreign_Key_Definition stores the public fields for this database abstraction.
   type Foreign_Key_Definition is record
      Name              : Unbounded_Wide_Wide_String;
      Referencing_Table : Natural := 0;
      Referenced_Table  : Natural := 0;
      Referencing_Cols  : Column_Id_Vectors.Vector;
      Referenced_Cols   : Column_Id_Vectors.Vector;
      On_Delete         : Foreign_Key_Action := Restrict;
      On_Update         : Foreign_Key_Action := Restrict;
      Deferred          : Boolean := False;
   end record;

   --  Compares two foreign-key definitions for equality.
   --  @param Left Left foreign-key definition operand.
   --  @param Right Right foreign-key definition operand.
   --  @return True when both definitions contain the same metadata and actions.
   overriding function "=" (Left, Right : Foreign_Key_Definition) return Boolean;

   --  Foreign_Key_Vectors stores ordered foreign key values for this package.
   package Foreign_Key_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Foreign_Key_Definition);

   --  Return create for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Referencing_Table referencing table argument supplied to the operation.
   --  @param Referenced_Table referenced table argument supplied to the operation.
   --  @param Referencing_Cols referencing cols argument supplied to the operation.
   --  @param Referenced_Cols referenced cols argument supplied to the operation.
   --  @param On_Delete on delete argument supplied to the operation.
   --  @param On_Update on update argument supplied to the operation.
   --  @param Deferred deferred argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Name              : Wide_Wide_String;
      Referencing_Table : Natural;
      Referenced_Table  : Natural;
      Referencing_Cols  : Column_Id_Vectors.Vector;
      Referenced_Cols   : Column_Id_Vectors.Vector;
      On_Delete         : Foreign_Key_Action := Restrict;
      On_Update         : Foreign_Key_Action := Restrict;
      Deferred          : Boolean := False) return Foreign_Key_Definition;

   --  Return validate definition for the supplied database state or arguments.
   --  @param Definition definition argument supplied to the operation.
   --  @param Referencing_Schema referencing schema argument supplied to the operation.
   --  @param Referenced_Schema referenced schema argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Definition
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Referenced_Schema  : Database.Schema.Table_Schema) return Database.Status.Result;

   --  Return referencing key is null for the supplied database state or arguments.
   --  @param Definition definition argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Referencing_Key_Is_Null
     (Definition : Foreign_Key_Definition;
      Schema     : Database.Schema.Table_Schema;
      Row        : Database.Rows.Row) return Boolean;

   --  Return rows match for the supplied database state or arguments.
   --  @param Left_Schema left schema argument supplied to the operation.
   --  @param Left_Row left row argument supplied to the operation.
   --  @param Left_Cols left cols argument supplied to the operation.
   --  @param Right_Schema right schema argument supplied to the operation.
   --  @param Right_Row right row argument supplied to the operation.
   --  @param Right_Cols right cols argument supplied to the operation.
   --  @return Result produced by the function.
   function Rows_Match
     (Left_Schema  : Database.Schema.Table_Schema;
      Left_Row     : Database.Rows.Row;
      Left_Cols    : Column_Id_Vectors.Vector;
      Right_Schema : Database.Schema.Table_Schema;
      Right_Row    : Database.Rows.Row;
      Right_Cols   : Column_Id_Vectors.Vector) return Boolean;

   --  Return validate insert or update for the supplied database state or arguments.
   --  @param Definition definition argument supplied to the operation.
   --  @param Referencing_Schema referencing schema argument supplied to the operation.
   --  @param Referenced_Schema referenced schema argument supplied to the operation.
   --  @param Referencing_Row referencing row argument supplied to the operation.
   --  @param Referenced_Rows referenced rows argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Insert_Or_Update
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Referenced_Schema  : Database.Schema.Table_Schema;
      Referencing_Row    : Database.Rows.Row;
      Referenced_Rows    : Row_Vectors.Vector) return Database.Status.Result;

   --  Return validate referenced delete for the supplied database state or arguments.
   --  @param Definition definition argument supplied to the operation.
   --  @param Referencing_Schema referencing schema argument supplied to the operation.
   --  @param Referenced_Schema referenced schema argument supplied to the operation.
   --  @param Referenced_Row referenced row argument supplied to the operation.
   --  @param Referencing_Rows referencing rows argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Referenced_Delete
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Referenced_Schema  : Database.Schema.Table_Schema;
      Referenced_Row     : Database.Rows.Row;
      Referencing_Rows   : Row_Vectors.Vector) return Database.Status.Result;

   --  Perform apply set null for the supplied database state or arguments.
   --  @param Definition definition argument supplied to the operation.
   --  @param Referencing_Schema referencing schema argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   procedure Apply_Set_Null
     (Definition         : Foreign_Key_Definition;
      Referencing_Schema : Database.Schema.Table_Schema;
      Row                : in out Database.Rows.Row);
end Database.Foreign_Keys;
