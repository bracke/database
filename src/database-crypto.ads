--  Cryptographic primitive abstraction used by encrypted pages, WAL frames,
--  backups, and logical export/import containers.
with Database.Status;
with Database.Storage.Pages;
with Database.Keys;
with Database.Log_Sequence;

--  Cryptographic primitives used by encrypted storage.
package Database.Crypto is
   --  Byte defines a public database type used by this package.
   subtype Byte is Database.Storage.Pages.Byte;
   --  Byte_Array defines a public database type used by this package.
   type Byte_Array is array (Natural range <>) of Byte;
   --  Nonce defines a public database type used by this package.
   subtype Nonce is Byte_Array (0 .. 23);
   --  Authentication_Tag defines a public database type used by this package.
   subtype Authentication_Tag is Byte_Array (0 .. 31);

   --  Return generate nonce for the supplied database state or arguments.
   --  @param Object_Id object id argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   --  @return Result produced by the function.
   function Generate_Nonce
     (Object_Id : Natural;
      LSN       : Database.Log_Sequence.Log_Sequence_Number) return Nonce;

   --  Return compute mac for the supplied database state or arguments.
   --  @param Key key value used to identify the row or object.
   --  @param Nonce_Value nonce value argument supplied to the operation.
   --  @param Associated_Data associated data argument supplied to the operation.
   --  @param Ciphertext ciphertext argument supplied to the operation.
   --  @return Result produced by the function.
   function Compute_MAC
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Ciphertext      : Byte_Array) return Authentication_Tag;

   --  Return encrypt for the supplied database state or arguments.
   --  @param Key key value used to identify the row or object.
   --  @param Nonce_Value nonce value argument supplied to the operation.
   --  @param Associated_Data associated data argument supplied to the operation.
   --  @param Plaintext plaintext argument supplied to the operation.
   --  @param Ciphertext ciphertext argument supplied to the operation.
   --  @param Tag tag argument supplied to the operation.
   --  @return Result produced by the function.
   function Encrypt
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Plaintext       : Byte_Array;
      Ciphertext      : out Byte_Array;
      Tag             : out Authentication_Tag) return Database.Status.Result;

   --  Return decrypt for the supplied database state or arguments.
   --  @param Key key value used to identify the row or object.
   --  @param Nonce_Value nonce value argument supplied to the operation.
   --  @param Associated_Data associated data argument supplied to the operation.
   --  @param Ciphertext ciphertext argument supplied to the operation.
   --  @param Tag tag argument supplied to the operation.
   --  @param Plaintext plaintext argument supplied to the operation.
   --  @return Result produced by the function.
   function Decrypt
     (Key             : Database.Keys.Encryption_Key;
      Nonce_Value     : Nonce;
      Associated_Data : Byte_Array;
      Ciphertext      : Byte_Array;
      Tag             : Authentication_Tag;
      Plaintext       : out Byte_Array) return Database.Status.Result;

   --  Perform clear for the supplied database state or arguments.
   --  @param Data byte data processed by the operation.
   procedure Clear (Data : in out Byte_Array);
end Database.Crypto;
