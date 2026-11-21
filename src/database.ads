--  Root database handle API. Owns in-memory or persistent database state.
--  All data access is performed through transaction-scoped package APIs.
with Ada.Containers.Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Streams.Stream_IO;
with Ada.Task_Identification;
with Interfaces.C;
with System;

package Database is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Backend kind of a database handle.
   type Backend_Kind is (Closed_Backend, In_Memory_Backend, Persistent_Backend);

   --  Structured status code returned by ordinary database operations.
   type Status_Code is
     (Ok, Not_Open, Already_Open, Invalid_Argument, Not_Found,
      Already_Exists, Schema_Mismatch, Constraint_Error, Transaction_Error,
      Invalid_File, Corrupt_File, Row_Too_Large, IOError,
      Serialization_Error, Corrupt_Index, Key_Not_Found, Duplicate_Key,
      Unsupported_Key_Type, Invalid_Schema, Migration_Error,
      Unsupported_Migration, Read_Only_Transaction, Transaction_Conflict,
      Lock_Error, Recovery_Required, Serialization_Failure, Snapshot_Too_Old, Version_Conflict,
      WAL_Corruption, Replay_Failure, Checkpoint_Failure, Invalid_LSN,
      Full_Text_Index_Error, Invalid_Full_Text_Query, Unsupported_Tokenizer,
      Unsupported_Normalization, Backup_Error, Restore_Error, Export_Error,
      Import_Error, Incompatible_Backup, Corrupt_Backup,
      Backup_Verification_Failed, Encryption_Error, Authentication_Failure,
      Invalid_Key, Unsupported_Encryption_Format, Corrupt_Encrypted_Page,
      Corrupt_Encrypted_WAL, Key_Rotation_Failed, Missing_Extension,
      Extension_Version_Mismatch, Extension_Error, Invalid_Date, Invalid_Time,
      Invalid_UUID, Decimal_Overflow, Invalid_Enum_Value,
      Bounded_Text_Overflow, Unsupported_Type_Version, Trace_Error,
      Metrics_Error, Profiling_Error, Event_Handler_Error, Invariant_Failure,
      Corruption_Detected, Replay_Inconsistency, Fault_Injection_Error,
      Fuzzing_Failure, Verification_Failure);

   --  Structured operation result. Expected validation and corruption failures
   --  are reported through this type rather than through exceptions.
   type Result is record
      Code    : Status_Code := Ok;
      Message : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
   end record;

   --  Byte used by durable page/key structures.
   type Byte is mod 2 ** 8;

   --  Byte array used by key material and page buffers.
   type Byte_Array is array (Natural range <>) of Byte;

   --  Durable page identifier shared by storage subpackages.
   type Page_Id is new Natural;

   --  Encryption key identifier.
   type Key_Id is new Natural;

   --  Salt bytes accepted by key-derivation helpers.
   type Salt_Type is array (Natural range <>) of Byte;

   --  Fixed salt used by the default derivation helper.
   subtype Fixed_Salt is Salt_Type (0 .. 31);

   --  Binary key bytes accepted by explicit key construction.
   type Key_Bytes is array (Natural range <>) of Byte;

   --  Fixed-size binary encryption key.
   subtype Binary_Key is Key_Bytes (0 .. 31);

   --  Authenticated-storage encryption key.
   type Encryption_Key is private;

   --  Internal persistent file handle shared with storage child packages.
   type File_Handle is limited private;

   --  Internal free-page allocator shared with storage child packages.
   type Allocator is private;

   --  The holds of one owner on one Read_Write_Lock. The lock sets and clears it inside its own protected operations,
   --  so an abort cannot come between taking or releasing the lock and recording it, and records itself in it: a
   --  claim releases only what the lock that granted it gave, and while it holds something no other lock grants it
   --  anything. Limited, so a hold cannot be duplicated, and tagged, so it is passed by reference.
   type Lock_Claim is tagged limited private;

   --  Whether Claim holds a read or the write side of a lock.
   --  @param Claim claim to inspect.
   --  @return True from the grant until the release.
   function Is_Held (Claim : Lock_Claim) return Boolean;

   --  In-process read/write lock used by transaction coordination. A write transaction holds the write side; so does,
   --  exclusively, an operation outside any transaction that writes the file directly: a checkpoint, a backup, a
   --  catalog change or a close. Each hold is recorded in the caller's claim, and End_Read or End_Write releases
   --  what the claim holds and nothing else.
   --  Every grant sets Granted to False and grants nothing when Claim holds something another lock granted.
   protected type Read_Write_Lock is
      entry Begin_Read (Claim : in out Lock_Claim; Granted : out Boolean);
      procedure Try_Begin_Read (Claim : in out Lock_Claim; Granted : out Boolean);
      procedure End_Read (Claim : in out Lock_Claim);
      --  Take the write side for a write transaction, waiting for the current writer.
      entry Begin_Write (Claim : in out Lock_Claim; Granted : out Boolean);
      procedure Try_Begin_Write (Claim : in out Lock_Claim; Granted : out Boolean);
      --  Take the write side for an operation outside any transaction, waiting for the current writer.
      entry Begin_Exclusive (Claim : in out Lock_Claim; Granted : out Boolean);
      --  Take the write side for an operation outside any transaction when no one writes.
      procedure Try_Begin_Exclusive (Claim : in out Lock_Claim; Granted : out Boolean);
      --  Take the write side exclusively for closing the database when no one reads or writes; until End_Write,
      --  Begin_Read waits and Try_Begin_Read refuses.
      procedure Try_Begin_Close (Claim : in out Lock_Claim; Granted : out Boolean);
      procedure End_Write (Claim : in out Lock_Claim);
      function Active_Readers return Natural;
      function Writer_Active return Boolean;
      --  Whether an operation outside any transaction holds the write side.
      function Exclusive_Active return Boolean;
      --  Whether the calling task holds the write side, for a transaction or exclusively.
      function Held_By_Current_Task return Boolean;
      --  Whether a write transaction begun by the calling task holds the write side.
      function Own_Transaction_Writing return Boolean;
      --  Whether the calling task is closing the database, so that Begin_Read would wait for itself.
      function Closing_By_Current_Task return Boolean;
      --  The tasks waiting in Begin_Write or Begin_Exclusive.
      function Waiting_Writers return Natural;
   private
      --  Whether Claim was granted by this lock.
      function Granted_Here (Claim : Lock_Claim) return Boolean;
      --  Whether this lock may grant Claim something: it holds nothing, or only what this lock gave.
      function Grantable (Claim : Lock_Claim) return Boolean;
      --  Take the write side for Holder; Exclusive_Hold and Closing_Hold say for what.
      procedure Grant_Write
        (Claim : in out Lock_Claim; Holder_Task : Ada.Task_Identification.Task_Id; Exclusive_Hold : Boolean;
         Closing_Hold : Boolean);
      Readers   : Natural := 0;
      Writer    : Boolean := False;
      Exclusive : Boolean := False;
      Closing   : Boolean := False;
      Holder    : Ada.Task_Identification.Task_Id := Ada.Task_Identification.Null_Task_Id;
   end Read_Write_Lock;

   --  Public database handle.
   type Handle is limited private;

   --  Open an in-memory database.
   --  @param DB database handle initialized by the operation.
   procedure Open_In_Memory (DB : out Handle);

   --  Create a persistent database.
   --  @param DB database handle initialized by the operation.
   --  @param Path filesystem path of the database carrier file.
   procedure Create (DB : out Handle; Path : Wide_Wide_String);

   --  Create an encrypted persistent database.
   --  @param DB database handle initialized by the operation.
   --  @param Path filesystem path of the database carrier file.
   --  @param Key encryption key used for authenticated page artifacts.
   procedure Create_Encrypted
     (DB   : out Handle;
      Path : Wide_Wide_String;
      Key  : Encryption_Key);

   --  Open a persistent database.
   --  @param DB database handle initialized by the operation.
   --  @param Path filesystem path of the database carrier file.
   procedure Open (DB : out Handle; Path : Wide_Wide_String);

   --  Open an existing persistent database without permitting recovery or
   --  mutation.  The operation takes a shared process lock and fails with
   --  Recovery_Required when a WAL is present.
   --  @param DB database handle initialized by the operation.
   --  @param Path filesystem path of the database carrier file.
   procedure Open_Read_Only (DB : out Handle; Path : Wide_Wide_String);

   --  Open an encrypted persistent database.
   --  @param DB database handle initialized by the operation.
   --  @param Path filesystem path of the database carrier file.
   --  @param Key encryption key used for authenticated page artifacts.
   procedure Open_Encrypted
     (DB   : out Handle;
      Path : Wide_Wide_String;
      Key  : Encryption_Key);

   --  Close a database handle.
   --  @param DB database handle closed by the operation.
   procedure Close (DB : in out Handle);

   --  Return whether the handle is currently open.
   --  @param DB database handle queried by the operation.
   --  @return True when the handle is open.
   function Is_Open (DB : Handle) return Boolean;

   --  Return whether the handle was opened through Open_Read_Only.
   function Is_Read_Only (DB : Handle) return Boolean;

   --  Return whether the last root-level operation succeeded.
   --  @param DB database handle queried by the operation.
   --  @return True when the last operation succeeded.
   function Last_Operation_Succeeded (DB : Handle) return Boolean;

   --  Return the last structured status produced by a root-level operation.
   --  @param DB database handle queried by the operation.
   --  @return Status result describing the last root-level operation.
   function Last_Result (DB : Handle) return Result;

   --  Return the active backend kind.
   --  @param DB database handle queried by the operation.
   --  @return Backend kind of the handle.
   function Backend (DB : Handle) return Backend_Kind;

   --  Return the current commit version observed by the handle.
   --  @param DB database handle queried by the operation.
   --  @return Current commit version.
   function Commit_Version (DB : Handle) return Natural;

   --  Return the internal full-text state key.
   --  @param DB database handle queried by the operation.
   --  @return Full-text state key for the handle.
   function Full_Text_State_Key (DB : Handle) return Natural;

   --  Return the internal catalog state key.
   --  @param DB database handle queried by the operation.
   --  @return Catalog state key for the handle.
   function Catalog_State_Key (DB : Handle) return Natural;

private
   type Lock_Claim is tagged limited record
      Read  : Boolean := False;
      Write : Boolean := False;
      --  The lock that granted the hold.
      Lock  : System.Address := System.Null_Address;
   end record;

   function Is_Held (Claim : Lock_Claim) return Boolean is (Claim.Read or else Claim.Write);
   type Encryption_Key is record
      Valid : Boolean := False;
      Id    : Key_Id := 0;
      Data  : Binary_Key := (others => 0);
   end record;

   --  Validated page images of an unencrypted handle, kept for the duration of one transaction. The handle's process
   --  lock keeps other processes from writing while it is open; its own page writes update the cache, other changes to
   --  the file clear it, and so does every transaction start and end and closing the handle.
   Cached_Page_Bytes : constant := 4096;
   Cache_Slots       : constant := 64;

   type Cached_Page is record
      Id    : Page_Id := 0;
      Valid : Boolean := False;
      Bytes : Byte_Array (0 .. Cached_Page_Bytes - 1) := [others => 0];
   end record;

   type Page_Cache is array (0 .. Cache_Slots - 1) of Cached_Page;
   type Page_Cache_Access is access Page_Cache;

   type File_Handle is limited record
      File      : Ada.Streams.Stream_IO.File_Type;
      Opened    : Boolean := False;
      Name      : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Lock_FD   : Interfaces.C.int := Interfaces.C.int'First;
      Encrypted : Boolean := False;
      Read_Only : Boolean := False;
      Key       : Encryption_Key := (Valid => False, Id => 0, Data => (others => 0));
      Cache     : Page_Cache_Access := null;
   end record;

   package Page_Id_Lists is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Page_Id);

   --  Next_Page is the first page past the file. The file is scanned for free pages once, on the first allocation
   --  after the allocator is initialized; Free_Pages holds the ones not yet reused, each checked again before use.
   type Allocator is record
      Next_Page  : Page_Id := 1;
      Scanned    : Boolean := False;
      Free_Pages : Page_Id_Lists.Vector;
   end record;

   type Handle is limited record
      Kind : Backend_Kind := Closed_Backend;
      Last : Result := (Code => Ok, Message => Null_Unbounded_Wide_Wide_String);
      File : File_Handle;
      Page_Allocator : Allocator;
      Lock : Read_Write_Lock;
      Version : Natural := 0;
      --  Highest transaction id referenced by any persisted row at open time,
      --  used to reserve fresh ids above it so a recovered process never
      --  reuses an id that still appears in Created_By_Tx / Deleted_By_Tx
      --  (which would alias the global MVCC lifecycle map). Derived from the
      --  heap during Catalog.Load, mirroring how Version is recovered.
      Max_Persisted_Tx : Natural := 0;
      FT_State_Key : Natural := 0;
      Catalog_State_Key_Value : Natural := 0;
      Encryption_Enabled        : Boolean := False;
      Encryption_Format_Version : Natural := 1;
      Encryption_Key_Id         : Key_Id := 0;
      WAL_Encryption_Enabled    : Boolean := False;
      Read_Only_Mode            : Boolean := False;
   end record;
end Database;
