--  Database-native logical export support. The format is not SQL.
with Database.Status;
with Database.Transactions;

--  Logical export operations.
package Database.Export is
   --  Export_Options stores the public fields for this database abstraction.
   type Export_Options is record
      Include_Full_Text_Rebuild_Data : Boolean := True;
      Verify_After_Write             : Boolean := True;
   end record;

   --  Return export database for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Export_Database
     (Tx          : in out Database.Transactions.Transaction;
      Destination : Wide_Wide_String) return Database.Status.Result;

   --  Return export database for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Export_Database
     (Tx          : in out Database.Transactions.Transaction;
      Destination : Wide_Wide_String;
      Options     : Export_Options) return Database.Status.Result;
end Database.Export;
