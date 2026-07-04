--  Encryption key derivation, key metadata, and explicit key lifecycle helpers.
with Database.Status;
with Database.Storage.Pages;

--  Key descriptors and key-derivation helpers.
package Database.Keys is
   --  Key identifier subtype re-exported from the root package.
   subtype Key_Id is Database.Key_Id;
   --  Salt byte array subtype re-exported from the root package.
   subtype Salt_Type is Database.Salt_Type;
   --  Fixed-size salt subtype re-exported from the root package.
   subtype Fixed_Salt is Database.Fixed_Salt;
   --  Key byte array subtype re-exported from the root package.
   subtype Key_Bytes is Database.Key_Bytes;
   --  Fixed-size binary key subtype re-exported from the root package.
   subtype Binary_Key is Database.Binary_Key;
   --  Encryption key subtype re-exported from the root package.
   subtype Encryption_Key is Database.Encryption_Key;

   --  Return an invalid empty key sentinel.
   --  @return Empty encryption key.
   function Empty_Key return Encryption_Key;
   --  Return whether the key contains usable key material.
   --  @param Key encryption key to inspect.
   --  @return True when the key is valid.
   function Is_Valid (Key : Encryption_Key) return Boolean;
   --  Return the stable key identifier.
   --  @param Key encryption key to inspect.
   --  @return Identifier attached to the key.
   function Identifier (Key : Encryption_Key) return Key_Id;
   --  Return the deterministic default salt.
   --  @return Default salt bytes.
   function Default_Salt return Fixed_Salt;

   --  Derive an encryption key from a passphrase and salt.
   --  @param Passphrase passphrase supplied by the caller.
   --  @param Salt salt bytes used for derivation.
   --  @return Derived encryption key.
   function Derive_Key
     (Passphrase : Wide_Wide_String;
      Salt       : Salt_Type) return Encryption_Key;

   --  Create an encryption key from explicit binary key bytes.
   --  @param Bytes 32-byte binary key material.
   --  @param Id identifier to attach to the key.
   --  @return Encryption key using the supplied bytes.
   function From_Binary_Key
     (Bytes : Binary_Key;
      Id    : Key_Id := 1) return Encryption_Key;

   --  Clear key material in place.
   --  @param Key encryption key cleared by the operation.
   procedure Clear (Key : in out Encryption_Key);
   --  Return one byte from key material, wrapping by key length.
   --  @param Key encryption key to inspect.
   --  @param Index zero-based byte index.
   --  @return Key byte at the wrapped index.
   function Byte_At (Key : Encryption_Key; Index : Natural) return Database.Storage.Pages.Byte;
   --  Validate binary key bytes before creating a key.
   --  @param Bytes byte data processed by the operation.
   --  @return Status result describing whether the bytes are valid.
   function Validate_Format (Bytes : Key_Bytes) return Database.Status.Result;
end Database.Keys;
