with Ada.Containers;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Ordered_Maps;

package body Database.MVCC is

   --  Transaction lifecycles and active snapshots are tracked in dynamic maps:
   --  there is no ceiling on the number of transactions or on snapshot commit
   --  versions, and the lifecycle map is bounded over a long-running session:
   --
   --    * A committed transaction's entry is reclaimed once its commit version
   --      is below every active snapshot (see Reclaim_Settled). Safe because a
   --      missing entry reads Unknown, which the visibility and reclamation
   --      rules treat as committed for any persisted or in-memory row -- version
   --      gating then gives the same answer.
   --    * An aborted transaction is forgotten outright on rollback (see
   --      Database.Transactions), once its work has been undone in every store
   --      (heap before-images, in-memory finalizers, full-text rollback), so
   --      nothing references it.
   --    * Only active (in-flight) entries are pinned.
   --
   --  Steady-state size is therefore bounded by in-flight transactions plus
   --  commits since the oldest live snapshot -- not by total history.

   type Lifecycle_Entry is record
      Life    : Transaction_Lifecycle := Unknown;
      Version : Database.Versioning.Commit_Version := Database.Versioning.No_Version;
   end record;

   function Tx_Hash (Id : Database.Versioning.Transaction_Id)
     return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type'Mod (Id));

   package Lifecycle_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Database.Versioning.Transaction_Id,
      Element_Type    => Lifecycle_Entry,
      Hash            => Tx_Hash,
      Equivalent_Keys => "=");

   --  Active snapshots keyed by commit version; only versions with at least one
   --  live reader are present, so the smallest key is the oldest active
   --  snapshot (exact, unlike the former fixed-range-plus-overflow scheme).
   package Snapshot_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type     => Database.Versioning.Commit_Version,
      Element_Type => Natural);

   --  Committed transactions indexed by their unique, monotonic commit version,
   --  so settled entries can be reclaimed from the low end without scanning the
   --  whole lifecycle map.
   package Version_Tx_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type     => Database.Versioning.Commit_Version,
      Element_Type => Database.Versioning.Transaction_Id);

   protected State is
      procedure Register_Snapshot (Snapshot : Database.Versioning.Commit_Version);
      procedure Release_Snapshot (Snapshot : Database.Versioning.Commit_Version);
      procedure Register_Tx (Tx_Id : Database.Versioning.Transaction_Id);
      procedure Commit_Tx
        (Tx_Id          : Database.Versioning.Transaction_Id;
         Commit_Version : Database.Versioning.Commit_Version);
      procedure Rollback_Tx (Tx_Id : Database.Versioning.Transaction_Id);
      procedure Forget_Tx (Tx_Id : Database.Versioning.Transaction_Id);
      function Tx_Lifecycle
        (Tx_Id : Database.Versioning.Transaction_Id) return Transaction_Lifecycle;
      function Tx_Commit_Version
        (Tx_Id : Database.Versioning.Transaction_Id) return Database.Versioning.Commit_Version;
      function Oldest return Database.Versioning.Commit_Version;
      function Any return Boolean;
      function Live_Count return Natural;
   private
      procedure Reclaim_Settled;
      Lives      : Lifecycle_Maps.Map;
      Snapshots  : Snapshot_Maps.Map;
      Committed_By_Version : Version_Tx_Maps.Map;
   end State;

   protected body State is
      procedure Register_Snapshot (Snapshot : Database.Versioning.Commit_Version) is
         C : constant Snapshot_Maps.Cursor := Snapshots.Find (Snapshot);
      begin
         if Snapshot_Maps.Has_Element (C) then
            Snapshots.Replace_Element (C, Snapshot_Maps.Element (C) + 1);
         else
            Snapshots.Insert (Snapshot, 1);
         end if;
      end Register_Snapshot;

      procedure Release_Snapshot (Snapshot : Database.Versioning.Commit_Version) is
         C : Snapshot_Maps.Cursor := Snapshots.Find (Snapshot);
      begin
         if Snapshot_Maps.Has_Element (C) then
            declare
               N : constant Natural := Snapshot_Maps.Element (C);
            begin
               if N <= 1 then
                  Snapshots.Delete (C);
               else
                  Snapshots.Replace_Element (C, N - 1);
               end if;
            end;
         end if;
         --  The oldest active snapshot can only rise here; drop entries that
         --  are now settled below it.
         Reclaim_Settled;
      end Release_Snapshot;

      procedure Reclaim_Settled is
         Bound : Database.Versioning.Commit_Version;
      begin
         if Snapshots.Is_Empty then
            --  No live reader: every committed version is settled.
            Bound := Database.Versioning.Commit_Version'Last;
         else
            Bound := Snapshot_Maps.Key (Snapshots.First);
         end if;
         while not Committed_By_Version.Is_Empty loop
            declare
               C  : Version_Tx_Maps.Cursor := Committed_By_Version.First;
               V  : constant Database.Versioning.Commit_Version :=
                 Version_Tx_Maps.Key (C);
               Id : constant Database.Versioning.Transaction_Id :=
                 Version_Tx_Maps.Element (C);
            begin
               exit when V >= Bound;
               Committed_By_Version.Delete (C);
               Lives.Exclude (Id);
            end;
         end loop;
      end Reclaim_Settled;

      procedure Register_Tx (Tx_Id : Database.Versioning.Transaction_Id) is
      begin
         Lives.Include
           (Tx_Id, (Life => Active, Version => Database.Versioning.No_Version));
      end Register_Tx;

      procedure Commit_Tx
        (Tx_Id          : Database.Versioning.Transaction_Id;
         Commit_Version : Database.Versioning.Commit_Version) is
      begin
         Lives.Include (Tx_Id, (Life => Committed, Version => Commit_Version));
         --  Index by commit version for low-end reclamation. Versions are
         --  unique and monotonic, so Include never collides in practice.
         Committed_By_Version.Include (Commit_Version, Tx_Id);
      end Commit_Tx;

      procedure Rollback_Tx (Tx_Id : Database.Versioning.Transaction_Id) is
      begin
         Lives.Include
           (Tx_Id, (Life => Rolled_Back, Version => Database.Versioning.No_Version));
      end Rollback_Tx;

      procedure Forget_Tx (Tx_Id : Database.Versioning.Transaction_Id) is
      begin
         Lives.Exclude (Tx_Id);
      end Forget_Tx;

      function Tx_Lifecycle
        (Tx_Id : Database.Versioning.Transaction_Id) return Transaction_Lifecycle is
      begin
         if Tx_Id = Database.Versioning.No_Transaction then
            return Committed;
         end if;
         declare
            C : constant Lifecycle_Maps.Cursor := Lives.Find (Tx_Id);
         begin
            if Lifecycle_Maps.Has_Element (C) then
               return Lifecycle_Maps.Element (C).Life;
            else
               return Unknown;
            end if;
         end;
      end Tx_Lifecycle;

      function Tx_Commit_Version
        (Tx_Id : Database.Versioning.Transaction_Id) return Database.Versioning.Commit_Version is
         C : constant Lifecycle_Maps.Cursor := Lives.Find (Tx_Id);
      begin
         if Lifecycle_Maps.Has_Element (C) then
            return Lifecycle_Maps.Element (C).Version;
         else
            return Database.Versioning.No_Version;
         end if;
      end Tx_Commit_Version;

      function Oldest return Database.Versioning.Commit_Version is
      begin
         if Snapshots.Is_Empty then
            return Database.Versioning.No_Version;
         else
            return Snapshot_Maps.Key (Snapshots.First);
         end if;
      end Oldest;

      function Any return Boolean is
      begin
         return not Snapshots.Is_Empty;
      end Any;

      function Live_Count return Natural is
      begin
         return Natural (Lives.Length);
      end Live_Count;
   end State;

   procedure Register_Snapshot (Snapshot : Database.Versioning.Commit_Version) is
   begin
      State.Register_Snapshot (Snapshot);
   end Register_Snapshot;

   procedure Release_Snapshot (Snapshot : Database.Versioning.Commit_Version) is
   begin
      State.Release_Snapshot (Snapshot);
   end Release_Snapshot;

   procedure Register_Transaction (Tx_Id : Database.Versioning.Transaction_Id) is
   begin
      State.Register_Tx (Tx_Id);
   end Register_Transaction;

   procedure Mark_Committed
     (Tx_Id          : Database.Versioning.Transaction_Id;
      Commit_Version : Database.Versioning.Commit_Version) is
   begin
      State.Commit_Tx (Tx_Id, Commit_Version);
   end Mark_Committed;

   procedure Mark_Rolled_Back (Tx_Id : Database.Versioning.Transaction_Id) is
   begin
      State.Rollback_Tx (Tx_Id);
   end Mark_Rolled_Back;

   procedure Forget (Tx_Id : Database.Versioning.Transaction_Id) is
   begin
      State.Forget_Tx (Tx_Id);
   end Forget;

   function Lifecycle
     (Tx_Id : Database.Versioning.Transaction_Id) return Transaction_Lifecycle is
   begin
      return State.Tx_Lifecycle (Tx_Id);
   end Lifecycle;

   function Transaction_Commit_Version
     (Tx_Id : Database.Versioning.Transaction_Id) return Database.Versioning.Commit_Version is
   begin
      return State.Tx_Commit_Version (Tx_Id);
   end Transaction_Commit_Version;

   function Oldest_Active_Snapshot return Database.Versioning.Commit_Version is
   begin
      return State.Oldest;
   end Oldest_Active_Snapshot;

   function Has_Active_Snapshot return Boolean is
   begin
      return State.Any;
   end Has_Active_Snapshot;

   function Safe_Reclaim_Version
     (Version : Database.Versioning.Commit_Version) return Boolean is
      Oldest : constant Database.Versioning.Commit_Version := Oldest_Active_Snapshot;
   begin
      return Oldest = Database.Versioning.No_Version or else Version < Oldest;
   end Safe_Reclaim_Version;

   function Tracked_Transaction_Count return Natural is
   begin
      return State.Live_Count;
   end Tracked_Transaction_Count;
end Database.MVCC;
