with AUnit.Assertions;

with Database; use Database;
with Database.Crypto; use Database.Crypto;
with Database.Crypto_Checks;
with Database.Encryption; use Database.Encryption;
with Database.Encrypted_Persistence;
with Database.Check;
with Database.Diagnostics;
with Database.Keys;
with Database.Log_Sequence;
with Database.Status; use Database.Status;
with Database.Transactions;
with Database.Storage.Pages;

package body Encryption_Tests is
   use AUnit.Assertions;
   use type Database.Storage.Pages.Byte;
   use type Database.Log_Sequence.Log_Sequence_Number;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("encryption");
   end Name;

   procedure Derived_Key_Is_Reproducible
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Salt : constant Database.Keys.Fixed_Salt := Database.Keys.Default_Salt;
      K1   : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Salt);
      K2   : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Salt);
   begin
      Assert (Database.Keys.Is_Valid (K1), "derived key is valid");
      for I in 0 .. 31 loop
         Assert
           (Database.Keys.Byte_At (K1, I) = Database.Keys.Byte_At (K2, I),
            "derived key byte mismatch");
      end loop;
   end Derived_Key_Is_Reproducible;

   procedure Key_Derivation_Uses_Passphrase_And_Salt
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Salt_1 : constant Database.Keys.Fixed_Salt := Database.Keys.Default_Salt;
      Salt_2 : Database.Keys.Fixed_Salt := Database.Keys.Default_Salt;
      K1     : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Salt_1);
      K2     : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("different", Salt_1);
      K3     : Database.Keys.Encryption_Key;
      Passphrase_Changed : Boolean := False;
      Salt_Changed       : Boolean := False;
   begin
      Salt_2 (Salt_2'First) := Salt_2 (Salt_2'First) xor 16#5A#;
      K3 := Database.Keys.Derive_Key ("secret", Salt_2);

      for I in 0 .. 31 loop
         if Database.Keys.Byte_At (K1, I) /= Database.Keys.Byte_At (K2, I) then
            Passphrase_Changed := True;
         end if;
         if Database.Keys.Byte_At (K1, I) /= Database.Keys.Byte_At (K3, I) then
            Salt_Changed := True;
         end if;
      end loop;

      Assert (Passphrase_Changed, "passphrase changes derived key bytes");
      Assert (Salt_Changed, "salt changes derived key bytes");
   end Key_Derivation_Uses_Passphrase_And_Salt;

   procedure Key_Derivation_Accepts_Empty_Inputs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty_Salt : constant Database.Keys.Salt_Type (1 .. 0) := (others => 0);
      K          : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("", Empty_Salt);
      Nonzero    : Boolean := False;
   begin
      Assert (Database.Keys.Is_Valid (K), "empty derivation inputs still produce a valid key");
      for I in 0 .. 31 loop
         if Database.Keys.Byte_At (K, I) /= 0 then
            Nonzero := True;
         end if;
      end loop;
      Assert (Nonzero, "empty derivation inputs do not produce an all-zero key");
   end Key_Derivation_Accepts_Empty_Inputs;

   procedure Authentication_Binds_Nonce_And_Associated_Data
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Key         : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      Nonce       : constant Database.Crypto.Nonce :=
        Database.Crypto.Generate_Nonce (42, 7);
      Wrong_Nonce : constant Database.Crypto.Nonce :=
        Database.Crypto.Generate_Nonce (42, 8);
      AD          : constant Database.Crypto.Byte_Array (0 .. 2) := (1, 2, 3);
      Wrong_AD    : constant Database.Crypto.Byte_Array (0 .. 2) := (1, 2, 4);
      Plain       : constant Database.Crypto.Byte_Array (0 .. 4) :=
        (10, 20, 30, 40, 50);
      Cipher      : Database.Crypto.Byte_Array (0 .. 4);
      Back        : Database.Crypto.Byte_Array (0 .. 4);
      Tag         : Database.Crypto.Authentication_Tag;
      R           : Database.Status.Result;
   begin
      R := Database.Crypto.Encrypt (Key, Nonce, AD, Plain, Cipher, Tag);
      Assert (Database.Status.Is_Ok (R), "encrypt succeeds");

      R := Database.Crypto.Decrypt (Key, Wrong_Nonce, AD, Cipher, Tag, Back);
      Assert
        (R.Code = Database.Status.Authentication_Failure,
         "wrong nonce is rejected");

      R := Database.Crypto.Decrypt (Key, Nonce, Wrong_AD, Cipher, Tag, Back);
      Assert
        (R.Code = Database.Status.Authentication_Failure,
         "wrong associated data is rejected");
   end Authentication_Binds_Nonce_And_Associated_Data;

   procedure Authenticated_Encryption_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Salt   : constant Database.Keys.Fixed_Salt := Database.Keys.Default_Salt;
      Key    : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Salt);
      Nonce  : constant Database.Crypto.Nonce :=
        Database.Crypto.Generate_Nonce (42, 7);
      AD     : constant Database.Crypto.Byte_Array (0 .. 2) := (1, 2, 3);
      Plain  : constant Database.Crypto.Byte_Array (0 .. 4) :=
        (10, 20, 30, 40, 50);
      Cipher : Database.Crypto.Byte_Array (0 .. 4);
      Back   : Database.Crypto.Byte_Array (0 .. 4);
      Tag    : Database.Crypto.Authentication_Tag;
      R      : Database.Status.Result;
   begin
      R := Database.Crypto.Encrypt (Key, Nonce, AD, Plain, Cipher, Tag);
      Assert (Database.Status.Is_Ok (R), "encrypt succeeds");
      Assert (Cipher /= Plain, "ciphertext differs from plaintext");
      R := Database.Crypto.Decrypt (Key, Nonce, AD, Cipher, Tag, Back);
      Assert (Database.Status.Is_Ok (R), "decrypt succeeds");
      Assert (Back = Plain, "plaintext round trips");
   end Authenticated_Encryption_Round_Trips;

   procedure Empty_Plaintext_And_AD_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Key    : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      Nonce  : constant Database.Crypto.Nonce :=
        Database.Crypto.Generate_Nonce (42, 9);
      AD     : constant Database.Crypto.Byte_Array (1 .. 0) := (others => 0);
      Plain  : constant Database.Crypto.Byte_Array (1 .. 0) := (others => 0);
      Cipher : Database.Crypto.Byte_Array (1 .. 0);
      Back   : Database.Crypto.Byte_Array (1 .. 0);
      Tag    : Database.Crypto.Authentication_Tag;
      R      : Database.Status.Result;
   begin
      R := Database.Crypto.Encrypt (Key, Nonce, AD, Plain, Cipher, Tag);
      Assert (Database.Status.Is_Ok (R), "empty plaintext encrypt succeeds");
      R := Database.Crypto.Decrypt (Key, Nonce, AD, Cipher, Tag, Back);
      Assert (Database.Status.Is_Ok (R), "empty plaintext decrypt succeeds");
      Assert (Back = Plain, "empty plaintext round trips");
   end Empty_Plaintext_And_AD_Round_Trip;

   procedure Tampering_Is_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Salt   : constant Database.Keys.Fixed_Salt := Database.Keys.Default_Salt;
      Key    : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Salt);
      Nonce  : constant Database.Crypto.Nonce :=
        Database.Crypto.Generate_Nonce (42, 7);
      AD     : constant Database.Crypto.Byte_Array (0 .. 0) := (0 => 9);
      Plain  : constant Database.Crypto.Byte_Array (0 .. 3) :=
        (11, 22, 33, 44);
      Cipher : Database.Crypto.Byte_Array (0 .. 3);
      Back   : Database.Crypto.Byte_Array (0 .. 3);
      Tag    : Database.Crypto.Authentication_Tag;
      R      : Database.Status.Result;
   begin
      R := Database.Crypto.Encrypt (Key, Nonce, AD, Plain, Cipher, Tag);
      Assert (Database.Status.Is_Ok (R), "encrypt succeeds");
      Cipher (1) := Cipher (1) xor 16#55#;
      R := Database.Crypto.Decrypt (Key, Nonce, AD, Cipher, Tag, Back);
      Assert
        (R.Code = Database.Status.Authentication_Failure,
         "tampered ciphertext is rejected");
   end Tampering_Is_Rejected;

   procedure Invalid_Key_Is_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bytes : Database.Keys.Key_Bytes (0 .. 30) := (others => 0);
      R     : constant Database.Status.Result :=
        Database.Keys.Validate_Format (Bytes);
   begin
      Assert
        (R.Code = Database.Status.Invalid_Key, "short binary key rejected");
   end Invalid_Key_Is_Rejected;

   procedure Encryption_Metadata_Updates
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB   : Database.Handle;
      Key  : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      R    : Database.Status.Result;
      Meta : Database.Encryption.Encryption_Metadata;
   begin
      Database.Open_In_Memory (DB);
      R :=
        Database.Encryption.Enable_Encryption
          (DB, (Mode => Database.Encryption.Encrypted, Key => Key));
      Assert (Database.Status.Is_Ok (R), "enable encryption succeeds");
      Meta := Database.Encryption.Metadata (DB);
      Assert
        (Meta.Mode = Database.Encryption.Encrypted,
         "metadata reports encrypted mode");
      R := Database.Encryption.Rotate_Key (DB, Key);
      Assert (Database.Status.Is_Ok (R), "key rotation succeeds");
      R := Database.Encryption.Disable_Encryption (DB);
      Assert (Database.Status.Is_Ok (R), "disable encryption succeeds");
   end Encryption_Metadata_Updates;

   procedure Diagnostics_And_Check_Are_Encryption_Aware
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      Tx    : Database.Transactions.Transaction;
      Key   : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      R     : Database.Status.Result;
      Check : Database.Check.Check_Result;
   begin
      Database.Open_In_Memory (DB);
      R :=
        Database.Encryption.Enable_Encryption
          (DB, (Mode => Database.Encryption.Encrypted, Key => Key));
      Assert (Database.Status.Is_Ok (R), "enable encryption succeeds");
      Assert
        (Database.Diagnostics.Encryption_Enabled (DB),
         "safe diagnostics report encryption enabled");
      Assert
        (Database.Diagnostics.Encryption_Format_Version (DB) = 1,
         "safe diagnostics report encryption format");
      Assert
        (Database.Diagnostics.WAL_Encryption_Enabled (DB),
         "safe diagnostics report encrypted WAL");

      Database.Transactions.Begin_Read (DB, Tx);
      Check := Database.Check.Check_Encryption_Metadata (Tx);
      Assert (Check.Success, "encryption metadata check succeeds");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "read transaction commits");
   end Diagnostics_And_Check_Are_Encryption_Aware;

   procedure Encrypted_Artifacts_Are_Persisted_And_Reopened
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant Wide_Wide_String := "encrypted_page_artifact.dbenc";
      Key    : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      Plain  : constant Database.Crypto.Byte_Array (0 .. 7) :=
        (1, 1, 2, 3, 5, 8, 13, 21);
      Back   : Database.Crypto.Byte_Array (0 .. 7);
      R      : Database.Status.Result;
      Read_R : Database.Encrypted_Persistence.Read_Result;
      Check  : Database.Crypto_Checks.Check_Result;
   begin
      R :=
        Database.Encrypted_Persistence.Write_Artifact
          (Path,
           Database.Crypto_Checks.Encrypted_Page_Artifact,
           Key,
           1,
           42,
           1001,
           Plain);
      Assert
        (Database.Status.Is_Ok (R), "encrypted page artifact writes to disk");

      Check :=
        Database.Encrypted_Persistence.Verify_Artifact_File
          (Path, Database.Crypto_Checks.Encrypted_Page_Artifact, Key);
      Assert
        (Database.Status.Is_Ok (Check.Result),
         "persisted encrypted artifact verifies");
      Assert
        (Check.Authenticated_Items = 1,
         "one persisted encrypted artifact authenticated");

      Read_R :=
        Database.Encrypted_Persistence.Read_Artifact
          (Path, Database.Crypto_Checks.Encrypted_Page_Artifact, Key, Back);
      Assert
        (Database.Status.Is_Ok (Read_R.Result),
         "persisted encrypted artifact reopens");
      Assert (Read_R.Header.Object_Id = 42, "object id persisted");
      Assert (Read_R.Header.LSN = 1001, "lsn persisted");
      Assert (Back = Plain, "persisted plaintext round trips after reopen");
   end Encrypted_Artifacts_Are_Persisted_And_Reopened;

   procedure Persisted_Encrypted_Tampering_Is_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path  : constant Wide_Wide_String := "tampered_export_artifact.dbenc";
      Key   : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      Plain : constant Database.Crypto.Byte_Array (0 .. 5) :=
        (10, 20, 30, 40, 50, 60);
      R     : Database.Status.Result;
      Check : Database.Crypto_Checks.Check_Result;
   begin
      R :=
        Database.Encrypted_Persistence.Write_Artifact
          (Path,
           Database.Crypto_Checks.Encrypted_Export_Artifact,
           Key,
           1,
           7,
           8,
           Plain);
      Assert (Database.Status.Is_Ok (R), "encrypted export artifact writes");
      R := Database.Encrypted_Persistence.Tamper_Byte (Path, 96 + 2);
      Assert (Database.Status.Is_Ok (R), "ciphertext tamper applied");
      Check :=
        Database.Encrypted_Persistence.Verify_Artifact_File
          (Path, Database.Crypto_Checks.Encrypted_Export_Artifact, Key);
      Assert
        (not Database.Status.Is_Ok (Check.Result),
         "tampered persisted encrypted export rejected");
      Assert (Check.Failed_Items = 1, "tamper produces one failed item");
   end Persisted_Encrypted_Tampering_Is_Rejected;

   procedure Persisted_Encrypted_Truncation_Is_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path  : constant Wide_Wide_String := "truncated_wal_artifact.dbenc";
      Key   : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("secret", Database.Keys.Default_Salt);
      Plain : constant Database.Crypto.Byte_Array (0 .. 9) :=
        (others => 16#33#);
      R     : Database.Status.Result;
      Check : Database.Crypto_Checks.Check_Result;
   begin
      R :=
        Database.Encrypted_Persistence.Write_Artifact
          (Path,
           Database.Crypto_Checks.Encrypted_WAL_Frame_Artifact,
           Key,
           1,
           9,
           10,
           Plain);
      Assert (Database.Status.Is_Ok (R), "encrypted WAL artifact writes");
      R := Database.Encrypted_Persistence.Truncate_File (Path, 100);
      Assert (Database.Status.Is_Ok (R), "encrypted WAL artifact truncated");
      Check :=
        Database.Encrypted_Persistence.Verify_Artifact_File
          (Path, Database.Crypto_Checks.Encrypted_WAL_Frame_Artifact, Key);
      Assert
        (not Database.Status.Is_Ok (Check.Result),
         "truncated persisted encrypted WAL artifact rejected");
   end Persisted_Encrypted_Truncation_Is_Rejected;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Derived_Key_Is_Reproducible'Access, "derived key reproducible");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Key_Derivation_Uses_Passphrase_And_Salt'Access,
         "key derivation uses passphrase and salt");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Key_Derivation_Accepts_Empty_Inputs'Access,
         "key derivation accepts empty inputs");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Authentication_Binds_Nonce_And_Associated_Data'Access,
         "authentication binds nonce and associated data");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Authenticated_Encryption_Round_Trips'Access,
         "authenticated encryption round trip");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Empty_Plaintext_And_AD_Round_Trip'Access,
         "empty plaintext and ad round trip");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Tampering_Is_Rejected'Access, "tampering rejected");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Invalid_Key_Is_Rejected'Access, "invalid key rejected");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Encryption_Metadata_Updates'Access, "encryption metadata updates");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Diagnostics_And_Check_Are_Encryption_Aware'Access,
         "diagnostics and check are encryption aware");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Encrypted_Artifacts_Are_Persisted_And_Reopened'Access,
         "encrypted artifacts persist and reopen");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Persisted_Encrypted_Tampering_Is_Rejected'Access,
         "persisted encrypted tampering rejected");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Persisted_Encrypted_Truncation_Is_Rejected'Access,
         "persisted encrypted truncation rejected");
   end Register_Tests;
end Encryption_Tests;
