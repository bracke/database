--  MVCC row version metadata and version identifiers.
with Database.Indexes;

--  Row-version descriptors and version-chain helpers.
package Database.Versioning is
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
     (Version : Commit_Version) return Row_Version_Metadata;

   --  Return new uncommitted for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @param Future_Version future version argument supplied to the operation.
   --  @param Previous previous argument supplied to the operation.
   --  @return Result produced by the function.
   function New_Uncommitted
     (Tx_Id          : Transaction_Id;
      Future_Version : Commit_Version;
      Previous       : Database.Indexes.Row_Reference := Database.Indexes.Invalid_Row_Reference)
      return Row_Version_Metadata;

   --  Perform mark deleted for the supplied database state or arguments.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @param Future_Version future version argument supplied to the operation.
   procedure Mark_Deleted
     (Metadata       : in out Row_Version_Metadata;
      Tx_Id          : Transaction_Id;
      Future_Version : Commit_Version);

   --  Perform clear delete for the supplied database state or arguments.
   --  @param Metadata metadata argument supplied to the operation.
   procedure Clear_Delete (Metadata : in out Row_Version_Metadata);
end Database.Versioning;
