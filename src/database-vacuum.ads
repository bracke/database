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

   --  What vacuum did with the table heap and index pages no catalog root reaches.
   type Vacuum_Report is record
      --  Pages returned to the free list.
      Freed_Pages          : Natural := 0;
      --  True when some heap chain or index tree could not be followed, so no page was freed: the pages behind the
      --  broken link may be in use. The integrity check tells where.
      Reachability_Unknown : Boolean := False;
   end record;

   --  Vacuum as above, and report what happened to the unreachable pages.
   --  @param Tx active write transaction.
   --  @param Report what vacuum did with the pages no catalog root reaches.
   --  @return Status result; Read_Only_Transaction for a read-only transaction.
   function Vacuum
     (Tx     : in out Database.Transactions.Transaction;
      Report : out Vacuum_Report) return Database.Status.Result;
end Database.Vacuum;
