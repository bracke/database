--  Central store for the in-memory (non-persistent) table backend.
--
--  Rows for every in-memory table live here in type-erased form
--  (Database.Rows.Row plus MVCC metadata), partitioned by (database state key,
--  table id). Because the store is a single non-generic unit, code outside the
--  Database.Tables.Typed generic -- notably Database.Transactions.Rollback --
--  can finalize an aborted transaction directly (see Rollback), with no
--  per-instantiation callback registry and no access-to-subprogram tricks.
--
--  The store guards its partition map with a protected object, so distinct
--  database handles (which own distinct partitions) may operate on it
--  concurrently and safely. Each operation is a single protected action.
with Database.Versioning;
with Database.Rows;

package Database.Memory_Store is

   --  Identifies one table's partition. State_Key separates database handles;
   --  Table_Id separates tables within a handle.
   type Table_Key is record
      State_Key : Natural := 0;
      Table_Id  : Natural := 0;
   end record;

   --  A stored row: the serialised row value and its version metadata.
   type Stored_Row is record
      Row      : Database.Rows.Row;
      Metadata : Database.Versioning.Row_Version_Metadata;
   end record;

   --  A whole partition, index 0 .. N-1 (empty when the partition has no rows).
   type Stored_Row_Array is array (Natural range <>) of Stored_Row;

   --  Copy of a partition's rows for a single operation. One call per operation
   --  (rather than per row) keeps in-memory scans off the hashed-map lookup
   --  path. Indices line up with Put.
   function Snapshot (Key : Table_Key) return Stored_Row_Array;

   --  Replace the row at a 0-based index within a partition.
   procedure Put (Key : Table_Key; Index : Natural; Value : Stored_Row);

   --  Append a row to a partition, creating the partition if necessary.
   procedure Append (Key : Table_Key; Value : Stored_Row);

   --  Finalize an aborted transaction across every partition: drop rows it
   --  created and undo the delete marks it made.
   procedure Rollback (Tx_Id : Database.Versioning.Transaction_Id);

   --  Free every partition belonging to a database state key. Called when an
   --  in-memory handle is closed (see Database.Close), so a closed handle
   --  leaves no rows behind and the store does not grow across open/close
   --  cycles. Harmless for a persistent handle (it owns no partitions).
   procedure Drop (State_Key : Natural);

end Database.Memory_Store;
