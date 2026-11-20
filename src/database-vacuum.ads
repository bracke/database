--  Transaction-scoped persistent database compaction.
with Database.Status;
with Database.Transactions;

   --  Public nested package `Database.Vacuum`.
package Database.Vacuum is
   --  Reclaim space in the database of a write transaction: remove the rows deleted for every snapshot from table heaps
   --  and indexes, compact full-text indexes, and return to the free list the table heap and index pages that no
   --  catalog root reaches, unless some root cannot be followed.
   --  @param Tx active write transaction.
   --  @return Status result; Read_Only_Transaction for a read-only transaction.
   function Vacuum
     (Tx : in out Database.Transactions.Transaction) return Database.Status.Result;
end Database.Vacuum;
