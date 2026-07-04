with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
package body Database.Materialized_Views is

   overriding function "=" (Left, Right : Materialized_View_Definition) return Boolean is
   begin
      return Left.Id = Right.Id and then Left.Name = Right.Name;
   end "=";
   function Create
     (Name          : Wide_Wide_String;
      Query         : Database.Queries.Query;
      Storage_Table : Natural) return Materialized_View_Definition is
   begin
      return (Id => 0, Name => To_Unbounded_Wide_Wide_String (Name), Query => Query,
              Storage_Table => Storage_Table, Last_Refresh_Commit => 0);
   end Create;
   function Validate (View : Materialized_View_Definition) return Database.Status.Result is
   begin
      if Length (View.Name) = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "materialized view name must not be empty");
      elsif View.Storage_Table = 0 then
         return Database.Status.Failure (Database.Status.Invalid_Schema,
           "materialized view storage table must be registered");
      end if;
      return Database.Status.Success;
   end Validate;
   function Refresh
     (Tx   : in out Database.Transactions.Transaction;
      View : in out Materialized_View_Definition;
      Rows : Row_Vectors.Vector) return Database.Status.Result is
      pragma Unreferenced (Rows);
   begin
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure (Database.Status.Read_Only_Transaction,
           "materialized view refresh requires a write transaction");
      end if;
      View.Last_Refresh_Commit := Natural (Database.Transactions.Snapshot_Version (Tx));
      return Validate (View);
   end Refresh;
end Database.Materialized_Views;
