--  Live runtime diagnostic snapshots.
with Database.Versioning;

--  Runtime diagnostics aggregation.
package Database.Diagnostics.Runtime is
   --  Transaction_Diagnostics stores the public fields for this database abstraction.
   type Transaction_Diagnostics is record
      Active_Readers : Natural := 0;
      Writer_Active  : Boolean := False;
      Waiting_Writers : Natural := 0;
   end record;

   --  Snapshot_Diagnostics stores the public fields for this database abstraction.
   type Snapshot_Diagnostics is record
      Has_Active_Snapshot : Boolean := False;
      Oldest_Snapshot     : Database.Versioning.Commit_Version := 0;
   end record;

   --  WAL_Diagnostics stores the public fields for this database abstraction.
   type WAL_Diagnostics is record
      Exists : Boolean := False;
   end record;

   --  Checkpoint_Diagnostics stores the public fields for this database abstraction.
   type Checkpoint_Diagnostics is record
      Writer_Blocked : Boolean := False;
   end record;

   --  Cache_Diagnostics stores the public fields for this database abstraction.
   type Cache_Diagnostics is record
      Page_Reads  : Natural := 0;
      Page_Writes : Natural := 0;
      Cache_Hits  : Natural := 0;
      Cache_Misses : Natural := 0;
   end record;

   --  Lock_Diagnostics defines a public database type used by this package.
   subtype Lock_Diagnostics is Transaction_Diagnostics;

   --  Return active transactions for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Active_Transactions (DB : Database.Handle) return Transaction_Diagnostics;
   --  Return active snapshots for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Active_Snapshots return Snapshot_Diagnostics;
   --  Return wal state for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function WAL_State (DB : Database.Handle) return WAL_Diagnostics;
   --  Return checkpoint state for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Checkpoint_State (DB : Database.Handle) return Checkpoint_Diagnostics;
   --  Return cache statistics for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Cache_Statistics return Cache_Diagnostics;
   --  Return lock statistics for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Lock_Statistics (DB : Database.Handle) return Lock_Diagnostics;
end Database.Diagnostics.Runtime;
