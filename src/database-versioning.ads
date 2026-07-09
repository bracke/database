--  MVCC row version metadata and version identifiers.
with Database.Indexes;

--  Row-version descriptors and version-chain helpers.
package Database.Versioning
  with SPARK_Mode => On
is
   use type Database.Indexes.Row_Reference;

   --  Transaction_Id defines a public database type used by this package.
   subtype Transaction_Id is Natural;
   --  Commit_Version defines a public database type used by this package.
   subtype Commit_Version is Natural;

   --  No_Transaction is a public constant used by this package.
   No_Transaction : constant Transaction_Id := 0;
   --  No_Version is a public constant used by this package.
   No_Version     : constant Commit_Version := 0;
   --  Uncommitted_Version is a public constant used by this package.
   Uncommitted_Version : constant Commit_Version := Natural'Last;

   --  Row_Version_Flags stores the public fields for this database abstraction.
   type Row_Version_Flags is record
      Committed : Boolean := True;
      Deleted   : Boolean := False;
      Tombstone : Boolean := False;
   end record;

   --  Row_Version_Metadata stores the public fields for this database abstraction.
   type Row_Version_Metadata is record
      Created_By_Tx    : Transaction_Id := No_Transaction;
      Created_Version  : Commit_Version := No_Version;
      Deleted_By_Tx    : Transaction_Id := No_Transaction;
      Deleted_Version  : Commit_Version := No_Version;
      Previous_Version : Database.Indexes.Row_Reference := Database.Indexes.Invalid_Row_Reference;
      Flags            : Row_Version_Flags := (others => <>);
   end record;

   --  Return new committed for the supplied database state or arguments.
   --  @param Version version argument supplied to the operation.
   --  @return Result produced by the function.
   function New_Committed
     (Version : Commit_Version) return Row_Version_Metadata
     with
       Global => null,
       Post =>
         New_Committed'Result.Created_By_Tx = No_Transaction
         and then New_Committed'Result.Created_Version = Version
         and then New_Committed'Result.Deleted_By_Tx = No_Transaction
         and then New_Committed'Result.Deleted_Version = No_Version
         and then New_Committed'Result.Previous_Version = Database.Indexes.Invalid_Row_Reference
         and then New_Committed'Result.Flags.Committed
         and then not New_Committed'Result.Flags.Deleted
         and then not New_Committed'Result.Flags.Tombstone;

   --  Return new uncommitted for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @param Future_Version future version argument supplied to the operation.
   --  @param Previous previous argument supplied to the operation.
   --  @return Result produced by the function.
   function New_Uncommitted
     (Tx_Id          : Transaction_Id;
      Future_Version : Commit_Version;
      Previous       : Database.Indexes.Row_Reference := Database.Indexes.Invalid_Row_Reference)
      return Row_Version_Metadata
     with
       Global => null,
       Post =>
         New_Uncommitted'Result.Created_By_Tx = Tx_Id
         and then New_Uncommitted'Result.Created_Version = Future_Version
         and then New_Uncommitted'Result.Deleted_By_Tx = No_Transaction
         and then New_Uncommitted'Result.Deleted_Version = No_Version
         and then New_Uncommitted'Result.Previous_Version = Previous
         and then not New_Uncommitted'Result.Flags.Committed
         and then not New_Uncommitted'Result.Flags.Deleted
         and then not New_Uncommitted'Result.Flags.Tombstone;

   --  Perform mark deleted for the supplied database state or arguments.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @param Future_Version future version argument supplied to the operation.
   procedure Mark_Deleted
     (Metadata       : in out Row_Version_Metadata;
      Tx_Id          : Transaction_Id;
      Future_Version : Commit_Version)
     with
       Global => null,
       Depends => (Metadata => (Metadata, Tx_Id, Future_Version)),
       Post =>
         Metadata.Deleted_By_Tx = Tx_Id
         and then Metadata.Deleted_Version = Future_Version
         and then Metadata.Flags.Deleted
         and then Metadata.Created_By_Tx = Metadata'Old.Created_By_Tx
         and then Metadata.Created_Version = Metadata'Old.Created_Version
         and then Metadata.Previous_Version = Metadata'Old.Previous_Version
         and then Metadata.Flags.Committed = Metadata'Old.Flags.Committed
         and then Metadata.Flags.Tombstone = Metadata'Old.Flags.Tombstone;

   --  Perform clear delete for the supplied database state or arguments.
   --  @param Metadata metadata argument supplied to the operation.
   procedure Clear_Delete (Metadata : in out Row_Version_Metadata)
     with
       Global => null,
       Depends => (Metadata => Metadata),
       Post =>
         Metadata.Deleted_By_Tx = No_Transaction
         and then Metadata.Deleted_Version = No_Version
         and then not Metadata.Flags.Deleted
         and then Metadata.Created_By_Tx = Metadata'Old.Created_By_Tx
         and then Metadata.Created_Version = Metadata'Old.Created_Version
         and then Metadata.Previous_Version = Metadata'Old.Previous_Version
         and then Metadata.Flags.Committed = Metadata'Old.Flags.Committed
         and then Metadata.Flags.Tombstone = Metadata'Old.Flags.Tombstone;
end Database.Versioning;
