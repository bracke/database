--  Integrity checking for catalog, heaps, indexes, pages, and free-list state.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Schema;
with Database.Indexes;
with Database.Full_Text;
with Database.Storage.Pages;
with Database.Transactions;

   --  Public nested package `Database.Check`.
package Database.Check is
   use type Database.Storage.Pages.Page_Id;
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Public type `Check_Error_Kind`.
   type Check_Error_Kind is
     (Invalid_Page,
      Corrupt_Page,
      Missing_Page,
      Orphan_Page,
      Invalid_Index,
      Invalid_Catalog,
      Invalid_Free_List,
      Invalid_Row,
      Invalid_Row_Reference,
      Duplicate_Primary_Key,
      Broken_Index_Reference,
      Invalid_Full_Text_Index,
      Invalid_Encryption_Metadata,
      Invalid_Extension_Metadata,
      Broken_Version_Chain,
      Invalid_Visibility_Metadata,
      Orphaned_Row_Version,
      Invalid_WAL,
      Invalid_Backup_Manifest,
      Invalid_Import_Structure,
      Schema_Error,
      Internal_Error);

   --  Public type `Check_Error`.
   type Check_Error is record
      Kind    : Check_Error_Kind := Internal_Error;
      Message : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Page    : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
   end record;

   --  Public nested package `Error_Vectors`.
   package Error_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Check_Error);
   --  Public type `Error_Vector`.
   subtype Error_Vector is Error_Vectors.Vector;

   --  Public type `Check_Result`.
   type Check_Result is record
      Success : Boolean := True;
      Errors  : Error_Vector;
   end record;

   --  Public operation `Add_Error`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Result output value populated by the operation.
   --  @param Kind kind selector controlling the operation.
   --  @param Message message argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   procedure Add_Error
     (Result  : in out Check_Result;
      Kind    : Check_Error_Kind;
      Message : Wide_Wide_String;
      Page    : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id);

   --  Public operation `Check_Database`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Check_Database
     (Tx : in out Database.Transactions.Transaction) return Check_Result;

   --  Public operation `Check_Catalog`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Check_Catalog
     (Tx : in out Database.Transactions.Transaction) return Check_Result;

   --  Public operation `Check_Table`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return Result produced by the function.
   function Check_Table
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Check_Result;

   --  Public operation `Check_Index`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Check_Index
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema;
      Index  : Database.Indexes.Index_Metadata) return Check_Result;

   --  Return check full text index for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Check_Full_Text_Index
     (Tx   : in out Database.Transactions.Transaction;
      Name : Wide_Wide_String) return Check_Result;

   --  Validate safe encryption metadata consistency without exposing secrets.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Check_Encryption_Metadata
     (Tx : in out Database.Transactions.Transaction) return Check_Result;

   --  Validate the WAL artifact for a persistent database path. This is a
   --  Corruption-detection entry point and reports malformed WAL
   --  headers, invalid ordering, impossible payload lengths, and complete
   --  corrupt frames as check errors instead of exceptions.
   --  @param Database_Path database path whose .wal artifact is validated.
   --  @return Structured check result.
   function Check_WAL
     (Database_Path : Wide_Wide_String) return Check_Result;

   --  Read and validate a physical backup manifest and the durable artifacts
   --  referenced by that manifest.
   --  @param Backup_Path physical backup directory.
   --  @return Structured check result.
   function Check_Backup_Manifest
     (Backup_Path : Wide_Wide_String) return Check_Result;

   --  Validate logical import header metadata before accepting import input.
   --  @param Header logical export/import header string.
   --  @param Version declared import format version.
   --  @return Structured check result.
   function Check_Import_Header
     (Header  : Wide_Wide_String;
      Version : Natural) return Check_Result;

   --  Validate serialized or externally supplied encryption metadata before
   --  accepting an encrypted artifact. This overload is intentionally separate
   --  from the transaction-scoped database metadata check so hardening callers
   --  can reject malformed metadata before opening an artifact.
   --  @param Format_Version declared encrypted-artifact metadata version.
   --  @param Key_Id declared non-secret key identifier.
   --  @param Authenticated true only after metadata/authentication verification.
   --  @return Structured check result.
   function Check_Encryption_Metadata
     (Format_Version : Natural;
      Key_Id         : Natural;
      Authenticated  : Boolean) return Check_Result;

   --  Return check extension metadata for the supplied database state or arguments.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Check_Extension_Metadata
     (Tx : in out Database.Transactions.Transaction) return Check_Result;
end Database.Check;
