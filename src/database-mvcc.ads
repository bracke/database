--  MVCC global snapshot and transaction-lifecycle state.
with Database.Versioning;

--  MVCC snapshot and transaction visibility management.
package Database.MVCC is
   --  Transaction_Lifecycle enumerates the supported values for this database abstraction.
   type Transaction_Lifecycle is (Unknown, Active, Committed, Rolled_Back);

   --  Perform register snapshot for the supplied database state or arguments.
   --  @param Snapshot snapshot argument supplied to the operation.
   procedure Register_Snapshot (Snapshot : Database.Versioning.Commit_Version);
   --  Perform release snapshot for the supplied database state or arguments.
   --  @param Snapshot snapshot argument supplied to the operation.
   procedure Release_Snapshot (Snapshot : Database.Versioning.Commit_Version);

   --  Perform register transaction for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   procedure Register_Transaction (Tx_Id : Database.Versioning.Transaction_Id);
   --  Perform mark committed for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @param Commit_Version commit version argument supplied to the operation.
   procedure Mark_Committed
     (Tx_Id          : Database.Versioning.Transaction_Id;
      Commit_Version : Database.Versioning.Commit_Version);
   --  Perform mark rolled back for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   procedure Mark_Rolled_Back (Tx_Id : Database.Versioning.Transaction_Id);

   --  Return lifecycle for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @return Result produced by the function.
   function Lifecycle
     (Tx_Id : Database.Versioning.Transaction_Id) return Transaction_Lifecycle;
   --  Return transaction commit version for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @return Result produced by the function.
   function Transaction_Commit_Version
     (Tx_Id : Database.Versioning.Transaction_Id) return Database.Versioning.Commit_Version;

   --  Return oldest active snapshot for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Oldest_Active_Snapshot return Database.Versioning.Commit_Version;
   --  Return has active snapshot for the supplied database state or arguments.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Has_Active_Snapshot return Boolean;
   --  Return safe reclaim version for the supplied database state or arguments.
   --  @param Version version argument supplied to the operation.
   --  @return Result produced by the function.
   function Safe_Reclaim_Version
     (Version : Database.Versioning.Commit_Version) return Boolean;
end Database.MVCC;
