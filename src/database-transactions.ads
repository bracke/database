--  Transaction lifecycle, RAII rollback, locking participation, and WAL writes.
with Ada.Containers.Vectors;
with Ada.Finalization;
with Database.Status;
with Database.Storage.Pages;
use type Database.Storage.Pages.Page_Id;
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
   type Transaction is new Ada.Finalization.Limited_Controlled with record
      DB                  : Handle_Access := null;
      Current_State       : Transaction_State := Rolled_Back;
      Current_Mode        : Transaction_Mode := Read_Only;
      Last                : Database.Status.Result := Database.Status.Success;
      Has_Writes          : Boolean := False;
      Before_Image_Ids    : Page_Id_Vectors.Vector;
      Before_Image_Pages  : Page_Vectors.Vector;
      Original_Page_Count : Natural := 0;
      Transaction_Id      : Database.Versioning.Transaction_Id := 0;
      Lock_Held           : Boolean := False;
      Started_At_Version  : Database.Versioning.Commit_Version := 0;
      Ended_At_Version    : Database.Versioning.Commit_Version := 0;
   end record;
end Database.Transactions;
