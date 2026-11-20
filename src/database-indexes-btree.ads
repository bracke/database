--  Persistent B+ tree operations for primary and secondary indexes.
--
--  Each index is a B+ tree of pages whose root page never moves, so catalog references stay valid. Entries are
--  ordered by key and then by row reference, so equal keys are adjacent; leaves are linked for range scans. Every
--  change is written through the transaction, so it is logged in the WAL and rolled back with the transaction.
--  Nodes are split when full and never merged; an emptied leaf stays in the tree.
with Ada.Containers.Vectors;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Transactions;
with Database.Values;

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
   --  Write operations take only the transaction: they change the tree in the transaction's database, read its
   --  pages through that database's file, and allocate and free pages through the transaction, so a rollback undoes
   --  them completely. They need a write transaction of a persistent database. Read operations take a file, so a
   --  database opened read-only can use them.

   --  Allocate a root page and make it an empty tree.
   --  @param Tx write transaction.
   --  @param Root new root page.
   --  @return Status result describing whether the operation succeeded.
   function Create
     (Tx   : in out Database.Transactions.Transaction;
      Root : out Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Add an entry to a unique index. An Invalid_Page_Id root is created first; an unbuilt index is left as it is.
   --  @param Tx write transaction.
   --  @param Root root page of the index.
   --  @param Key indexed value.
   --  @param Ref row reference.
   --  @return Status result; Duplicate_Key when the index already holds Key, Row_Too_Large for a key longer than
   --  1,000 bytes when encoded.
   function Insert
     (Tx   : in out Database.Transactions.Transaction;
      Root : in out Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Return the reference of the first entry with Key.
   --  @param F database file.
   --  @param Root root page of the index.
   --  @param Key indexed value.
   --  @param Ref reference of the first entry with Key.
   --  @return Status result; Key_Not_Found when no entry has Key, Not_Found for an unbuilt index.
   function Find
     (F     : in out Database.Storage.File_IO.File_Handle;
      Root  : Database.Storage.Pages.Page_Id;
      Key   : Database.Values.Value;
      Ref   : out Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Add an entry to a non-unique index; an entry that is already present is left as it is. An Invalid_Page_Id root
   --  is created first; an unbuilt index is left as it is.
   --  @param Tx write transaction.
   --  @param Root root page of the index.
   --  @param Key indexed value.
   --  @param Ref row reference.
   --  @return Status result; Row_Too_Large for a key longer than 1,000 bytes when encoded.
   function Insert_Duplicate
     (Tx   : in out Database.Transactions.Transaction;
      Root : in out Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Remove one entry; a missing entry, or an unbuilt index, is left as it is.
   --  @param Tx write transaction.
   --  @param Root root page of the index.
   --  @param Key indexed value.
   --  @param Ref row reference.
   --  @return Status result describing whether the operation succeeded.
   function Remove_Entry
     (Tx   : in out Database.Transactions.Transaction;
      Root : Database.Storage.Pages.Page_Id;
      Key  : Database.Values.Value;
      Ref  : Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Return all row references whose keys are inside the requested range.
   --  Results preserve ascending key order and include duplicate secondary keys.
   --  @param F database file.
   --  @param Root root page of the index.
   --  @param Low lower bound.
   --  @param High upper bound.
   --  @param Result references in ascending (key, reference) order.
   --  @return Status result; Not_Found for an unbuilt index, and the comparison failure when a bound cannot be
   --  compared with the index keys.
   function Range_Find
     (F      : in out Database.Storage.File_IO.File_Handle;
      Root   : Database.Storage.Pages.Page_Id;
      Low    : Range_Bound;
      High   : Range_Bound;
      Result : out Row_Reference_Vectors.Vector) return Database.Status.Result;

   --  Check an index's structure: every node is readable and in strictly ascending order, every entry of a subtree
   --  lies between the separators around it, all leaves are at the same depth and chained left to right, and no page
   --  is reached twice. An unwritten root (see Is_Unwritten) is valid; it is bypassed until it is rebuilt.
   --  @param F database file.
   --  @param Root root page of the index.
   --  @return Status result; Corrupt_Index for the first violation.
   function Validate
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Page_Id_Vectors lists the pages of one B+ tree.
   package Page_Id_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Database.Storage.Pages.Page_Id);

   --  Test whether an index root holds a tree of the persistent format. A root allocated by an earlier version of
   --  this package, which kept index entries only in memory, holds nothing: such an index is unbuilt until it is
   --  reset and filled from its table. Lookups in an unbuilt index fail with Not_Found, so callers fall back to the
   --  table; changes to it are ignored.
   --  @param F database file.
   --  @param Root root page of the index.
   --  @return True when the index is built.
   function Is_Built
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Boolean;

   --  Test whether an unbuilt root is a leaf page that was allocated and never written, as earlier versions left
   --  every root; only such a page may be cleared in place. Any other unbuilt root, which a file written by an
   --  earlier version can hold after a rollback, must be replaced by a new root instead.
   --  @param F database file.
   --  @param Root root page of the index.
   --  @return True for an empty, never-written leaf page.
   function Is_Unwritten
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Boolean;

   --  Make Root an empty built index, keeping its page, so the caller can fill it from the table. Pages of the tree
   --  below a built root are freed.
   --  @param Tx write transaction.
   --  @param Root root page of a built or unwritten index.
   --  @return Status result; Corrupt_Index for any other root.
   function Clear
     (Tx   : in out Database.Transactions.Transaction;
      Root : Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  List every page of an index: its root, internal nodes, and leaves.
   --  @param F database file.
   --  @param Root root page of the index.
   --  @param Pages pages in breadth-first order; only Root for an unbuilt index.
   --  @return Status result; Corrupt_Index when a node is unreadable or reached twice.
   function Pages_Of
     (F     : in out Database.Storage.File_IO.File_Handle;
      Root  : Database.Storage.Pages.Page_Id;
      Pages : out Page_Id_Vectors.Vector) return Database.Status.Result;
end Database.Indexes.BTree;
