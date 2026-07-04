--  Transaction-scoped persistent database compaction.
with Database.Status;
with Database.Transactions;

   --  Public nested package `Database.Vacuum`.
package Database.Vacuum is
   --  Public operation `Vacuum`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Vacuum
     (Tx : in out Database.Transactions.Transaction) return Database.Status.Result;
end Database.Vacuum;
