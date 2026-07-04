--  Append-only physical write-ahead log used by persistent transactions.
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Log_Sequence;
with Ada.Streams.Stream_IO;
with Ada.Strings.Wide_Wide_Unbounded;

--  Write-ahead log subsystem namespace.
package Database.WAL is
   --  WAL_Handle defines a public database type used by this package.
   type WAL_Handle is limited private;

   --  Record_Kind enumerates the supported values for this database abstraction.
   type Record_Kind is (Page_Frame, Commit_Record, Checkpoint_Record);

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

   --  Return replay committed for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @param F f argument supplied to the operation.
   --  @return Result produced by the function.
   function Replay_Committed
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result;

   --  Return the highest commit version recorded in a WAL file, or zero when
   --  no committed transaction version is present.
   function Max_Commit_Version (Database_Path : Wide_Wide_String) return Natural;

   --  Return validate for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate (Database_Path : Wide_Wide_String) return Database.Status.Result;

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
