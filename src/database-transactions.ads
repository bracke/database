--  Transaction lifecycle, RAII rollback, locking participation, and WAL writes.
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Finalization;
with Database.Status;
with Database.Storage.Pages;
use type Database.Storage.Pages.Page;
with Database.Versioning;

   --  Public nested package `Database.Transactions`.
package Database.Transactions is
   --  Public type `Transaction_Mode`.
   type Transaction_Mode is (Read_Only, Read_Write);
   --  Public type `Transaction_State`.
   type Transaction_State is (Active, Committing, Committed, Rolling_Back, Rolled_Back, Failed);
   --  Public type `Transaction`.
   type Transaction is new Ada.Finalization.Limited_Controlled with private;

   --  Start a read-only transaction. The transaction holds a shared read lock
   --  until Commit, Rollback, or Finalize.
   --  @param DB database handle used by the operation.
   --  @param Tx transaction object that scopes the operation.
   procedure Begin_Read (DB : in out Database.Handle; Tx : out Transaction);

   --  Ensure freshly assigned transaction ids stay strictly above Highest.
   --  Called during open-time recovery with the largest transaction id still
   --  referenced by any persisted row, so a restarted process never reuses an
   --  id that appears in Created_By_Tx / Deleted_By_Tx (which would alias the
   --  process-global MVCC lifecycle map). Only ever raises the counter.
   procedure Reserve_Ids_Through (Highest : Natural);

   --  Start a read-write transaction. The transaction holds the exclusive
   --  writer lock until Commit, Rollback, or Finalize.
   --  @param DB database handle used by the operation.
   --  @param Tx transaction object that scopes the operation.
   procedure Begin_Write (DB : in out Database.Handle; Tx : out Transaction);
   --  Nonblocking read transaction start. Granted is False and Result (Tx)
   --  is Transaction_Conflict when the read lock is unavailable.
   --  @param DB database handle used by the operation.
   --  @param Tx transaction object that scopes the operation.
   --  @param Granted granted argument supplied to the operation.
   procedure Try_Begin_Read
     (DB      : in out Database.Handle;
      Tx      : out Transaction;
      Granted : out Boolean);
   --  Nonblocking write transaction start. Granted is False and Result (Tx)
   --  is Transaction_Conflict when the writer lock is unavailable.
   --  @param DB database handle used by the operation.
   --  @param Tx transaction object that scopes the operation.
   --  @param Granted granted argument supplied to the operation.
   procedure Try_Begin_Write
     (DB      : in out Database.Handle;
      Tx      : out Transaction;
      Granted : out Boolean);

   --  Public operation `Commit`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Commit (Tx : in out Transaction) return Database.Status.Result;
   --  Public operation `Rollback`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Rollback (Tx : in out Transaction) return Database.Status.Result;
   --  Public operation `Commit`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   procedure Commit (Tx : in out Transaction);
   --  Public operation `Rollback`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   procedure Rollback (Tx : in out Transaction);

   --  Public operation `Is_Active`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Active (Tx : Transaction) return Boolean;
   --  Public operation `Can_Read`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Can_Read (Tx : Transaction) return Boolean;
   --  Public operation `Can_Write`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Can_Write (Tx : Transaction) return Boolean;
   --  Public operation `Result`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Result (Tx : Transaction) return Database.Status.Result;
   --  Public operation `State`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function State (Tx : Transaction) return Transaction_State;
   --  Public operation `Mode`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Mode (Tx : Transaction) return Transaction_Mode;
   --  Public operation `Id`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Id (Tx : Transaction) return Database.Versioning.Transaction_Id;
   --  Public operation `Snapshot_Version`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Snapshot_Version (Tx : Transaction) return Database.Versioning.Commit_Version;
   --  Public operation `Start_Version`. Alias for Snapshot_Version.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Start_Version (Tx : Transaction) return Database.Versioning.Commit_Version;
   --  Public operation `Ended_Version`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Ended_Version (Tx : Transaction) return Database.Versioning.Commit_Version;
   --  Public operation `Commit_Version`. The commit version assigned at successful commit, or 0 before commit.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Commit_Version (Tx : Transaction) return Database.Versioning.Commit_Version;
   --  Public operation `Owning_Database`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @return Result produced by the function.
   function Owning_Database (Tx : in out Transaction) return access Database.Handle;

   --  Public operation `Write_Page`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param Page page argument supplied to the operation.
   --  @return Result produced by the function.
   function Write_Page
     (Tx   : in out Transaction;
      Page : Database.Storage.Pages.Page) return Database.Status.Result;

   --  Allocate an empty page of Kind and write it through the transaction, so a rollback returns a reused free page
   --  to the free list and removes a page added at the end of the file.
   --  @param Tx write transaction of a persistent database.
   --  @param Kind page kind of the new page.
   --  @param Page the written empty page.
   --  @return Status result describing whether the operation succeeded.
   function Allocate_Page
     (Tx   : in out Transaction;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result;

   --  Rewrite a page as free through the transaction and offer it to the allocator.
   --  @param Tx write transaction of a persistent database.
   --  @param Id page that is no longer used.
   --  @return Status result describing whether the operation succeeded.
   function Free_Page
     (Tx : in out Transaction;
      Id : Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Return the last page of a table heap as this transaction last appended to it, so an append need not walk the
   --  page chain again. Only this transaction changes the heap while it is active, so the hint stays exact; it ends
   --  with the transaction.
   --  @param Tx transaction object that scopes the operation.
   --  @param First first page of the table heap.
   --  @return Last page, or Invalid_Page_Id when this transaction has not appended to the heap.
   function Heap_Tail
     (Tx    : Transaction;
      First : Database.Storage.Pages.Page_Id) return Database.Storage.Pages.Page_Id;

   --  Record the last page of a table heap after an append.
   --  @param Tx transaction object that scopes the operation.
   --  @param First first page of the table heap.
   --  @param Last page the row was appended to.
   procedure Set_Heap_Tail
     (Tx    : in out Transaction;
      First : Database.Storage.Pages.Page_Id;
      Last  : Database.Storage.Pages.Page_Id);

   --  Finalize performs the documented database operation.
   --  @param Tx transaction object that scopes the operation.
   overriding procedure Finalize (Tx : in out Transaction);

private
   --  Public type `Handle_Access`.
   type Handle_Access is access all Database.Handle;
   --  Private page id vector used to track transaction before-images.
   package Page_Id_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Database.Storage.Pages.Page_Id);
   --  Private page vector used for in-memory rollback before-images.
   package Page_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Database.Storage.Pages.Page);

   --  Public type `Transaction`.
   --  Last heap page per table heap, by first page.
   package Heap_Tail_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Database.Storage.Pages.Page_Id, Element_Type => Database.Storage.Pages.Page_Id,
      "<" => Database."<", "=" => Database."=");

   type Transaction is new Ada.Finalization.Limited_Controlled with record
      DB                  : Handle_Access := null;
      Current_State       : Transaction_State := Rolled_Back;
      Current_Mode        : Transaction_Mode := Read_Only;
      Last                : Database.Status.Result := Database.Status.Success;
      Has_Writes          : Boolean := False;
      Before_Image_Ids    : Page_Id_Vectors.Vector;
      Before_Image_Pages  : Page_Vectors.Vector;
      Heap_Tails          : Heap_Tail_Maps.Map;
      --  The catalog page as the transaction found it. The catalog is saved outside the page log, so a rollback
      --  restores it from here.
      Catalog_Before      : Database.Storage.Pages.Page;
      Catalog_Saved       : Boolean := False;
      Original_Page_Count : Natural := 0;
      Transaction_Id      : Database.Versioning.Transaction_Id := 0;
      Lock_Held           : Boolean := False;
      Started_At_Version  : Database.Versioning.Commit_Version := 0;
      Ended_At_Version    : Database.Versioning.Commit_Version := 0;
   end record;
end Database.Transactions;
