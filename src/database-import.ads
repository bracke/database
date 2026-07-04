--  Database-native logical import support. The format is not SQL.
with Database.Status;
with Database.Transactions;

--  Logical import operations.
package Database.Import is
   --  Import_Options stores the public fields for this database abstraction.
   type Import_Options is record
      Verify_After_Import : Boolean := True;
   end record;

   --  Return import database for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Source filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Import_Database
     (Tx     : in out Database.Transactions.Transaction;
      Source : Wide_Wide_String) return Database.Status.Result;

   --  Return import database for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Source filesystem path or artifact location used by the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Import_Database
     (Tx      : in out Database.Transactions.Transaction;
      Source  : Wide_Wide_String;
      Options : Import_Options) return Database.Status.Result;
end Database.Import;
