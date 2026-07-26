package body Database.Visibility.Rules
  with SPARK_Mode => On
is
   function Created_Is_Visible
     (Tx_Id            : Database.Versioning.Transaction_Id;
      Snapshot         : Database.Versioning.Commit_Version;
      Created_By_Tx    : Database.Versioning.Transaction_Id;
      Created_Version  : Database.Versioning.Commit_Version;
      Created_Committed : Boolean;
      Created_Lifecycle : Database.MVCC.Transaction_Lifecycle) return Boolean
   is
   begin
      if Created_By_Tx = Tx_Id then
         return True;
      end if;

      if not Created_Committed then
         case Created_Lifecycle is
            when Database.MVCC.Committed | Database.MVCC.Unknown =>
               --  Unknown means the creating transaction is no longer tracked in
               --  the live MVCC map. That happens once a committed transaction's
               --  entry has been reclaimed (see Database.MVCC) or after a restart
               --  -- never for an active or rolled-back one, which are always
               --  retained -- so it can only be a settled commit. Version gating
               --  then gives the right answer, exactly as for a heap row whose
               --  Created_Committed flag is synthesised true on read. (Symmetric
               --  with Deleted_For; it is what lets the map reclaim entries
               --  without hiding in-memory rows whose flag stays false.)
               return Created_Version <= Snapshot;
            when Database.MVCC.Rolled_Back | Database.MVCC.Active =>
               return False;
         end case;
      end if;

      return Created_Version <= Snapshot;
   end Created_Is_Visible;

   function Deleted_For
     (Tx_Id             : Database.Versioning.Transaction_Id;
      Snapshot          : Database.Versioning.Commit_Version;
      Deleted           : Boolean;
      Deleted_By_Tx     : Database.Versioning.Transaction_Id;
      Deleted_Version   : Database.Versioning.Commit_Version;
      Deleted_Lifecycle : Database.MVCC.Transaction_Lifecycle) return Boolean
   is
   begin
      if not Deleted then
         return False;
      end if;

      if Deleted_By_Tx = Tx_Id then
         return True;
      end if;

      if Deleted_By_Tx /= Database.Versioning.No_Transaction then
         case Deleted_Lifecycle is
            when Database.MVCC.Committed | Database.MVCC.Unknown =>
               --  Unknown mirrors the creation path: a persisted tombstone whose
               --  deleting transaction is no longer tracked in the live MVCC map
               --  must be treated as a committed deletion. This happens after WAL
               --  replay on restart (the map starts empty) or when the lifecycle
               --  map reclaims a long-committed transaction. A row read back from
               --  the heap already synthesises Created "Committed => True" for the
               --  same reason (Metadata_At); deletion needs the symmetric rule, or
               --  a committed-and-deleted row springs back to life. A live
               --  transaction is always registered, so an Active or Rolled_Back
               --  deletion is never Unknown -- only forgotten committed ones are.
               --  In-flight deletions stay suppressed via version gating
               --  (Deleted_Version is the future commit version, > any snapshot).
               return Deleted_Version /= Database.Versioning.No_Version
                 and then Deleted_Version <= Snapshot;
            when Database.MVCC.Rolled_Back | Database.MVCC.Active =>
               return False;
         end case;
      end if;

      return Deleted_Version /= Database.Versioning.No_Version
        and then Deleted_Version <= Snapshot;
   end Deleted_For;

   function Version_Is_Visible
     (Created_Visible : Boolean;
      Deleted         : Boolean) return Boolean
   is
   begin
      return Created_Visible and then not Deleted;
   end Version_Is_Visible;

   function Is_Own_Write
     (Tx_Id         : Database.Versioning.Transaction_Id;
      Created_By_Tx : Database.Versioning.Transaction_Id;
      Deleted_By_Tx : Database.Versioning.Transaction_Id) return Boolean
   is
   begin
      return Created_By_Tx = Tx_Id or else Deleted_By_Tx = Tx_Id;
   end Is_Own_Write;
end Database.Visibility.Rules;
