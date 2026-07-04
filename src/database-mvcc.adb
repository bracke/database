package body Database.MVCC is
   Max_Tracked_Transactions : constant Natural := 65_535;

   type Snapshot_Counts is array (Natural range <>) of Natural;
   type Lifecycle_Array is array (Natural range <>) of Transaction_Lifecycle;
   type Commit_Array is array (Natural range <>) of Database.Versioning.Commit_Version;

   protected State is
      procedure Register_Snapshot (Snapshot : Database.Versioning.Commit_Version);
      procedure Release_Snapshot (Snapshot : Database.Versioning.Commit_Version);
      procedure Register_Tx (Tx_Id : Database.Versioning.Transaction_Id);
      procedure Commit_Tx
        (Tx_Id          : Database.Versioning.Transaction_Id;
         Commit_Version : Database.Versioning.Commit_Version);
      procedure Rollback_Tx (Tx_Id : Database.Versioning.Transaction_Id);
      function Tx_Lifecycle
        (Tx_Id : Database.Versioning.Transaction_Id) return Transaction_Lifecycle;
      function Tx_Commit_Version
        (Tx_Id : Database.Versioning.Transaction_Id) return Database.Versioning.Commit_Version;
      function Oldest return Database.Versioning.Commit_Version;
      function Any return Boolean;
   private
      Counts : Snapshot_Counts (0 .. 255) := (others => 0);
      Overflow_Count : Natural := 0;
      Overflow_Min   : Database.Versioning.Commit_Version := Database.Versioning.No_Version;
      Lifecycles     : Lifecycle_Array (0 .. Max_Tracked_Transactions) := (others => Unknown);
      Commit_Versions : Commit_Array (0 .. Max_Tracked_Transactions)  :=
        (others => Database.Versioning.No_Version);
   end State;

   protected body State is
      procedure Register_Snapshot (Snapshot : Database.Versioning.Commit_Version) is
      begin
         if Snapshot <= Counts'Last then
            Counts (Snapshot) := Counts (Snapshot) + 1;
         else
            Overflow_Count := Overflow_Count + 1;
            if Overflow_Min = Database.Versioning.No_Version or else Snapshot < Overflow_Min then
               Overflow_Min := Snapshot;
            end if;
         end if;
      end Register_Snapshot;

      procedure Release_Snapshot (Snapshot : Database.Versioning.Commit_Version) is
      begin
         if Snapshot <= Counts'Last then
            if Counts (Snapshot) > 0 then
               Counts (Snapshot) := Counts (Snapshot) - 1;
            end if;
         elsif Overflow_Count > 0 then
            Overflow_Count := Overflow_Count - 1;
            if Overflow_Count = 0 then
               Overflow_Min := Database.Versioning.No_Version;
            end if;
         end if;
      end Release_Snapshot;

      procedure Register_Tx (Tx_Id : Database.Versioning.Transaction_Id) is
      begin
         if Tx_Id in Lifecycles'Range then
            Lifecycles (Tx_Id) := Active;
            Commit_Versions (Tx_Id) := Database.Versioning.No_Version;
         end if;
      end Register_Tx;

      procedure Commit_Tx
        (Tx_Id          : Database.Versioning.Transaction_Id;
         Commit_Version : Database.Versioning.Commit_Version) is
      begin
         if Tx_Id in Lifecycles'Range then
            Lifecycles (Tx_Id) := Committed;
            Commit_Versions (Tx_Id) := Commit_Version;
         end if;
      end Commit_Tx;

      procedure Rollback_Tx (Tx_Id : Database.Versioning.Transaction_Id) is
      begin
         if Tx_Id in Lifecycles'Range then
            Lifecycles (Tx_Id) := Rolled_Back;
            Commit_Versions (Tx_Id) := Database.Versioning.No_Version;
         end if;
      end Rollback_Tx;

      function Tx_Lifecycle
        (Tx_Id : Database.Versioning.Transaction_Id) return Transaction_Lifecycle is
      begin
         if Tx_Id = Database.Versioning.No_Transaction then
            return Committed;
         elsif Tx_Id in Lifecycles'Range then
            return Lifecycles (Tx_Id);
         else
            return Unknown;
         end if;
      end Tx_Lifecycle;

      function Tx_Commit_Version
        (Tx_Id : Database.Versioning.Transaction_Id) return Database.Versioning.Commit_Version is
      begin
         if Tx_Id in Commit_Versions'Range then
            return Commit_Versions (Tx_Id);
         else
            return Database.Versioning.No_Version;
         end if;
      end Tx_Commit_Version;

      function Oldest return Database.Versioning.Commit_Version is
      begin
         for I in Counts'Range loop
            if Counts (I) > 0 then
               return I;
            end if;
         end loop;
         return Overflow_Min;
      end Oldest;

      function Any return Boolean is
      begin
         if Overflow_Count > 0 then
            return True;
         end if;
         for I in Counts'Range loop
            if Counts (I) > 0 then
               return True;
            end if;
         end loop;
         return False;
      end Any;
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
end Database.MVCC;
