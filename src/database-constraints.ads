--  Centralized schema and row constraint validation.
with Database.Rows;
with Database.Schema;
with Database.Status;

   --  Public nested package `Database.Constraints`.
package Database.Constraints is
   --  Public operation `Validate_Row`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Row
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Database.Status.Result;
end Database.Constraints;
