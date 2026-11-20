with Database.Indexes;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;
with Database.Transactions;
with Database.Values;

--  Index maintenance shared by every typed table: reading a row's indexed value, finding a visible row by key,
--  filling an index from its table, and building indexes left unbuilt by earlier versions.
private package Database.Tables.Indexing is

   --  Return the value a row holds in an indexed column.
   --  @param Schema table schema.
   --  @param Row_Value row.
   --  @param Column column id.
   --  @return The value, or Null_Value when the row has no such column.
   function Index_Value
     (Schema    : Database.Schema.Table_Schema;
      Row_Value : Database.Rows.Row;
      Column    : Natural) return Database.Values.Value;

   --  Return the column a table's primary index is keyed on.
   --  @param Schema table schema.
   --  @return Column id, or Natural'Last for a table without a primary key.
   function Primary_Column (Schema : Database.Schema.Table_Schema) return Natural;

   --  Find the row visible to Tx whose Column equals Key through the index at Root. A built index is authoritative;
   --  an unbuilt one (see BTree.Is_Built) is bypassed by scanning the table.
   --  @param Tx transaction whose snapshot decides visibility.
   --  @param DB database.
   --  @param Schema table schema.
   --  @param Root root page of the index on Column.
   --  @param Key value looked for.
   --  @param Column indexed column id.
   --  @param Ref reference of the visible row.
   --  @return Status result; Not_Found when no visible row has Key.
   function Visible_Ref_For_Key
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Root   : Database.Storage.Pages.Page_Id;
      Key    : Database.Values.Value;
      Column : Natural;
      Ref    : out Database.Indexes.Row_Reference) return Database.Status.Result;

   --  Test whether a row visible to Tx has Key in Column.
   --  @param Tx transaction whose snapshot decides visibility.
   --  @param DB database.
   --  @param Schema table schema.
   --  @param Root root page of the index on Column.
   --  @param Key value looked for.
   --  @param Column indexed column id.
   --  @return True when such a row exists.
   function Any_Visible_Key
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Root   : Database.Storage.Pages.Page_Id;
      Key    : Database.Values.Value;
      Column : Natural) return Boolean;

   --  Add an entry for every stored row that is not marked deleted, the transaction's own uncommitted rows included,
   --  to the empty index at Root. Null values are not indexed.
   --  @param Tx write transaction.
   --  @param DB persistent database.
   --  @param Schema table schema.
   --  @param Root root page of an empty built index.
   --  @param Column indexed column id.
   --  @param Unique whether two rows with the same value are rejected.
   --  @return Status result; Duplicate_Key for a repeated value of a unique index, and the key validation failure
   --  for a value that cannot be indexed.
   function Fill
     (Tx     : in out Database.Transactions.Transaction;
      DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Root   : Database.Storage.Pages.Page_Id;
      Column : Natural;
      Unique : Boolean) return Database.Status.Result;

   --  Build every unbuilt index of a table before a change, recording a replaced root in the catalog.
   --  @param Tx write transaction.
   --  @param DB persistent database.
   --  @param S table schema; replaced roots are updated in it.
   --  @return Status result describing whether the operation succeeded.
   function Ensure_Indexes
     (Tx : in out Database.Transactions.Transaction;
      DB : in out Database.Handle;
      S  : in out Database.Schema.Table_Schema) return Database.Status.Result;

end Database.Tables.Indexing;
