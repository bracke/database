with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Queries;
with Database.Rows;
use Database.Rows;
with Database.Status;
with Database.Transactions;

--  Materialized view metadata and refresh support.
package Database.Materialized_Views is
   use Ada.Strings.Wide_Wide_Unbounded;
   --  Materialized_View_Id defines a public database type used by this package.
   type Materialized_View_Id is new Natural;
   --  Row_Vectors stores ordered row values for this package.
   package Row_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Database.Rows.Row);
   --  Materialized_View_Definition stores the public fields for this database abstraction.
   type Materialized_View_Definition is record
      Id             : Materialized_View_Id := 0;
      Name           : Unbounded_Wide_Wide_String;
      Query          : Database.Queries.Query;
      Storage_Table  : Natural := 0;
      Last_Refresh_Commit : Natural := 0;
   end record;

   --  Compares two materialized-view definitions for equality.
   --  @param Left Left materialized-view definition operand.
   --  @param Right Right materialized-view definition operand.
   --  @return True when both definitions contain the same materialized-view metadata.
   overriding function "=" (Left, Right : Materialized_View_Definition) return Boolean;
   --  Materialized_View_Vectors stores ordered materialized view values for this package.
   package Materialized_View_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Materialized_View_Definition);
   --  Return create for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Query query argument supplied to the operation.
   --  @param Storage_Table storage table argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Name : Wide_Wide_String;
      Query : Database.Queries.Query;
      Storage_Table : Natural) return Materialized_View_Definition;
   --  Return validate for the supplied database state or arguments.
   --  @param View view argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate (View : Materialized_View_Definition) return Database.Status.Result;
   --  Return refresh for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param View view argument supplied to the operation.
   --  @param Rows rows argument supplied to the operation.
   --  @return Result produced by the function.
   function Refresh
     (Tx   : in out Database.Transactions.Transaction;
      View : in out Materialized_View_Definition;
      Rows : Row_Vectors.Vector) return Database.Status.Result;

   --  Incrementally merge row-set changes into a materialized result. Rows are
   --  matched by Key_Column. Deleted_Rows need only contain the key column.
   function Refresh_Incremental
     (Tx           : in out Database.Transactions.Transaction;
      View         : in out Materialized_View_Definition;
      Current_Rows : Row_Vectors.Vector;
      Inserted     : Row_Vectors.Vector;
      Updated      : Row_Vectors.Vector;
      Deleted_Rows : Row_Vectors.Vector;
      Key_Column   : Natural;
      Result       : out Row_Vectors.Vector) return Database.Status.Result;
end Database.Materialized_Views;
