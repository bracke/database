package body Database.Versioning is
   function New_Committed
     (Version : Commit_Version) return Row_Version_Metadata is
   begin
      return
        (Created_By_Tx    => No_Transaction,
         Created_Version  => Version,
         Deleted_By_Tx    => No_Transaction,
         Deleted_Version  => No_Version,
         Previous_Version => Database.Indexes.Invalid_Row_Reference,
         Flags            => (Committed => True, Deleted => False, Tombstone => False));
   end New_Committed;

   function New_Uncommitted
     (Tx_Id          : Transaction_Id;
      Future_Version : Commit_Version;
      Previous       : Database.Indexes.Row_Reference := Database.Indexes.Invalid_Row_Reference)
      return Row_Version_Metadata is
   begin
      return
        (Created_By_Tx    => Tx_Id,
         Created_Version  => Future_Version,
         Deleted_By_Tx    => No_Transaction,
         Deleted_Version  => No_Version,
         Previous_Version => Previous,
         Flags            => (Committed => False, Deleted => False, Tombstone => False));
   end New_Uncommitted;

   procedure Mark_Deleted
     (Metadata       : in out Row_Version_Metadata;
      Tx_Id          : Transaction_Id;
      Future_Version : Commit_Version) is
   begin
      Metadata.Deleted_By_Tx := Tx_Id;
      Metadata.Deleted_Version := Future_Version;
      Metadata.Flags.Deleted := True;
   end Mark_Deleted;

   procedure Clear_Delete (Metadata : in out Row_Version_Metadata) is
   begin
      Metadata.Deleted_By_Tx := No_Transaction;
      Metadata.Deleted_Version := No_Version;
      Metadata.Flags.Deleted := False;
   end Clear_Delete;
end Database.Versioning;
