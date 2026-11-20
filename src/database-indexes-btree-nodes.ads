with Ada.Containers.Vectors;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Transactions;
with Database.Values;

--  The on-disk form of a B+ tree node and of its keys.
--
--  A node is one page: a leaf (BTree_Leaf_Page) holds entries in ascending (key, row reference) order and links to
--  its right sibling through the page's next-page field; an internal node (BTree_Internal_Page) holds a first child
--  and separators, each with the child that holds the entries at or above it. Every node payload starts with a
--  format marker, so a root page that was allocated but never written by this format is recognized as unbuilt.
--
--  Payload layout: marker "BPT1", node type (0 leaf, 1 internal), entry count (u16), first child (u32), then per
--  entry the key length (u16), the encoded key, the row reference page and slot (u32 each), and for internal nodes
--  the child page (u32). Integers are big-endian.
private package Database.Indexes.BTree.Nodes is
   --  The on-disk form of a B+ tree node and of its keys.

   --  One entry: a leaf entry, or a separator of an internal node.
   --  @field Key Indexed value.
   --  @field Ref Row reference; together with Key it orders entries, so equal keys are adjacent and distinct.
   --  @field Child Internal nodes only: the child holding the entries at or above this separator.
   type Item is record
      Key   : Database.Values.Value := Database.Values.Null_Value;
      Ref   : Database.Indexes.Row_Reference := Database.Indexes.Invalid_Row_Reference;
      Child : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
   end record;

   --  Entries of one node in ascending order.
   package Item_Vectors is new Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Item);

   --  One decoded node.
   --  @field Id Page holding the node.
   --  @field Leaf Whether the node is a leaf.
   --  @field First Internal nodes only: the child holding the entries below the first separator.
   --  @field Next Leaves only: the right sibling, or Invalid_Page_Id for the last leaf.
   --  @field Items Entries in ascending order.
   type Node is record
      Id    : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Leaf  : Boolean := True;
      First : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Next  : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Items : Item_Vectors.Vector;
   end record;

   --  Longest encoded key an entry may hold, so that every node can hold at least three entries.
   Max_Key_Bytes : constant := 1_000;

   --  Return the length of a key's encoding.
   --  @param Key Supported key value.
   --  @return Encoded length in bytes.
   function Key_Size (Key : Database.Values.Value) return Natural;

   --  Compare two entries by key, then by row reference.
   --  @param Left_Key Left key.
   --  @param Left_Ref Left row reference.
   --  @param Right_Key Right key.
   --  @param Right_Ref Right row reference.
   --  @param Order Less, Equal, or Greater.
   --  @return Success, or the key comparison failure.
   function Compare
     (Left_Key  : Database.Values.Value;
      Left_Ref  : Database.Indexes.Row_Reference;
      Right_Key : Database.Values.Value;
      Right_Ref : Database.Indexes.Row_Reference;
      Order     : out Database.Indexes.Ordering) return Database.Status.Result;

   --  Test whether a root page holds a node of this format, rather than a root allocated and never written.
   --  @param F Database file.
   --  @param Id Root page.
   --  @return True when the page carries the format marker.
   function Is_Built (F : in out Database.Storage.File_IO.File_Handle; Id : Database.Storage.Pages.Page_Id)
      return Boolean;

   --  Read and decode one node.
   --  @param F Database file.
   --  @param Id Node page.
   --  @param N Decoded node.
   --  @return Success, or Corrupt_Index when the page is not a node of this format.
   function Load
     (F  : in out Database.Storage.File_IO.File_Handle;
      Id : Database.Storage.Pages.Page_Id;
      N  : out Node) return Database.Status.Result;

   --  Test whether a node's encoding fits one page.
   --  @param N Node.
   --  @return True when it fits.
   function Fits (N : Node) return Boolean;

   --  Return the encoded size of one entry.
   --  @param N Node the entry belongs to; internal entries also hold a child.
   --  @param Entry_Item Entry.
   --  @return Bytes.
   function Item_Size (N : Node; Entry_Item : Item) return Natural;

   --  Encode a node and write it through the transaction, so it is logged and rolled back with it. A transaction of a
   --  database without a file (an in-memory one used to drive the tree directly) writes F itself.
   --  @param Tx Write transaction.
   --  @param F Database file holding the tree.
   --  @param N Node that fits one page.
   --  @return Success, or the write failure.
   function Store
     (Tx : in out Database.Transactions.Transaction;
      F  : in out Database.Storage.File_IO.File_Handle;
      N  : Node) return Database.Status.Result;
end Database.Indexes.BTree.Nodes;
