--  Read-only diagnostic counters for storage, tables, and indexes.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Transactions;
with Database.Schema;
with Database.Indexes;

   --  Public nested package `Database.Diagnostics`.
package Database.Diagnostics is
   use Ada.Strings.Wide_Wide_Unbounded;
   --  Public operation `Page_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Number of items represented by the queried object.
   function Page_Count (Tx : in out Database.Transactions.Transaction) return Natural;
   --  Public operation `Free_Page_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Number of items represented by the queried object.
   function Free_Page_Count (Tx : in out Database.Transactions.Transaction) return Natural;
   --  Public operation `Database_Size`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Database_Size (Tx : in out Database.Transactions.Transaction) return Natural;
   --  Public operation `Table_Row_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Number of items represented by the queried object.
   function Table_Row_Count
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Natural;
   --  Public operation `Table_Page_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Number of items represented by the queried object.
   function Table_Page_Count
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Natural;
   --  Public operation `Index_Page_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Number of items represented by the queried object.
   function Index_Page_Count
     (Tx    : in out Database.Transactions.Transaction;
      Index : Database.Indexes.Index_Metadata) return Natural;
   --  Public operation `Index_Depth`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Index_Depth
     (Tx    : in out Database.Transactions.Transaction;
      Index : Database.Indexes.Index_Metadata) return Natural;

   --  Return full text index count for the supplied database state or arguments.
   --  @return Number of items represented by the queried object.
   function Full_Text_Index_Count return Natural;
   --  Return full text term count for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Number of items represented by the queried object.
   function Full_Text_Term_Count (Name : Wide_Wide_String) return Natural;
   --  Return full text posting count for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Number of items represented by the queried object.
   function Full_Text_Posting_Count (Name : Wide_Wide_String) return Natural;
   --  Return full text obsolete posting count for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Number of items represented by the queried object.
   function Full_Text_Obsolete_Posting_Count (Name : Wide_Wide_String) return Natural;

   --  Safe encryption diagnostics. These expose only mode/version
   --  metadata and never expose key bytes, derived secrets, nonces, tags, or
   --  decrypted page contents.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Encryption_Enabled (DB : Database.Handle) return Boolean;
   --  Return encryption format version for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Encryption_Format_Version (DB : Database.Handle) return Natural;
   --  Return wal encryption enabled for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function WAL_Encryption_Enabled (DB : Database.Handle) return Boolean;
end Database.Diagnostics;
