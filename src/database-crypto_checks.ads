--  Encryption-aware integrity checking helpers. These checks validate metadata,
--  authentication tags, and encrypted buffer consistency without exposing keys.
with Database.Status;
with Database.Crypto;
with Database.Keys;
with Database.Log_Sequence;

--  Authenticated integrity checks for encrypted artifacts.
package Database.Crypto_Checks is
   --  Encrypted_Artifact_Kind defines a public database type used by this package.
   type Encrypted_Artifact_Kind is
     (Encrypted_Page_Artifact,
      Encrypted_WAL_Frame_Artifact,
      Encrypted_Backup_Artifact,
      Encrypted_Export_Artifact,
      Encrypted_Key_Metadata_Artifact,
      Encrypted_Backup_Manifest_Artifact,
      Encrypted_Full_Text_Artifact);

   --  Check_Result stores the public fields for this database abstraction.
   type Check_Result is record
      Result              : Database.Status.Result := Database.Status.Success;
      Authenticated_Items : Natural := 0;
      Failed_Items        : Natural := 0;
   end record;

   --  Return verify authenticated buffer for the supplied database state or arguments.
   --  @param Key key value used to identify the row or object.
   --  @param Nonce_Value nonce value argument supplied to the operation.
   --  @param Associated_Data associated data argument supplied to the operation.
   --  @param Ciphertext ciphertext argument supplied to the operation.
   --  @param Tag tag argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Authenticated_Buffer
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Database.Crypto.Nonce;
      Associated_Data : Database.Crypto.Byte_Array;
      Ciphertext      : Database.Crypto.Byte_Array;
      Tag             : Database.Crypto.Authentication_Tag) return Check_Result;

   --  Return validate key metadata for the supplied database state or arguments.
   --  @param Key key value used to identify the row or object.
   --  @param Format_Version format version argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Key_Metadata
     (Key              : Database.Keys.Encryption_Key;
      Format_Version   : Natural) return Database.Status.Result;

   --  Build the associated-data prefix used for authenticated durable
   --  encrypted artifacts.  The prefix binds ciphertext to object kind,
   --  format version, key id, object id, and LSN.
   --  @param Kind kind selector controlling the operation.
   --  @param Format_Version format version argument supplied to the operation.
   --  @param Key_Id key id argument supplied to the operation.
   --  @param Object_Id object id argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Result produced by the function.
   function Artifact_Associated_Data
     (Kind           : Encrypted_Artifact_Kind;
      Format_Version : Natural;
      Key_Id         : Database.Keys.Key_Id;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number)
      return Database.Crypto.Byte_Array;

   --  Validate a concrete encrypted durable artifact without exposing plaintext.
   --  This is intentionally stricter than Verify_Authenticated_Buffer: it also
   --  validates key metadata and rejects artifact/format mismatches with
   --  artifact-specific corruption status codes.
   --  @param Kind kind selector controlling the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Format_Version format version argument supplied to the operation.
   --  @param Object_Id object id argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @param Nonce_Value nonce value argument supplied to the operation.
   --  @param Ciphertext ciphertext argument supplied to the operation.
   --  @param Tag tag argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Verify_Encrypted_Artifact
     (Kind           : Encrypted_Artifact_Kind;
      Key            : Database.Keys.Encryption_Key;
      Format_Version : Natural;
      Object_Id      : Natural;
      LSN            : Database.Log_Sequence.Log_Sequence_Number;
      Nonce_Value    : Database.Crypto.Nonce;
      Ciphertext     : Database.Crypto.Byte_Array;
      Tag            : Database.Crypto.Authentication_Tag) return Check_Result;
end Database.Crypto_Checks;
