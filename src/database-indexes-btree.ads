--  Persistent B+ tree operations for primary and secondary indexes.
with Ada.Containers.Vectors;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Pages;
with Database.Transactions;
with Database.Values;

   --  Public nested package `Database.Indexes.BTree`.
package Database.Indexes.BTree is
   --  Row_Reference_Vectors stores ordered row reference values for this package.
   package Row_Reference_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Database.Indexes.Row_Reference);

   --  Range_Bound_Kind enumerates the supported values for this database abstraction.
   type Range_Bound_Kind is (Unbounded, Exclusive, Inclusive);

   --  Range_Bound stores the public fields for this database abstraction.
   type Range_Bound is record
      Kind : Range_Bound_Kind := Unbounded;
      Key  : Database.Values.Value := Database.Values.Null_Value;
   end record;
   --  Public operation `Create`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Allocator allocator argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : out Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Public operation `Insert`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Allocator allocator argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Ref ref argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Insert
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Public operation `Find`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Ref ref argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Find
     (F     : in out Database.Storage.File_IO.File_Handle;
      Root  : Database.Storage.Pages.Page_Id;
      Key   : Database.Values.Value;
      Ref   : out Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Public operation `Insert_Duplicate`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Allocator allocator argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Ref ref argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Insert_Duplicate
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Key       : Database.Values.Value;
      Ref       : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Public operation `Remove_Entry`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Ref ref argument supplied to the operation.
   --  @return Result produced by the function.
   function Remove_Entry
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Public operation `Remove`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Key key value used to identify the row or object.
   --  @return Result produced by the function.
   function Remove
     (Tx   : in out Database.Transactions.Transaction;
      F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value) return Database.Status.Result;

   --  Public operation `Update`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Tx transaction object that scopes the operation.
   --  @param F f argument supplied to the operation.
   --  @param Allocator allocator argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Old_Key old key argument supplied to the operation.
   --  @param New_Key new key argument supplied to the operation.
   --  @param New_Ref new ref argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Update
     (Tx        : in out Database.Transactions.Transaction;
      F         : in out Database.Storage.File_IO.File_Handle;
      Allocator : in out Database.Storage.Free_List.Allocator;
      Root      : in out Database.Storage.Pages.Page_Id;
      Old_Key   : Database.Values.Value;
      New_Key   : Database.Values.Value;
      New_Ref   : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Return all row references whose keys are inside the requested range.
   --  Results preserve ascending key order and include duplicate secondary keys.
   --  @param F f argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @param Low low argument supplied to the operation.
   --  @param High high argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Requested value or optional value according to the package contract.
   function Range_Find
     (F      : in out Database.Storage.File_IO.File_Handle;
      Root   : Database.Storage.Pages.Page_Id;
      Low    : Range_Bound;
      High   : Range_Bound;
      Result : out Row_Reference_Vectors.Vector) return Database.Status.Result;

   --  Public operation `Validate`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Database.Status.Result;
end Database.Indexes.BTree;
