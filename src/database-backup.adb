with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Backup_Format;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Encrypted_Persistence;
with Database.Fault_Hooks;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.WAL;

package body Database.Backup is
   use type Ada.Directories.File_Kind;
   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   function Natural_Image (Value : Natural) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Natural'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Natural_Image;

   procedure Ensure_Directory (Path : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Path)) then
         if Ada.Directories.Kind (Native (Path)) /= Ada.Directories.Directory then
            Ada.Directories.Delete_File (Native (Path));
            Ada.Directories.Create_Path (Native (Path));
         end if;
      else
         Ada.Directories.Create_Path (Native (Path));
      end if;
   end Ensure_Directory;

   procedure Copy_If_Exists (Source, Destination : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Source)) then
         if Ada.Directories.Exists (Native (Destination)) then
            Ada.Directories.Delete_File (Native (Destination));
         end if;
         Ada.Directories.Copy_File (Native (Source), Native (Destination));
      end if;
   end Copy_If_Exists;

   function Base_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Options     : Backup_Options;
      Encrypted   : Boolean;
      Key         : Database.Keys.Encryption_Key) return Database.Status.Result is
      Source_Path : constant Wide_Wide_String := Database.Storage.File_IO.Path (DB.File);
      Page_Count  : Natural;
      Manifest    : Database.Backup_Format.Manifest;
      R           : Database.Status.Result;
   begin
      if not Database.Is_Open (DB) or else DB.Kind /= Persistent_Backend then
         return Database.Status.Failure (Database.Status.Not_Open, "backup requires an open persistent database");
      end if;
      if DB.Lock.Writer_Active then
         return Database.Status.Failure (Database.Status.Transaction_Conflict, "backup rejected active writer");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Backup_Copy) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Backup_Copy);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Backup) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error, "deterministic crash during backup");
      end if;
      if Encrypted and then not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encrypted backup requires a valid key");
      end if;

      R := Database.Storage.File_IO.Flush (DB.File);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Ensure_Directory (Destination);
      Copy_If_Exists (Source_Path, Database.Backup_Format.Database_Image_Path (Destination));
      if Options.Include_WAL and then Database.WAL.Exists (Source_Path) then
         Copy_If_Exists (Database.WAL.WAL_Path (Source_Path), Database.Backup_Format.WAL_Image_Path (Destination));
      end if;

      Page_Count := Database.Storage.File_IO.Page_Count (DB.File);
      if Encrypted then
         Page_Count := Natural'Max (Page_Count, 2);
         for I in 0 .. Page_Count - 1 loop
            Copy_If_Exists
              (Source_Path & ".page" & Natural_Image (I) & ".enc",
               Database.Backup_Format.Encrypted_Page_Image_Path (Destination, I));
         end loop;
         if Options.Include_WAL then
            Copy_If_Exists
              (Source_Path & ".wal.enc",
               Database.Backup_Format.Encrypted_WAL_Image_Path (Destination));
         end if;
      end if;

      Manifest.Database_Format_Version := 1;
      Manifest.Backup_Format_Version := Database.Backup_Format.Backup_Format_Version;
      Manifest.Source_Database_Id := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Source_Path);
      Manifest.Created_At := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("deterministic");
      Manifest.Page_Size := Database.Storage.Pages.Page_Size;
      Manifest.Page_Count := Page_Count;
      Manifest.Database_Checksum := Database.Backup_Format.Compute_File_Checksum
        (Database.Backup_Format.Database_Image_Path (Destination));
      Manifest.WAL_Checksum := Database.Backup_Format.Compute_File_Checksum
        (Database.Backup_Format.WAL_Image_Path (Destination));
      if Encrypted then
         Manifest.Encrypted_Page_Count := Page_Count;
         Manifest.Encrypted_Page_Checksum  :=
           Database.Backup_Format.Compute_Encrypted_Page_Sidecar_Checksum
             (Destination, Page_Count);
         Manifest.Encrypted_WAL_Checksum := Database.Backup_Format.Compute_File_Checksum
           (Database.Backup_Format.Encrypted_WAL_Image_Path (Destination));
      end if;

      R := Database.Backup_Format.Write_Manifest (Destination, Manifest);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Options.Verify_After_Copy then
         R := Database.Backup_Format.Validate_Manifest (Destination, Manifest);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      if Encrypted then
         declare
            Empty : constant Database.Crypto.Byte_Array (0 .. 0) := (others => 0);
         begin
            R := Database.Encrypted_Persistence.Write_Artifact
              (Database.Backup_Format.Encrypted_Manifest_Image_Path (Destination),
               Database.Crypto_Checks.Encrypted_Backup_Manifest_Artifact,
               Key, 1, 0, 0, Empty);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end;
      end if;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure (Database.Status.Backup_Error, "physical backup failed safely");
   end Base_Physical_Backup;

   function Create_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String) return Database.Status.Result is
   begin
      return Create_Physical_Backup (DB, Destination, (Include_WAL => True, Verify_After_Copy => True,
        Force_Checkpoint => False));
   end Create_Physical_Backup;

   function Create_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Options     : Backup_Options) return Database.Status.Result is
   begin
      return Base_Physical_Backup (DB, Destination, Options, False, Database.Keys.Empty_Key);
   end Create_Physical_Backup;

   function Create_Encrypted_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key) return Database.Status.Result is
   begin
      return Create_Encrypted_Physical_Backup
        (DB, Destination, Key,
         (Include_WAL => True, Verify_After_Copy => True, Force_Checkpoint => False));
   end Create_Encrypted_Physical_Backup;

   function Create_Encrypted_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key;
      Options     : Backup_Options) return Database.Status.Result is
   begin
      return Base_Physical_Backup (DB, Destination, Options, True, Key);
   end Create_Encrypted_Physical_Backup;

end Database.Backup;
