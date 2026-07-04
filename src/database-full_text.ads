--  Ada-native full-text search API. No SQL parser or external search engine is used.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Transactions;
with Database.Versioning;

--  Full-text indexing and search subsystem.
package Database.Full_Text is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Search_Result stores the public fields for this database abstraction.
   type Search_Result is record
      Table_Id  : Natural := 0;
      Row_Id    : Natural := 0;
      Row_Key   : Unbounded_Wide_Wide_String;
      Column_Id : Natural := 0;
      Score     : Long_Float := 0.0;
   end record;

   --  Search_Result_Vectors stores ordered search result values for this package.
   package Search_Result_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Search_Result);

   --  Search_Cursor defines a public database type used by this package.
   type Search_Cursor is private;

   --  Return create full text index for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Name logical name of the object.
   --  @param Table_Name table name argument supplied to the operation.
   --  @param Column column argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create_Full_Text_Index
     (Tx         : in out Database.Transactions.Transaction;
      Name       : Wide_Wide_String;
      Table_Name : Wide_Wide_String;
      Column     : Natural) return Database.Status.Result;

   --  Return drop full text index for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Drop_Full_Text_Index
     (Tx   : in out Database.Transactions.Transaction;
      Name : Wide_Wide_String) return Database.Status.Result;

   --  Return search for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Query query argument supplied to the operation.
   --  @return Result produced by the function.
   function Search
     (Tx    : in out Database.Transactions.Transaction;
      Index : Wide_Wide_String;
      Query : Wide_Wide_String) return Search_Cursor;

   --  Status-returning search variant. Unlike Search, this reports missing
   --  indexes and invalid query/index failures instead of collapsing them into
   --  an empty cursor. New code should prefer this operation when ordinary
   --  failure reporting matters.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Query query argument supplied to the operation.
   --  @param Cursor cursor argument supplied to the operation.
   --  @return Result produced by the function.
   function Try_Search
     (Tx     : in out Database.Transactions.Transaction;
      Index  : Wide_Wide_String;
      Query  : Wide_Wide_String;
      Cursor : out Search_Cursor) return Database.Status.Result;

   --  Return has element for the supplied database state or arguments.
   --  @param C c argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Has_Element (C : Search_Cursor) return Boolean;
   --  Return element for the supplied database state or arguments.
   --  @param C c argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Element (C : Search_Cursor) return Search_Result;
   --  Perform next for the supplied database state or arguments.
   --  @param C c argument supplied to the operation.
   procedure Next (C : in out Search_Cursor);
   --  Return row count for the supplied database state or arguments.
   --  @param C c argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Row_Count (C : Search_Cursor) return Natural;

   --  Return the stable full-text row identity for Row.
   --  The identity is derived from the primary-key column values when the
   --  schema has a primary key, and from the whole row only for schemas
   --  without primary-key metadata. It is deliberately independent of the
   --  row position inside the catalog cache, so deleting one row cannot make
   --  postings for later rows point at a different row.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Row_Identity
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Natural;

   --  Resolve a full-text row reference through the owning transaction.
   --  Persistent databases are resolved by scanning the table heap with
   --  MVCC visibility rules;
   --  in-memory databases fall back to the catalog
   --  row registry. This prevents query integration from depending only on
   --  transient cached rows after reopen.
   --  @param Tx transaction object that scopes the operation.
   --  @param Ref ref argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Resolve_Row
     (Tx  : in out Database.Transactions.Transaction;
      Hit : Search_Result;
      Row : out Database.Rows.Row) return Database.Status.Result;

   --  Perform maintain insert for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row_Id row id argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   procedure Maintain_Insert
     (Tx       : in out Database.Transactions.Transaction;
      Schema   : Database.Schema.Table_Schema;
      Row_Id   : Natural;
      Row      : Database.Rows.Row);

   --  Perform maintain delete for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   procedure Maintain_Delete
     (Tx       : in out Database.Transactions.Transaction;
      Schema   : Database.Schema.Table_Schema;
      Row      : Database.Rows.Row);

   --  Return full text index count for the supplied database state or arguments.
   --  @return Number of items represented by the queried object.
   function Full_Text_Index_Count return Natural;
   --  Return exists for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Exists (Name : Wide_Wide_String) return Boolean;
   --  Return term count for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Number of items represented by the queried object.
   function Term_Count (Name : Wide_Wide_String) return Natural;
   --  Return posting count for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Number of items represented by the queried object.
   function Posting_Count (Name : Wide_Wide_String) return Natural;
   --  Return obsolete posting count for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Number of items represented by the queried object.
   function Obsolete_Posting_Count (Name : Wide_Wide_String) return Natural;
   --  Return max commit version for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Max_Commit_Version return Database.Versioning.Commit_Version;

   --  Select the database-handle-local full-text namespace used by
   --  non-transactional diagnostics/check/vacuum/save/load calls. Transactional
   --  operations select their owning handle automatically.
   --  @param State_Key state key argument supplied to the operation.
   procedure Select_Database (State_Key : Natural);

   --  Clear full-text state for the currently selected database handle only.
   --  @param Tx_Id tx id argument supplied to the operation.
   --  @param Commit_Version commit version argument supplied to the operation.
   procedure Commit_Transaction
     (Tx_Id          : Database.Versioning.Transaction_Id;
      Commit_Version : Database.Versioning.Commit_Version);

   --  Perform rollback transaction for the supplied database state or arguments.
   --  @param Tx_Id tx id argument supplied to the operation.
   procedure Rollback_Transaction
     (Tx_Id : Database.Versioning.Transaction_Id);

   --  Return save for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Save (Path : Wide_Wide_String) return Database.Status.Result;
   --  Return load for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Load
     (DB   : in out Database.Handle;
      Path : Wide_Wide_String) return Database.Status.Result;

   --  Rebuild full-text indexes from persisted index definitions and current
   --  table rows. This is used when the sidecar posting cache is missing or
   --  known stale after WAL replay.
   --  @param DB database handle used by the operation.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Rebuild_From_Catalog
     (DB   : in out Database.Handle;
      Path : Wide_Wide_String) return Database.Status.Result;

   --  Return check index for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Check_Index (Name : Wide_Wide_String) return Database.Status.Result;
   --  Return check index for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Check_Index
     (Tx   : in out Database.Transactions.Transaction;
      Name : Wide_Wide_String) return Database.Status.Result;
   --  Perform vacuum index for the supplied database state or arguments.
   --  @param Name logical name of the object.
   procedure Vacuum_Index (Name : Wide_Wide_String);
   --  Perform vacuum all for the supplied database state or arguments.
   procedure Vacuum_All;

   --  Perform clear for the supplied database state or arguments.
   procedure Clear;

private
   --  Search_Cursor stores the public fields for this database abstraction.
   type Search_Cursor is record
      Results : Search_Result_Vectors.Vector;
      Index   : Natural := 0;
   end record;
end Database.Full_Text;
