--  Persistent table heap row append, scan, read, delete, and validation operations.
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Pages;
with Database.Transactions;
with Database.Indexes;
with Database.Versioning;

   --  Public nested package `Database.Storage.Table_Heap`.
package Database.Storage.Table_Heap is
   --  Public type `Heap_Cursor`.
   type Heap_Cursor is record
      Current_Page : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Slot_Offset  : Natural := 0;
      Has_Row      : Boolean := False;
      Row          : Database.Rows.Row;
   end record;

   --  Public operation `Create_Heap`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param Allocator allocator argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create_Heap
     (F          : in out Database.Storage.File_IO.File_Handle;
      Allocator  : in out Database.Storage.Free_List.Allocator;
      First_Page : out Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Public operation `Append_Row`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Allocator allocator argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @param Ref ref argument supplied to the operation.
   --  @return Result produced by the function.
   function Append_Row
     (Tx         : in out Database.Transactions.Transaction;
      F          : in out Database.Storage.File_IO.File_Handle;
      Allocator  : in out Database.Storage.Free_List.Allocator;
      First_Page : in out Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema;
      Row        : Database.Rows.Row;
      Ref        : out Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Public operation `Read_At`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @param Ref ref argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Read_At
     (F      : in out Database.Storage.File_IO.File_Handle;
      Ref    : Database.Indexes.Row_Reference;
      Schema : Database.Schema.Table_Schema;
      Row    : out Database.Rows.Row) return Database.Status.Result;

   --  MVCC-aware row read. Invisible versions return Not_Found.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Ref ref argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Read_At
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Ref    : Database.Indexes.Row_Reference;
      Schema : Database.Schema.Table_Schema;
      Row    : out Database.Rows.Row) return Database.Status.Result;

   --  Public operation `Scan_First`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Cursor cursor argument supplied to the operation.
   --  @return Result produced by the function.
   function Scan_First
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema;
      Cursor     : out Heap_Cursor) return Database.Status.Result;

   --  MVCC-aware scan start. Invisible versions are skipped.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Cursor cursor argument supplied to the operation.
   --  @return Result produced by the function.
   function Scan_First
     (Tx         : in out Database.Transactions.Transaction;
      F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema;
      Cursor     : out Heap_Cursor) return Database.Status.Result;

   --  Public operation `Scan_Next`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Cursor cursor argument supplied to the operation.
   --  @return Result produced by the function.
   function Scan_Next
     (F      : in out Database.Storage.File_IO.File_Handle;
      Schema : Database.Schema.Table_Schema;
      Cursor : in out Heap_Cursor) return Database.Status.Result;

   --  MVCC-aware scan advance. Invisible versions are skipped.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Cursor cursor argument supplied to the operation.
   --  @return Result produced by the function.
   function Scan_Next
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Schema : Database.Schema.Table_Schema;
      Cursor : in out Heap_Cursor) return Database.Status.Result;

   --  Public operation `Delete_At`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Cursor cursor argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Delete_At
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Cursor : Heap_Cursor) return Database.Status.Result;

   --  Public operation `Validate_Table_Heap`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param F f argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Table_Heap
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema) return Database.Status.Result;

   --  Public operation `Validate_Row_Slots`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param Page page argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Row_Slots
     (Page : Database.Storage.Pages.Page) return Database.Status.Result;

   --  Public operation `Validate_Row_Payloads`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param F f argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Row_Payloads
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema) return Database.Status.Result;

   --  Return the highest committed row version recorded in a heap chain.
   function Max_Commit_Version
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id) return Natural;
end Database.Storage.Table_Heap;
