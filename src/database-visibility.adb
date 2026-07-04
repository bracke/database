with Database.Transactions;
with Database.MVCC;

package body Database.Visibility is
   function Created_Visible
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
      Lifecycle : constant Database.MVCC.Transaction_Lifecycle  :=
        Database.MVCC.Lifecycle (Version.Created_By_Tx);
   begin
      if Version.Created_By_Tx = Database.Transactions.Id (Tx) then
         return True;
      end if;

      if not Version.Flags.Committed then
         case Lifecycle is
            when Database.MVCC.Committed =>
               return Version.Created_Version <= Database.Transactions.Snapshot_Version (Tx);
            when Database.MVCC.Rolled_Back | Database.MVCC.Active | Database.MVCC.Unknown =>
               return False;
         end case;
      end if;

      return Version.Created_Version <= Database.Transactions.Snapshot_Version (Tx);
   end Created_Visible;

   function Is_Deleted_For
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
      Lifecycle : constant Database.MVCC.Transaction_Lifecycle  :=
        Database.MVCC.Lifecycle (Version.Deleted_By_Tx);
   begin
      if not Version.Flags.Deleted then
         return False;
      end if;

      if Version.Deleted_By_Tx = Database.Transactions.Id (Tx) then
         return True;
      end if;

      if Version.Deleted_By_Tx /= Database.Versioning.No_Transaction then
         case Lifecycle is
            when Database.MVCC.Committed =>
               return Version.Deleted_Version /= Database.Versioning.No_Version
                 and then Version.Deleted_Version <= Database.Transactions.Snapshot_Version (Tx);
            when Database.MVCC.Rolled_Back | Database.MVCC.Active | Database.MVCC.Unknown =>
               return False;
         end case;
      end if;

      return Version.Deleted_Version /= Database.Versioning.No_Version
        and then Version.Deleted_Version <= Database.Transactions.Snapshot_Version (Tx);
   end Is_Deleted_For;

   function Is_Visible
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
   begin
      return Created_Visible (Tx, Version)
        and then not Is_Deleted_For (Tx, Version);
   end Is_Visible;

   function Is_Own_Write
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
   begin
      return Version.Created_By_Tx = Database.Transactions.Id (Tx)
        or else Version.Deleted_By_Tx = Database.Transactions.Id (Tx);
   end Is_Own_Write;

end Database.Visibility;
