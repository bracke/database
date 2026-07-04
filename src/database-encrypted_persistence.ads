--  Durable encrypted artifact persistence for pages, WAL frames, backups,
--  logical exports, manifests, full-text structures, and key metadata.
--
--  This package writes authenticated encrypted containers to disk and reads
--  them back through the same verification path used by recovery and hardening
--  tests.  The container is intentionally independent of Ada record memory
--  layout and stores only explicit bytes plus authenticated metadata.
with Database.Status;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Keys;
with Database.Log_Sequence;

--  Public specification for this database subsystem.
package Database.Encrypted_Persistence is
   --  Byte defines a public database type used by this package.
   subtype Byte is Database.Crypto.Byte;
   --  Byte_Array defines a public database type used by this package.
   type Byte_Array is array (Natural range <>) of Byte;

   --  Persisted_Header stores the public fields for this database abstraction.
   type Persisted_Header is record
      Kind           : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Format_Version : Natural := 1;
      Key_Id         : Database.Keys.Key_Id := 0;
      Object_Id      : Natural := 0;
      LSN            : Database.Log_Sequence.Log_Sequence_Number := 0;
      Plaintext_Size : Natural := 0;
   end record;

   --  Read_Result stores the public fields for this database abstraction.
   type Read_Result is record
      Result : Database.Status.Result := Database.Status.Success;
      Header : Persisted_Header;
   end record;

   --  Return write artifact for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Kind kind selector controlling the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Format_Version format version argument supplied to the operation.
   --  @param Object_Id object id argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @param Plaintext plaintext argument supplied to the operation.
   --  @return Result produced by the function.
   function Write_Artifact
     (Path           : Wide_Wide_String;
      Kind           : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key            : Database.Keys.Encryption_Key;
      Format_Version : Natural;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number;
      Plaintext      : Database.Crypto.Byte_Array) return Database.Status.Result;

   --  Return read artifact for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Expected expected value used for validation.
   --  @param Key key value used to identify the row or object.
   --  @param Plaintext plaintext argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_Artifact
     (Path      : Wide_Wide_String;
      Expected  : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key       : Database.Keys.Encryption_Key;
      Plaintext : out Database.Crypto.Byte_Array) return Read_Result;

   --  Return verify artifact file for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Expected expected value used for validation.
   --  @param Key key value used to identify the row or object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Artifact_File
     (Path     : Wide_Wide_String;
      Expected : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key      : Database.Keys.Encryption_Key)
      return Database.Crypto_Checks.Check_Result;

   --  Return artifact plaintext size for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Expected expected value used for validation.
   --  @param Key key value used to identify the row or object.
   --  @param Size size argument supplied to the operation.
   --  @return Result produced by the function.
   function Artifact_Plaintext_Size
     (Path     : Wide_Wide_String;
      Expected : Database.Crypto_Checks.Encrypted_Artifact_Kind;
      Key      : Database.Keys.Encryption_Key;
      Size     : out Natural) return Database.Status.Result;

   --  Return tamper byte for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Offset offset argument supplied to the operation.
   --  @param Mask mask argument supplied to the operation.
   --  @return Result produced by the function.
   function Tamper_Byte
     (Path   : Wide_Wide_String;
      Offset : Natural;
      Mask   : Byte := 16#55#) return Database.Status.Result;

   --  Return truncate file for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param New_Size new size argument supplied to the operation.
   --  @return Result produced by the function.
   function Truncate_File
     (Path      : Wide_Wide_String;
      New_Size  : Natural) return Database.Status.Result;
end Database.Encrypted_Persistence;
