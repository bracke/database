with Database.Transactions;
with Database.MVCC;
with Database.Visibility.Rules;

package body Database.Visibility is
   function Created_Visible
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
      Lifecycle : constant Database.MVCC.Transaction_Lifecycle  :=
        Database.MVCC.Lifecycle (Version.Created_By_Tx);
   begin
      return Database.Visibility.Rules.Created_Is_Visible
        (Tx_Id             => Database.Transactions.Id (Tx),
         Snapshot          => Database.Transactions.Snapshot_Version (Tx),
         Created_By_Tx     => Version.Created_By_Tx,
         Created_Version   => Version.Created_Version,
         Created_Committed => Version.Flags.Committed,
         Created_Lifecycle => Lifecycle);
   end Created_Visible;

   function Is_Deleted_For
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
      Lifecycle : constant Database.MVCC.Transaction_Lifecycle  :=
        Database.MVCC.Lifecycle (Version.Deleted_By_Tx);
   begin
      return Database.Visibility.Rules.Deleted_For
        (Tx_Id             => Database.Transactions.Id (Tx),
         Snapshot          => Database.Transactions.Snapshot_Version (Tx),
         Deleted           => Version.Flags.Deleted,
         Deleted_By_Tx     => Version.Deleted_By_Tx,
         Deleted_Version   => Version.Deleted_Version,
         Deleted_Lifecycle => Lifecycle);
   end Is_Deleted_For;

   function Is_Visible
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
   begin
      return Database.Visibility.Rules.Version_Is_Visible
        (Created_Visible => Created_Visible (Tx, Version),
         Deleted         => Is_Deleted_For (Tx, Version));
   end Is_Visible;

   function Is_Own_Write
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean is
   begin
      return Database.Visibility.Rules.Is_Own_Write
        (Tx_Id         => Database.Transactions.Id (Tx),
         Created_By_Tx => Version.Created_By_Tx,
         Deleted_By_Tx => Version.Deleted_By_Tx);
   end Is_Own_Write;

end Database.Visibility;
