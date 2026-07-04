with Ada.Characters.Conversions;
with Ada.Directories;
with Database.Backup_Format;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Encrypted_Persistence;
with Database.Fault_Hooks;
with Database.Keys;
with Database.WAL;

package body Database.Restore is
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

   procedure Copy_Required (Source, Destination : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Destination)) then
         Ada.Directories.Delete_File (Native (Destination));
      end if;
      Ada.Directories.Copy_File (Native (Source), Native (Destination));
   end Copy_Required;

   function Destination_Page_Path
     (Destination : Wide_Wide_String;
      Page        : Natural) return Wide_Wide_String is
   begin
      return Destination & ".page" & Natural_Image (Page) & ".enc";
   end Destination_Page_Path;

   procedure Delete_If_Exists (Path : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Path)) then
         Ada.Directories.Delete_File (Native (Path));
      end if;
   exception
      when others => null;
   end Delete_If_Exists;

   procedure Delete_Page_Sidecars (Database_Path : Wide_Wide_String) is
      Search      : Ada.Directories.Search_Type;
      Dir_Entry   : Ada.Directories.Directory_Entry_Type;
      Native_Path : constant String := Native (Database_Path);

      function Sidecar_Directory return String is
      begin
         declare
            Dir : constant String := Ada.Directories.Containing_Directory (Native_Path);
         begin
            if Dir'Length = 0 then
               return ".";
            else
               return Dir;
            end if;
         end;
      exception
         when others => return ".";
      end Sidecar_Directory;

      function Sidecar_Base return String is
      begin
         return Ada.Directories.Simple_Name (Native_Path);
      exception
         when others => return Native_Path;
      end Sidecar_Base;
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Sidecar_Directory,
         Pattern   => Sidecar_Base & ".page*.enc",
         Filter    => (Ada.Directories.Ordinary_File => True,
                       others => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
         Delete_If_Exists
           (Ada.Characters.Conversions.To_Wide_Wide_String
              (Ada.Directories.Full_Name (Dir_Entry)));
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         begin
            Ada.Directories.End_Search (Search);
         exception when others => null;
         end;
   end Delete_Page_Sidecars;

   function Any_Page_Sidecar_Exists (Database_Path : Wide_Wide_String) return Boolean is
      Search      : Ada.Directories.Search_Type;
      Native_Path : constant String := Native (Database_Path);
      Found       : Boolean := False;

      function Sidecar_Directory return String is
      begin
         declare
            Dir : constant String := Ada.Directories.Containing_Directory (Native_Path);
         begin
            if Dir'Length = 0 then
               return ".";
            else
               return Dir;
            end if;
         end;
      exception
         when others => return ".";
      end Sidecar_Directory;

      function Sidecar_Base return String is
      begin
         return Ada.Directories.Simple_Name (Native_Path);
      exception
         when others => return Native_Path;
      end Sidecar_Base;
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Sidecar_Directory,
         Pattern   => Sidecar_Base & ".page*.enc",
         Filter    => (Ada.Directories.Ordinary_File => True,
                       others => False));
      Found := Ada.Directories.More_Entries (Search);
      Ada.Directories.End_Search (Search);
      return Found;
   exception
      when others =>
         begin
            Ada.Directories.End_Search (Search);
         exception when others => null;
         end;
         return False;
   end Any_Page_Sidecar_Exists;

   function Restore_Artifacts_Exist (Database_Path : Wide_Wide_String) return Boolean is
   begin
      return Ada.Directories.Exists (Native (Database_Path));
   end Restore_Artifacts_Exist;

   procedure Delete_Restore_Artifacts (Database_Path : Wide_Wide_String) is
   begin
      Delete_If_Exists (Database_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Database_Path));
      Delete_If_Exists (Database_Path & ".fts");
      Delete_If_Exists (Database_Path & ".wal.enc");
      Delete_Page_Sidecars (Database_Path);
   end Delete_Restore_Artifacts;

   function Restore_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String) return Database.Status.Result is
   begin
      return Restore_Physical_Backup (Source, Destination, (Overwrite => False, Verify => True));
   end Restore_Physical_Backup;

   function Restore_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String;
      Options     : Restore_Options) return Database.Status.Result is
      Manifest : Database.Backup_Format.Manifest;
      R        : Database.Status.Result;
   begin
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Restore_Write) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Restore_Write);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Restore) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error, "deterministic crash during restore");
      end if;
      if not Options.Overwrite and then Restore_Artifacts_Exist (Destination) then
         return Database.Status.Failure (Database.Status.Already_Exists, "restore destination exists");
      end if;
      R := Database.Backup_Format.Read_Manifest (Source, Manifest);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Options.Verify then
         R := Database.Backup_Format.Validate_Manifest (Source, Manifest);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      declare
         Temp_Destination : constant Wide_Wide_String := Destination & ".restore.tmp";
      begin
         Delete_Restore_Artifacts (Temp_Destination);
         Copy_Required
           (Database.Backup_Format.Database_Image_Path (Source),
            Temp_Destination);
         if Manifest.WAL_Checksum /= 0 then
            Copy_Required
              (Database.Backup_Format.WAL_Image_Path (Source),
               Database.WAL.WAL_Path (Temp_Destination));
         end if;

         Delete_Restore_Artifacts (Destination);
         Ada.Directories.Rename (Native (Temp_Destination), Native (Destination));
         if Manifest.WAL_Checksum /= 0 then
            Ada.Directories.Rename
              (Native (Database.WAL.WAL_Path (Temp_Destination)),
               Native (Database.WAL.WAL_Path (Destination)));
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         Delete_Restore_Artifacts (Destination & ".restore.tmp");
         return Database.Status.Failure (Database.Status.Restore_Error, "physical restore failed safely");
   end Restore_Physical_Backup;

   function Restore_Encrypted_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key) return Database.Status.Result is
   begin
      return Restore_Encrypted_Physical_Backup (Source, Destination, Key, (Overwrite => False, Verify => True));
   end Restore_Encrypted_Physical_Backup;

   function Restore_Encrypted_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key;
      Options     : Restore_Options) return Database.Status.Result is
      Manifest : Database.Backup_Format.Manifest;
      R        : Database.Status.Result;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encrypted restore requires a valid key");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Restore_Write) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Restore_Write);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Restore) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error,
           "deterministic crash during encrypted restore");
      end if;
      if not Options.Overwrite and then Restore_Artifacts_Exist (Destination) then
         return Database.Status.Failure (Database.Status.Already_Exists, "restore destination exists");
      end if;
      R := Database.Backup_Format.Read_Manifest (Source, Manifest);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Options.Verify then
         R := Database.Backup_Format.Validate_Manifest (Source, Manifest);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;

      if Manifest.Encrypted_Page_Count = 0 then
         return Database.Status.Failure (Database.Status.Corrupt_Backup, "encrypted backup has no page sidecars");
      end if;
      for I in 0 .. Manifest.Encrypted_Page_Count - 1 loop
         declare
            Size  : Natural := 0;
            Check : Database.Crypto_Checks.Check_Result;
         begin
            R := Database.Encrypted_Persistence.Artifact_Plaintext_Size
              (Database.Backup_Format.Encrypted_Page_Image_Path (Source, I),
               Database.Crypto_Checks.Encrypted_Page_Artifact,
               Key, Size);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Check := Database.Encrypted_Persistence.Verify_Artifact_File
              (Database.Backup_Format.Encrypted_Page_Image_Path (Source, I),
               Database.Crypto_Checks.Encrypted_Page_Artifact,
               Key);
            if not Database.Status.Is_Ok (Check.Result) then
               return Check.Result;
            end if;
         end;
      end loop;

      if Ada.Directories.Exists (Native (Database.Backup_Format.Encrypted_Manifest_Image_Path (Source))) then
         declare
            Check : constant Database.Crypto_Checks.Check_Result  :=
              Database.Encrypted_Persistence.Verify_Artifact_File
                (Database.Backup_Format.Encrypted_Manifest_Image_Path (Source),
                 Database.Crypto_Checks.Encrypted_Backup_Manifest_Artifact,
                 Key);
         begin
            if not Database.Status.Is_Ok (Check.Result) then
               return Check.Result;
            end if;
         end;
      end if;

      declare
         Temp_Destination : constant Wide_Wide_String := Destination & ".restore.tmp";
      begin
         Delete_Restore_Artifacts (Temp_Destination);
         Copy_Required
           (Database.Backup_Format.Database_Image_Path (Source),
            Temp_Destination);
         for I in 0 .. Manifest.Encrypted_Page_Count - 1 loop
            Copy_Required
              (Database.Backup_Format.Encrypted_Page_Image_Path (Source, I),
               Destination_Page_Path (Temp_Destination, I));
         end loop;
         if Manifest.WAL_Checksum /= 0 then
            Copy_Required
              (Database.Backup_Format.WAL_Image_Path (Source),
               Database.WAL.WAL_Path (Temp_Destination));
         end if;
         if Manifest.Encrypted_WAL_Checksum /= 0 then
            Copy_Required
              (Database.Backup_Format.Encrypted_WAL_Image_Path (Source),
               Temp_Destination & ".wal.enc");
         end if;

         Delete_Restore_Artifacts (Destination);
         Ada.Directories.Rename (Native (Temp_Destination), Native (Destination));
         for I in 0 .. Manifest.Encrypted_Page_Count - 1 loop
            Ada.Directories.Rename
              (Native (Destination_Page_Path (Temp_Destination, I)),
               Native (Destination_Page_Path (Destination, I)));
         end loop;
         if Manifest.WAL_Checksum /= 0 then
            Ada.Directories.Rename
              (Native (Database.WAL.WAL_Path (Temp_Destination)),
               Native (Database.WAL.WAL_Path (Destination)));
         end if;
         if Manifest.Encrypted_WAL_Checksum /= 0 then
            Ada.Directories.Rename
              (Native (Temp_Destination & ".wal.enc"),
               Native (Destination & ".wal.enc"));
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         Delete_Restore_Artifacts (Destination & ".restore.tmp");
         return Database.Status.Failure (Database.Status.Restore_Error, "encrypted restore failed safely");
   end Restore_Encrypted_Physical_Backup;

end Database.Restore;
