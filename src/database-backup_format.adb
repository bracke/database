with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;
with Database.Log_Sequence;
with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Wide_Wide_Text_IO;
with Database.Storage.Pages;
with Database.WAL;
with Interfaces;

package body Database.Backup_Format is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Interfaces.Unsigned_64;

   Checksum_Modulus : constant Interfaces.Unsigned_64 := 2_147_483_647;

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

   function Join (Left, Right : Wide_Wide_String) return Wide_Wide_String is
   begin
      if Left'Length = 0 then
         return Right;
      elsif Left (Left'Last) = '/' or else Left (Left'Last) = '\' then
         return Left & Right;
      else
         return Left & "/" & Right;
      end if;
   end Join;

   function Manifest_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String is
   begin
      return Join (Backup_Path, "manifest.dbbackup");
   end Manifest_Path;

   function Database_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String is
   begin
      return Join (Backup_Path, "database.image");
   end Database_Image_Path;

   function WAL_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String is
   begin
      return Join (Backup_Path, "database.wal");
   end WAL_Image_Path;

   function Encrypted_Page_Image_Path
     (Backup_Path : Wide_Wide_String;
      Page         : Natural) return Wide_Wide_String is
   begin
      return Join (Backup_Path, "database.page" & Natural_Image (Page) & ".backup.enc");
   end Encrypted_Page_Image_Path;

   function Encrypted_Manifest_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String is
   begin
      return Join (Backup_Path, "manifest.dbbackup.enc");
   end Encrypted_Manifest_Image_Path;

   function Encrypted_WAL_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String is
   begin
      return Join (Backup_Path, "database.wal.enc");
   end Encrypted_WAL_Image_Path;

   function Compute_File_Checksum (Path : Wide_Wide_String) return Natural is
      use Ada.Streams;
      F    : Ada.Streams.Stream_IO.File_Type;
      Buf  : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset;
      Sum  : Interfaces.Unsigned_64 := 0;
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return 0;
      end if;
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, Native (Path));
      while not Ada.Streams.Stream_IO.End_Of_File (F) loop
         Ada.Streams.Stream_IO.Read (F, Buf, Last);
         for I in Buf'First .. Last loop
            Sum := (Sum * 33 + Interfaces.Unsigned_64 (Buf (I))) mod Checksum_Modulus;
         end loop;
      end loop;
      Ada.Streams.Stream_IO.Close (F);
      return Natural (Sum);
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (F) then
               Ada.Streams.Stream_IO.Close (F);
            end if;
         exception
            when others => null;
         end;
         return 0;
   end Compute_File_Checksum;

   function Compute_Encrypted_Page_Sidecar_Checksum
     (Backup_Path : Wide_Wide_String;
      Page_Count  : Natural) return Natural
   is
      Sum : Interfaces.Unsigned_64 := 0;
   begin
      if Page_Count = 0 then
         return 0;
      end if;
      for I in 0 .. Page_Count - 1 loop
         declare
            C : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64
              (Compute_File_Checksum (Encrypted_Page_Image_Path (Backup_Path, I)));
         begin
            Sum := (Sum * 65537 + C + Interfaces.Unsigned_64 (I) + 1) mod Checksum_Modulus;
         end;
      end loop;
      return Natural (Sum);
   end Compute_Encrypted_Page_Sidecar_Checksum;

   procedure Put_Line_WW (F : Ada.Wide_Wide_Text_IO.File_Type; S : Wide_Wide_String) is
   begin
      Ada.Wide_Wide_Text_IO.Put_Line (F, S);
   end Put_Line_WW;

   function Write_Manifest
     (Backup_Path : Wide_Wide_String;
      Item        : Manifest) return Database.Status.Result
   is
      F : Ada.Wide_Wide_Text_IO.File_Type;
   begin
      Ada.Wide_Wide_Text_IO.Create
        (F, Ada.Wide_Wide_Text_IO.Out_File, Native (Manifest_Path (Backup_Path)));
      Put_Line_WW (F, "DATABASE_BACKUP_MANIFEST 1");
      Put_Line_WW (F, "database_format_version=" &
                     Natural'Wide_Wide_Image (Item.Database_Format_Version));
      Put_Line_WW (F, "backup_format_version=" &
                     Natural'Wide_Wide_Image (Item.Backup_Format_Version));
      Put_Line_WW (F, "source_database_id=" &
                     To_Wide_Wide_String (Item.Source_Database_Id));
      Put_Line_WW (F, "created_at=" & To_Wide_Wide_String (Item.Created_At));
      Put_Line_WW (F, "page_size=" & Natural'Wide_Wide_Image (Item.Page_Size));
      Put_Line_WW (F, "page_count=" & Natural'Wide_Wide_Image (Item.Page_Count));
      Put_Line_WW (F, "checkpoint_lsn=" &
                     Database.Log_Sequence.Log_Sequence_Number'Wide_Wide_Image
                       (Item.Checkpoint_LSN));
      Put_Line_WW (F, "backup_target_lsn=" &
                     Database.Log_Sequence.Log_Sequence_Number'Wide_Wide_Image
                       (Item.Backup_Target_LSN));
      Put_Line_WW (F, "wal_start_lsn=" &
                     Database.Log_Sequence.Log_Sequence_Number'Wide_Wide_Image
                       (Item.WAL_Start_LSN));
      Put_Line_WW (F, "wal_end_lsn=" &
                     Database.Log_Sequence.Log_Sequence_Number'Wide_Wide_Image
                       (Item.WAL_End_LSN));
      Put_Line_WW (F, "database_checksum=" &
                     Natural'Wide_Wide_Image (Item.Database_Checksum));
      Put_Line_WW (F, "wal_checksum=" & Natural'Wide_Wide_Image (Item.WAL_Checksum));
      Put_Line_WW (F, "catalog_checksum=" &
                     Natural'Wide_Wide_Image (Item.Catalog_Checksum));
      Put_Line_WW (F, "encrypted_page_count=" &
                     Natural'Wide_Wide_Image (Item.Encrypted_Page_Count));
      Put_Line_WW (F, "encrypted_page_checksum=" &
                     Natural'Wide_Wide_Image (Item.Encrypted_Page_Checksum));
      Put_Line_WW (F, "encrypted_wal_checksum=" &
                     Natural'Wide_Wide_Image (Item.Encrypted_WAL_Checksum));
      Ada.Wide_Wide_Text_IO.Close (F);
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Wide_Wide_Text_IO.Is_Open (F) then
               Ada.Wide_Wide_Text_IO.Close (F);
            end if;
         exception
            when others => null;
         end;
         return Database.Status.Failure
           (Database.Status.Backup_Error, "could not write backup manifest");
   end Write_Manifest;

   procedure Assign
     (Item  : in out Manifest;
      Key   : Wide_Wide_String;
      Value : Wide_Wide_String)
   is
      function N return Natural is (Natural'Wide_Wide_Value (Value));
      function L return Database.Log_Sequence.Log_Sequence_Number is
        (Database.Log_Sequence.Log_Sequence_Number'Wide_Wide_Value (Value));
   begin
      if Key = "database_format_version" then
         Item.Database_Format_Version := N;
      elsif Key = "backup_format_version" then
         Item.Backup_Format_Version := N;
      elsif Key = "source_database_id" then
         Item.Source_Database_Id := To_Unbounded_Wide_Wide_String (Value);
      elsif Key = "created_at" then
         Item.Created_At := To_Unbounded_Wide_Wide_String (Value);
      elsif Key = "page_size" then
         Item.Page_Size := N;
      elsif Key = "page_count" then
         Item.Page_Count := N;
      elsif Key = "checkpoint_lsn" then
         Item.Checkpoint_LSN := L;
      elsif Key = "backup_target_lsn" then
         Item.Backup_Target_LSN := L;
      elsif Key = "wal_start_lsn" then
         Item.WAL_Start_LSN := L;
      elsif Key = "wal_end_lsn" then
         Item.WAL_End_LSN := L;
      elsif Key = "database_checksum" then
         Item.Database_Checksum := N;
      elsif Key = "wal_checksum" then
         Item.WAL_Checksum := N;
      elsif Key = "catalog_checksum" then
         Item.Catalog_Checksum := N;
      elsif Key = "encrypted_page_count" then
         Item.Encrypted_Page_Count := N;
      elsif Key = "encrypted_page_checksum" then
         Item.Encrypted_Page_Checksum := N;
      elsif Key = "encrypted_wal_checksum" then
         Item.Encrypted_WAL_Checksum := N;
      end if;
   end Assign;

   function Read_Manifest
     (Backup_Path : Wide_Wide_String;
      Item        : out Manifest) return Database.Status.Result
   is
      F : Ada.Wide_Wide_Text_IO.File_Type;
   begin
      Item := (others => <>);
      if not Ada.Directories.Exists (Native (Manifest_Path (Backup_Path))) then
         return Database.Status.Failure
           (Database.Status.Corrupt_Backup, "backup manifest is missing");
      end if;
      Ada.Wide_Wide_Text_IO.Open
        (F, Ada.Wide_Wide_Text_IO.In_File, Native (Manifest_Path (Backup_Path)));
      if Ada.Wide_Wide_Text_IO.End_Of_File (F) then
         Ada.Wide_Wide_Text_IO.Close (F);
         return Database.Status.Failure
           (Database.Status.Corrupt_Backup, "backup manifest is empty");
      end if;
      declare
         Header : constant Wide_Wide_String := Ada.Wide_Wide_Text_IO.Get_Line (F);
      begin
         if Header /= "DATABASE_BACKUP_MANIFEST 1" then
            Ada.Wide_Wide_Text_IO.Close (F);
            return Database.Status.Failure
              (Database.Status.Incompatible_Backup, "unsupported backup manifest");
         end if;
      end;
      while not Ada.Wide_Wide_Text_IO.End_Of_File (F) loop
         declare
            Line : constant Wide_Wide_String := Ada.Wide_Wide_Text_IO.Get_Line (F);
            Eq   : Natural := 0;
         begin
            for I in Line'Range loop
               if Line (I) = '=' then
                  Eq := I;
                  exit;
               end if;
            end loop;
            if Eq > Line'First then
               Assign (Item, Line (Line'First .. Eq - 1), Line (Eq + 1 .. Line'Last));
            end if;
         end;
      end loop;
      Ada.Wide_Wide_Text_IO.Close (F);
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Wide_Wide_Text_IO.Is_Open (F) then
               Ada.Wide_Wide_Text_IO.Close (F);
            end if;
         exception when others => null;
         end;
         return Database.Status.Failure
           (Database.Status.Corrupt_Backup, "could not read backup manifest");
   end Read_Manifest;

   function Validate_Manifest
     (Backup_Path : Wide_Wide_String;
      Item        : Manifest) return Database.Status.Result
   is
      DB_Image : constant Wide_Wide_String := Database_Image_Path (Backup_Path);
      WAL_Image : constant Wide_Wide_String := WAL_Image_Path (Backup_Path);
   begin
      if Item.Backup_Format_Version /= Backup_Format_Version then
         return Database.Status.Failure
           (Database.Status.Incompatible_Backup, "unsupported backup format version");
      end if;
      if not Ada.Directories.Exists (Native (DB_Image)) then
         return Database.Status.Failure
           (Database.Status.Corrupt_Backup, "database image is missing");
      end if;
      if Compute_File_Checksum (DB_Image) /= Item.Database_Checksum then
         return Database.Status.Failure
           (Database.Status.Corrupt_Backup, "database image checksum mismatch");
      end if;
      if Item.WAL_Checksum /= 0 then
         if not Ada.Directories.Exists (Native (WAL_Image)) then
            return Database.Status.Failure
              (Database.Status.Corrupt_Backup, "WAL image is missing");
         end if;
         if Compute_File_Checksum (WAL_Image) /= Item.WAL_Checksum then
            return Database.Status.Failure
              (Database.Status.Corrupt_Backup, "WAL checksum mismatch");
         end if;
      end if;

      --  Encrypted backups use authenticated page/WAL sidecars. The manifest
      --  must describe the exact sidecar set so restore cannot silently use a
      --  stale, missing, swapped, or truncated sidecar artifact.
      if Item.Encrypted_Page_Count /= 0 or else Item.Encrypted_Page_Checksum /= 0 then
         if Item.Encrypted_Page_Count /= Item.Page_Count then
            return Database.Status.Failure
              (Database.Status.Corrupt_Backup, "encrypted page sidecar count mismatch");
         end if;
         for I in 0 .. Item.Encrypted_Page_Count - 1 loop
            if not Ada.Directories.Exists
              (Native (Encrypted_Page_Image_Path (Backup_Path, I)))
            then
               return Database.Status.Failure
                 (Database.Status.Corrupt_Backup, "encrypted page sidecar is missing");
            end if;
         end loop;
         if Compute_Encrypted_Page_Sidecar_Checksum
              (Backup_Path, Item.Encrypted_Page_Count) /= Item.Encrypted_Page_Checksum
         then
            return Database.Status.Failure
              (Database.Status.Corrupt_Backup, "encrypted page sidecar checksum mismatch");
         end if;
      end if;

      if Item.Encrypted_WAL_Checksum /= 0 then
         if not Ada.Directories.Exists (Native (Encrypted_WAL_Image_Path (Backup_Path))) then
            return Database.Status.Failure
              (Database.Status.Corrupt_Backup, "encrypted WAL sidecar is missing");
         end if;
         if Compute_File_Checksum
              (Encrypted_WAL_Image_Path (Backup_Path)) /= Item.Encrypted_WAL_Checksum
         then
            return Database.Status.Failure
              (Database.Status.Corrupt_Backup, "encrypted WAL sidecar checksum mismatch");
         end if;
      end if;

      return Database.Status.Success;
   end Validate_Manifest;
end Database.Backup_Format;
