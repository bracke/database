--  Internal invariant validators used by hardening, recovery, and stress tests.
with Database.Status;
with Database.Storage.Pages;
with Database.Storage.File_IO;
with Database.Log_Sequence;
with Database.Backup_Format;
with Database.Indexes.BTree;
with Database.WAL;
with Database.MVCC;
with Database.Schema;
with Database.Versioning;
--  Deep invariant validation entry points.
package Database.Invariant_Checks is
   --  Integer_Array defines a public database type used by this package.
   type Integer_Array is array (Positive range <>) of Integer;
   --  Page_Id_Array defines a public database type used by this package.
   type Page_Id_Array is array (Positive range <>) of Database.Storage.Pages.Page_Id;
   --  LSN_Array defines a public database type used by this package.
   type LSN_Array is array (Positive range <>) of Database.Log_Sequence.Log_Sequence_Number;

   --  Version_Node stores the public fields for this database abstraction.
   type Version_Node is record
      Transaction : Database.Versioning.Transaction_Id := 0;
      Begin_Version : Database.Versioning.Commit_Version := 0;
      End_Version : Database.Versioning.Commit_Version := Database.Versioning.No_Version;
      Deleted : Boolean := False;
   end record;
   --  Version_Node_Array defines a public database type used by this package.
   type Version_Node_Array is array (Positive range <>) of Version_Node;

   --  BTree_Link stores the public fields for this database abstraction.
   type BTree_Link is record
      Parent : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Child  : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
   end record;
   --  BTree_Link_Array defines a public database type used by this package.
   type BTree_Link_Array is array (Positive range <>) of BTree_Link;

   --  Index_Reference stores the public fields for this database abstraction.
   type Index_Reference is record
      Index_Page : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
      Heap_Page  : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
   end record;
   --  Index_Reference_Array defines a public database type used by this package.
   type Index_Reference_Array is array (Positive range <>) of Index_Reference;

   --  Check_Kind defines a public database type used by this package.
   type Check_Kind is
     (BTree_Key_Order,
      BTree_Parent_Child_Links,
      Page_Header,
      Page_Chain,
      MVCC_Version_Chain,
      WAL_LSN_Order,
      Free_List_Links,
      Catalog_Metadata,
      Index_References,
      Snapshot_References,
      Backup_Manifest,
      Import_Structure,
      Encryption_Metadata,
      Table_Heap_Traversal,
      Free_Page_Set,
      Deep_Database_Traversal);

   --  Check_Report stores the public fields for this database abstraction.
   type Check_Report is record
      Result : Database.Status.Result := Database.Status.Success;
      Checked_Items : Natural := 0;
      Failed_Items : Natural := 0;
   end record;

   --  Return pass for the supplied database state or arguments.
   --  @param Items items argument supplied to the operation.
   --  @return Result produced by the function.
   function Pass (Items : Natural := 0) return Check_Report;
   --  Return fail for the supplied database state or arguments.
   --  @param Kind kind selector controlling the operation.
   --  @param Message message argument supplied to the operation.
   --  @return Result produced by the function.
   function Fail (Kind : Check_Kind; Message : Wide_Wide_String) return Check_Report;

   --  Return validate sorted keys for the supplied database state or arguments.
   --  @param Keys keys argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Sorted_Keys (Keys : Integer_Array) return Check_Report
     with Post => Validate_Sorted_Keys'Result.Checked_Items = Keys'Length;
   --  Return validate lsn order for the supplied database state or arguments.
   --  @param Previous previous argument supplied to the operation.
   --  @param Current current argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_LSN_Order
     (Previous : Database.Log_Sequence.Log_Sequence_Number;
      Current  : Database.Log_Sequence.Log_Sequence_Number) return Check_Report;
   --  Return validate lsn sequence for the supplied database state or arguments.
   --  @param Items items argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_LSN_Sequence (Items : LSN_Array) return Check_Report;
   --  Return validate wal file for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_WAL_File (Database_Path : Wide_Wide_String) return Check_Report;
   --  Return validate page header for the supplied database state or arguments.
   --  @param Page page argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Page_Header (Page : Database.Storage.Pages.Page) return Check_Report;

   --  Traverse every page currently present in a persistent file and validate
   --  page headers, page ids, page kinds, and duplicate references. This is the
   --  concrete file-level invariant hook used by crash/stress tests.
   --  @param F f argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Page_File
     (F : in out Database.Storage.File_IO.File_Handle) return Check_Report;
   --  Return validate page chain for the supplied database state or arguments.
   --  @param Pages pages argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Page_Chain (Pages : Page_Id_Array) return Check_Report;
   --  Return validate free list links for the supplied database state or arguments.
   --  @param Pages pages argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Free_List_Links (Pages : Page_Id_Array) return Check_Report;
   --  Return validate btree links for the supplied database state or arguments.
   --  @param Links links argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_BTree_Links (Links : BTree_Link_Array) return Check_Report;
   --  Return validate btree for the supplied database state or arguments.
   --  @param F f argument supplied to the operation.
   --  @param Root root argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_BTree
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Check_Report;

   --  Validate every reachable heap page for a table, including page-chain
   --  bounds/cycles, slot headers, MVCC row metadata, record payload decoding,
   --  and row/schema compatibility.
   --  @param F f argument supplied to the operation.
   --  @param First_Page first page argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Table_Heap_Deep
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema) return Check_Report;

   --  Traverse the complete physical file and validate the free-page set.
   --  Reserved pages must not be free;
   --  free pages must have matching ids and
   --  legal next links;
   --  free pages must not be reachable through table/index
   --  chains checked elsewhere.
   --  @param F f argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Free_Page_Set
     (F : in out Database.Storage.File_IO.File_Handle) return Check_Report;
   --  Return validate mvcc chain for the supplied database state or arguments.
   --  @param Versions versions argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_MVCC_Chain (Versions : Version_Node_Array) return Check_Report;
   --  Return validate active snapshot for the supplied database state or arguments.
   --  @param Snapshot snapshot argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Active_Snapshot
     (Snapshot : Database.Versioning.Commit_Version) return Check_Report;
   --  Return validate index references for the supplied database state or arguments.
   --  @param Refs refs argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Index_References (Refs : Index_Reference_Array) return Check_Report;
   --  Return validate backup manifest for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @param Manifest manifest argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Backup_Manifest
     (Backup_Path : Wide_Wide_String;
      Manifest    : Database.Backup_Format.Manifest) return Check_Report;
   --  Return validate import header for the supplied database state or arguments.
   --  @param Magic magic argument supplied to the operation.
   --  @param Version version argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Import_Header
     (Magic : Wide_Wide_String;
      Version : Natural) return Check_Report;
   --  Return validate encryption metadata for the supplied database state or arguments.
   --  @param Format_Version format version argument supplied to the operation.
   --  @param Key_Id key id argument supplied to the operation.
   --  @param Authenticated authenticated argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Encryption_Metadata
     (Format_Version : Natural;
      Key_Id         : Natural;
      Authenticated  : Boolean) return Check_Report;
   --  Engine-wide invariant pass. It traverses the
   --  persistent page file, WAL, catalog tables, all catalogued indexes,
   --  full-text definitions, active MVCC horizon, and encryption metadata
   --  reachable from an open database handle.
   --  @param DB database handle used by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Database
     (DB : in out Database.Handle) return Check_Report;

   --  Return combine for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Combine (Left, Right : Check_Report) return Check_Report;
end Database.Invariant_Checks;
