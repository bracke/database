--  Centralized MVCC visibility and conflict rules.
with Database.Transactions;
with Database.Versioning;

--  Visibility rules for MVCC row versions.
package Database.Visibility is
   --  Return is visible for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Version version argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Visible
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean;

   --  Return is deleted for for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Version version argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Deleted_For
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean;

   --  Return is own write for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Version version argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Own_Write
     (Tx      : Database.Transactions.Transaction;
      Version : Database.Versioning.Row_Version_Metadata) return Boolean;
end Database.Visibility;
