--  Append-only physical write-ahead log used by persistent transactions.
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Log_Sequence;
with Ada.Containers.Ordered_Maps;
with Ada.Streams.Stream_IO;
with Ada.Strings.Wide_Wide_Unbounded;

--  Write-ahead log subsystem namespace.
package Database.WAL is
   --  WAL_Handle defines a public database type used by this package.
   type WAL_Handle is limited private;

   --  Record_Kind enumerates the supported values for this database abstraction.
   type Record_Kind is
     (Page_Frame,
      Commit_Record,
      Checkpoint_Record,
      Full_Text_Redo_Record,
      Full_Text_Undo_Record,
      Page_Undo_Record,
      Begin_Record,
      Abort_Record);

   --  Return wal path for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return Result produced by the function.
   function WAL_Path (Database_Path : Wide_Wide_String) return Wide_Wide_String;
   --  Return exists for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return Result produced by the function.
   function Exists (Database_Path : Wide_Wide_String) return Boolean;
   --  Return delete for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Delete (Database_Path : Wide_Wide_String) return Database.Status.Result;

   --  Return create for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create (W : in out WAL_Handle; Database_Path : Wide_Wide_String) return Database.Status.Result;
   --  Return open for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Open (W : in out WAL_Handle; Database_Path : Wide_Wide_String) return Database.Status.Result;
   --  Return close for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @return Result produced by the function.
   function Close (W : in out WAL_Handle) return Database.Status.Result;
   --  Return is open for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Open (W : WAL_Handle) return Boolean;
   --  Return flush for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @return Result produced by the function.
   function Flush (W : in out WAL_Handle) return Database.Status.Result;
   --  Return durable lsn for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @return Result produced by the function.
   function Durable_LSN (W : WAL_Handle) return Database.Log_Sequence.Log_Sequence_Number;

   --  Return append page frame for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @param Transaction_Id transaction id argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Result produced by the function.
   function Append_Page_Frame
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Append a full-text page after-image. Recovery replays this image only
   --  for transactions that have a durable commit marker. Reserved: the
   --  engine does not write full-text pages through the WAL today, but the
   --  record kind is part of the format and recovery honours it.
   --  @param W w argument supplied to the operation.
   --  @param Transaction_Id transaction id argument supplied to the operation.
   --  @param Page full-text dictionary or posting page after image.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Append_Full_Text_Redo
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Append a full-text page before-image. Recovery writes it back for a
   --  transaction that has neither a commit nor an abort record. Reserved like
   --  Append_Full_Text_Redo.
   --  @param W w argument supplied to the operation.
   --  @param Transaction_Id transaction id argument supplied to the operation.
   --  @param Page full-text dictionary or posting page before image.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Append_Full_Text_Undo
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Append the image a page had before a transaction first changed it. Recovery writes the image back for a
   --  transaction that has neither a commit nor an abort record.
   --  @param W open WAL.
   --  @param Transaction_Id transaction that changes the page.
   --  @param Page the page as it was before the transaction changed it.
   --  @param LSN sequence number of the record.
   --  @return Status result describing whether the operation succeeded.
   function Append_Page_Undo
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Append the start of a transaction's writes, with the length of the database file before them. Recovery cuts the
   --  file back to that length for a transaction that has neither a commit nor an abort record.
   --  @param W open WAL.
   --  @param Transaction_Id transaction about to write its first page.
   --  @param Page_Count number of pages in the database file before the transaction's first write.
   --  @param LSN sequence number of the record.
   --  @return Status result describing whether the operation succeeded.
   function Append_Begin
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page_Count     : Natural;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Append the end of a transaction whose writes were undone, so recovery does not undo them again over later work.
   --  @param W open WAL.
   --  @param Transaction_Id transaction that rolled back.
   --  @param LSN sequence number of the record.
   --  @return Status result describing whether the operation succeeded.
   function Append_Abort
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Return append commit for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @param Transaction_Id transaction id argument supplied to the operation.
   --  @param Commit_Version commit version argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Result produced by the function.
   function Append_Commit
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Commit_Version : Natural;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Return append checkpoint for the supplied database state or arguments.
   --  @param W w argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Result produced by the function.
   function Append_Checkpoint
     (W   : in out WAL_Handle;
      LSN : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result;

   --  Numbers by transaction id, such as the version a transaction committed.
   package Transaction_Maps is new Ada.Containers.Ordered_Maps (Natural, Natural);

   --  What recovery found in a WAL besides the pages it wrote.
   type Recovery_Summary is record
      --  The committed transactions, so visibility treats their rows as committed in a process that never ran them.
      Committed          : Transaction_Maps.Map;
      --  The highest commit version, or zero.
      Max_Commit_Version : Natural := 0;
      --  The highest transaction id in any record, or zero. A new transaction must not reuse one, or replay would take
      --  the records of the old transaction for its own.
      Max_Transaction_Id : Natural := 0;
   end record;

   --  Recover the database file from its WAL: write the page images of committed transactions, and undo the
   --  transactions that have neither a commit nor an abort record, which a crash interrupted. Their pages get their
   --  images from before the transaction back, the file is cut back to its length before them unless a committed
   --  transaction wrote past it, and an abort record is appended for each so a later replay leaves them alone.
   --  The WAL is read twice: once to learn how each transaction ended, once to apply its records.
   --  @param Database_Path path of the database whose WAL is replayed.
   --  @param F the open database file.
   --  @param Summary what the WAL holds besides pages; empty when there is no WAL.
   --  @return Status result; Replay_Failure or a WAL corruption status when the WAL cannot be applied.
   function Recover
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle;
      Summary       : out Recovery_Summary) return Database.Status.Result;

   --  Recover the database file from its WAL, as Recover does, without the summary.
   --  @param Database_Path path of the database whose WAL is replayed.
   --  @param F the open database file.
   --  @return Status result; Replay_Failure or a WAL corruption status when the WAL cannot be applied.
   function Replay_Committed
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result;

   --  Return validate for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate (Database_Path : Wide_Wide_String) return Database.Status.Result;

   --  Forget what this process knows about a WAL it appended to, so the next Open scans the file again. Called when
   --  the database handle closes and its process lock is released, after which another process may append.
   --  @param Database_Path database path whose WAL is no longer trusted.
   procedure Forget_Trusted (Database_Path : Wide_Wide_String);

private
   --  WAL_Handle defines a public database type used by this package.
   type WAL_Handle is limited record
      File        : Ada.Streams.Stream_IO.File_Type;
      Opened      : Boolean := False;
      DB_Path     : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Generator   : Database.Log_Sequence.Generator;
      Durable_Pos : Database.Log_Sequence.Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
   end record;
end Database.WAL;
