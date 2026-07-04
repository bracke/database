with Database.Metrics;
with Database.MVCC;
with Database.Storage.File_IO;
with Database.WAL;

package body Database.Diagnostics.Runtime is
   function Active_Transactions (DB : Database.Handle) return Transaction_Diagnostics is
   begin
      return (Active_Readers => DB.Lock.Active_Readers,
              Writer_Active => DB.Lock.Writer_Active,
              Waiting_Writers => DB.Lock.Waiting_Writers);
   end Active_Transactions;

   function Active_Snapshots return Snapshot_Diagnostics is
   begin
      return (Has_Active_Snapshot => Database.MVCC.Has_Active_Snapshot,
              Oldest_Snapshot => Database.MVCC.Oldest_Active_Snapshot);
   end Active_Snapshots;

   function WAL_State (DB : Database.Handle) return WAL_Diagnostics is
   begin
      if Database.Backend (DB) = Database.Persistent_Backend then
         return (Exists => Database.WAL.Exists (Database.Storage.File_IO.Path (DB.File)));
      end if;
      return (Exists => False);
   end WAL_State;

   function Checkpoint_State (DB : Database.Handle) return Checkpoint_Diagnostics is
   begin
      return (Writer_Blocked => DB.Lock.Writer_Active);
   end Checkpoint_State;

   function Cache_Statistics return Cache_Diagnostics is
      S : constant Database.Metrics.Metrics_Snapshot := Database.Metrics.Snapshot_Metrics;
   begin
      return (Page_Reads => S.Page_Reads,
              Page_Writes => S.Page_Writes,
              Cache_Hits => S.Cache_Hits,
              Cache_Misses => S.Cache_Misses);
   end Cache_Statistics;

   function Lock_Statistics (DB : Database.Handle) return Lock_Diagnostics is
   begin
      return Active_Transactions (DB);
   end Lock_Statistics;
end Database.Diagnostics.Runtime;
