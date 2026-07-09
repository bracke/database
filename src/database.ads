--  Root database handle API. Owns in-memory or persistent database state.
--  All data access is performed through transaction-scoped package APIs.
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Streams.Stream_IO;
with Interfaces.C;

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
      Lock_Error, Serialization_Failure, Snapshot_Too_Old, Version_Conflict,
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

   --  In-process read/write lock used by transaction coordination.
   protected type Read_Write_Lock is
      entry Begin_Read;
      procedure Try_Begin_Read (Granted : out Boolean);
      procedure End_Read;
      entry Begin_Write;
      procedure Try_Begin_Write (Granted : out Boolean);
      procedure End_Write;
      function Active_Readers return Natural;
      function Writer_Active return Boolean;
      function Waiting_Writers return Natural;
   private
      Readers       : Natural := 0;
      Writer        : Boolean := False;
      Waiting_Write : Natural := 0;
      entry Acquire_Write;
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
   type Encryption_Key is record
      Valid : Boolean := False;
      Id    : Key_Id := 0;
      Data  : Binary_Key := (others => 0);
   end record;

   type File_Handle is limited record
      File      : Ada.Streams.Stream_IO.File_Type;
      Opened    : Boolean := False;
      Name      : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Lock_FD   : Interfaces.C.int := Interfaces.C.int'First;
      Encrypted : Boolean := False;
      Key       : Encryption_Key := (Valid => False, Id => 0, Data => (others => 0));
   end record;

   type Allocator is record
      Next_Page : Page_Id := 1;
   end record;

   type Handle is limited record
      Kind : Backend_Kind := Closed_Backend;
      Last : Result := (Code => Ok, Message => Null_Unbounded_Wide_Wide_String);
      File : File_Handle;
      Page_Allocator : Allocator;
      Lock : Read_Write_Lock;
      Version : Natural := 0;
      FT_State_Key : Natural := 0;
      Catalog_State_Key_Value : Natural := 0;
      Encryption_Enabled        : Boolean := False;
      Encryption_Format_Version : Natural := 1;
      Encryption_Key_Id         : Key_Id := 0;
      WAL_Encryption_Enabled    : Boolean := False;
   end record;
end Database;
