with Database.Status;
with Database.Storage.Pages;
with Database.Metrics;
with Database.Fault_Hooks;
with Database.Encrypted_Persistence;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Keys;
with Database.Log_Sequence;
with Database.Tracing;
with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Wide_Wide_Unbounded;
with Interfaces.C;

package body Database.Storage.File_IO is
   use Ada.Streams;
   use Ada.Streams.Stream_IO;
   use Database.Storage.Pages;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Interfaces.C.int;

   Invalid_Lock_FD : constant Interfaces.C.int := Interfaces.C.int'First;
   O_RDONLY : constant Interfaces.C.int := 0;
   O_RDWR  : constant Interfaces.C.int := 2;
   O_CREAT : constant Interfaces.C.int := 64;
   O_DIRECTORY : constant Interfaces.C.int := 16#10000#;
   Mode_RW : constant Interfaces.C.int := 8#666#;
   LOCK_EX : constant Interfaces.C.int := 2;
   LOCK_NB : constant Interfaces.C.int := 4;
   LOCK_UN : constant Interfaces.C.int := 8;

   function C_Open
     (Path  : Interfaces.C.char_array;
      Flags : Interfaces.C.int;
      Mode  : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "open";

   function C_Close (FD : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "close";

   function C_Flock
     (FD        : Interfaces.C.int;
      Operation : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "flock";

   function C_Fsync (FD : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "fsync";

   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   function Parent_Directory (Path : Wide_Wide_String) return String is
      Native_Path : constant String := Native (Path);
      Dir         : constant String := Ada.Directories.Containing_Directory (Native_Path);
   begin
      if Dir'Length = 0 then
         return ".";
      end if;
      return Dir;
   exception
      when others =>
         return ".";
   end Parent_Directory;

   function Sync_FD (FD : Interfaces.C.int) return Database.Status.Result is
   begin
      if FD = Invalid_Lock_FD then
         return Database.Status.Success;
      end if;
      if C_Fsync (FD) /= 0 then
         return Database.Status.Failure
           (Database.Status.IOError, "could not fsync database file");
      end if;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError, "could not fsync database file");
   end Sync_FD;

   function Sync_File_Path (Path : Wide_Wide_String) return Database.Status.Result is
      FD : Interfaces.C.int;
      R  : Database.Status.Result;
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return Database.Status.Success;
      end if;
      FD := C_Open (Interfaces.C.To_C (Native (Path)), O_RDWR, Mode_RW);
      if FD < 0 then
         return Database.Status.Failure
           (Database.Status.IOError, "could not open database file for fsync");
      end if;
      R := Sync_FD (FD);
      declare
         Close_Result : constant Interfaces.C.int := C_Close (FD);
         pragma Unreferenced (Close_Result);
      begin
         return R;
      end;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError, "could not fsync database file");
   end Sync_File_Path;

   function Sync_Parent_Directory (Path : Wide_Wide_String) return Database.Status.Result is
      Dir : constant String := Parent_Directory (Path);
      FD  : Interfaces.C.int;
   begin
      FD := C_Open (Interfaces.C.To_C (Dir), O_RDONLY + O_DIRECTORY, Mode_RW);
      if FD < 0 then
         return Database.Status.Failure
           (Database.Status.IOError, "could not open database directory for fsync");
      end if;
      declare
         Fsync_Result : constant Interfaces.C.int := C_Fsync (FD);
         Close_Result : constant Interfaces.C.int := C_Close (FD);
         pragma Unreferenced (Close_Result);
      begin
         if Fsync_Result /= 0 then
            return Database.Status.Failure
              (Database.Status.IOError, "could not fsync database directory");
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError, "could not fsync database directory");
   end Sync_Parent_Directory;

   function Acquire_Process_Lock
     (F              : in out File_Handle;
      Path           : Wide_Wide_String;
      Create_If_Need : Boolean) return Database.Status.Result is
      Flags : Interfaces.C.int := O_RDWR;
      FD    : Interfaces.C.int;
   begin
      if F.Lock_FD /= Invalid_Lock_FD then
         return Database.Status.Failure
           (Database.Status.Already_Open, "database file lock already held");
      end if;

      if Create_If_Need then
         Flags := Flags + O_CREAT;
      end if;

      FD := C_Open (Interfaces.C.To_C (Native (Path)), Flags, Mode_RW);
      if FD < 0 then
         return Database.Status.Failure
           (Database.Status.IOError, "could not open database file for process lock");
      end if;

      if C_Flock (FD, LOCK_EX + LOCK_NB) /= 0 then
         declare
            Ignored : constant Interfaces.C.int := C_Close (FD);
            pragma Unreferenced (Ignored);
         begin
            return Database.Status.Failure
              (Database.Status.Lock_Error,
               "database file is locked by another process");
         end;
      end if;

      F.Lock_FD := FD;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.Lock_Error, "could not acquire database process lock");
   end Acquire_Process_Lock;

   procedure Release_Process_Lock (F : in out File_Handle) is
   begin
      if F.Lock_FD /= Invalid_Lock_FD then
         declare
            Unlock_Result : constant Interfaces.C.int := C_Flock (F.Lock_FD, LOCK_UN);
            Close_Result  : constant Interfaces.C.int := C_Close (F.Lock_FD);
            pragma Unreferenced (Unlock_Result, Close_Result);
         begin
            F.Lock_FD := Invalid_Lock_FD;
         end;
      end if;
   exception
      when others =>
         F.Lock_FD := Invalid_Lock_FD;
   end Release_Process_Lock;

   function Natural_Image (Value : Natural) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Natural'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Natural_Image;

   procedure Delete_Encrypted_Page_Sidecars (Database_Path : Wide_Wide_String) is
      Search : Ada.Directories.Search_Type;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
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
         when others =>
            return ".";
      end Sidecar_Directory;

      function Sidecar_Base return String is
      begin
         return Ada.Directories.Simple_Name (Native_Path);
      exception
         when others =>
            return Native_Path;
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
         begin
            Ada.Directories.Delete_File (Ada.Directories.Full_Name (Dir_Entry));
         exception
            when others => null;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         begin
            Ada.Directories.End_Search (Search);
         exception
            when others => null;
         end;
   end Delete_Encrypted_Page_Sidecars;

   procedure Delete_Encrypted_Page_Sidecars_From
     (Database_Path : Wide_Wide_String;
      First_Removed : Natural) is
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
         when others =>
            return ".";
      end Sidecar_Directory;

      function Sidecar_Base return String is
      begin
         return Ada.Directories.Simple_Name (Native_Path);
      exception
         when others =>
            return Native_Path;
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
         declare
            Name   : constant String  :=
              Ada.Directories.Simple_Name (Ada.Directories.Full_Name (Dir_Entry));
            Prefix : constant String := Sidecar_Base & ".page";
            Suffix : constant String := ".enc";
         begin
            if Name'Length > Prefix'Length + Suffix'Length
              and then Name (Name'First .. Name'First + Prefix'Length - 1) = Prefix
              and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix
            then
               declare
                  First_Digit : constant Natural := Name'First + Prefix'Length;
                  Last_Digit  : constant Natural := Name'Last - Suffix'Length;
                  Page_No     : Natural := 0;
                  Valid       : Boolean := True;
               begin
                  for J in First_Digit .. Last_Digit loop
                     if Name (J) not in '0' .. '9' then
                        Valid := False;
                     else
                        Page_No := Page_No * 10
                          + Character'Pos (Name (J)) - Character'Pos ('0');
                     end if;
                  end loop;
                  if Valid and then Page_No >= First_Removed then
                     begin
                        Ada.Directories.Delete_File
                          (Ada.Directories.Full_Name (Dir_Entry));
                     exception
                        when others => null;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         begin
            Ada.Directories.End_Search (Search);
         exception
            when others => null;
         end;
   end Delete_Encrypted_Page_Sidecars_From;

   function Encrypted_Page_Path (F : File_Handle; Id : Page_Id) return Wide_Wide_String is
   begin
      return Path (F) & ".page" & Natural_Image (Natural (Id)) & ".enc";
   end Encrypted_Page_Path;

   function To_Crypto (S : Stream_Element_Array) return Database.Crypto.Byte_Array is
      B : Database.Crypto.Byte_Array (0 .. Natural (S'Length) - 1);
   begin
      for I in B'Range loop
         B (I) := Database.Crypto.Byte (S (S'First + Stream_Element_Offset (I)));
      end loop;
      return B;
   end To_Crypto;

   function To_Stream (B : Database.Crypto.Byte_Array) return Stream_Element_Array is
      S : Stream_Element_Array (0 .. Stream_Element_Offset (B'Length - 1));
   begin
      for I in B'Range loop
         S (Stream_Element_Offset (I - B'First)) := Stream_Element (B (I));
      end loop;
      return S;
   end To_Stream;

   procedure Enable_Encryption
     (F   : in out File_Handle;
      Key : Database.Keys.Encryption_Key) is
   begin
      F.Encrypted := Database.Keys.Is_Valid (Key);
      F.Key := Key;
   end Enable_Encryption;

   procedure Disable_Encryption (F : in out File_Handle) is
   begin
      F.Encrypted := False;
      F.Key := Database.Keys.Empty_Key;
   end Disable_Encryption;

   function Create_Encrypted
     (F    : in out File_Handle;
      Path : Wide_Wide_String;
      Key  : Database.Keys.Encryption_Key) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encrypted create requires valid key");
      end if;
      Enable_Encryption (F, Key);
      R := Create (F, Path);
      if not Database.Status.Is_Ok (R) then
         Disable_Encryption (F);
      end if;
      return R;
   end Create_Encrypted;

   function Open_Encrypted
     (F    : in out File_Handle;
      Path : Wide_Wide_String;
      Key  : Database.Keys.Encryption_Key) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure (Database.Status.Invalid_Key, "encrypted open requires valid key");
      end if;
      Enable_Encryption (F, Key);
      R := Open (F, Path);
      if not Database.Status.Is_Ok (R) then
         Disable_Encryption (F);
      end if;
      return R;
   end Open_Encrypted;

   function Is_Open (F : File_Handle) return Boolean is (F.Opened);
   function Path (F : File_Handle) return Wide_Wide_String is (To_Wide_Wide_String (F.Name));
   function File_Exists (Path : Wide_Wide_String) return Boolean is (Ada.Directories.Exists (Native (Path)));

   function Ensure_Mode
     (F    : in out File_Handle;
      Mode : Ada.Streams.Stream_IO.File_Mode) return Database.Status.Result is
      Current_Path : constant Wide_Wide_String := Path (F);
   begin
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;
      if Ada.Streams.Stream_IO.Mode (F.File) /= Mode then
         if Ada.Streams.Stream_IO.Mode (F.File) /= In_File then
            Ada.Streams.Stream_IO.Flush (F.File);
         end if;
         Ada.Streams.Stream_IO.Close (F.File);
         Ada.Streams.Stream_IO.Open (F.File, Mode, Native (Current_Path));
      end if;
      return Database.Status.Success;
   exception
      when others =>
         F.Opened := False;
         return Database.Status.Failure (Database.Status.IOError, "could not switch file mode");
   end Ensure_Mode;

   function Ensure_Carrier_Page
     (F  : in out File_Handle;
      Id : Page_Id) return Database.Status.Result is
      Zeros : constant Stream_Element_Array
        (0 .. Stream_Element_Offset (Page_Size - 1)) := (others => 0);
      R : Database.Status.Result;
   begin
      --  Encrypted page contents live in authenticated sidecar artifacts.
      --  The raw file is still extended with zero-filled placeholder pages so
      --  Page_Count, allocation, truncation, and integrity tooling observe the
      --  same physical page cardinality after close/reopen without leaking
      --  plaintext page bytes.
      R := Ensure_Mode (F, Out_File);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Set_Index (F.File, Positive_Count (Natural (Id) * Page_Size + 1));
      Write (F.File, Zeros);
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError,
            "could not extend encrypted database carrier file");
   end Ensure_Carrier_Page;

   function Encrypt_Existing_Pages
     (F   : in out File_Handle;
      Key : Database.Keys.Encryption_Key) return Database.Status.Result is
      Count : Natural;
      Last  : Stream_Element_Offset;
      R     : Database.Status.Result;
   begin
      if not Database.Keys.Is_Valid (Key) then
         return Database.Status.Failure
           (Database.Status.Invalid_Key, "encrypted rewrite requires valid key");
      end if;
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;

      R := Flush (F);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Ensure_Mode (F, In_File);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Count := Page_Count (F);
      if Count > 0 then
         for I in 0 .. Count - 1 loop
            declare
               S     : Stream_Element_Array (0 .. Stream_Element_Offset (Page_Size - 1));
               Page  : Database.Storage.Pages.Page;
               Plain : Database.Crypto.Byte_Array (0 .. Page_Size - 1);
            begin
               Set_Index (F.File, Positive_Count (I * Page_Size + 1));
               Read (F.File, S, Last);
               if Last /= S'Last then
                  return Database.Status.Failure
                    (Database.Status.Corrupt_File, "short page read during encrypted rewrite");
               end if;

               Page := From_Stream (S);
               R := Validate
                 (Page,
                  Page_Id (I),
                  Database.Storage.Pages.Get_Kind (Page));
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;

               Plain := To_Crypto (S);
               R := Database.Encrypted_Persistence.Write_Artifact
                 (Path (F) & ".page" & Natural_Image (I) & ".enc",
                  Database.Crypto_Checks.Encrypted_Page_Artifact,
                  Key,
                  1,
                  I,
                  Database.Log_Sequence.Log_Sequence_Number (I),
                  Plain);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end;
         end loop;
      end if;

      Enable_Encryption (F, Key);
      if Count > 0 then
         for I in 0 .. Count - 1 loop
            R := Ensure_Carrier_Page (F, Page_Id (I));
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end loop;
      end if;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError, "could not rewrite existing pages as encrypted artifacts");
   end Encrypt_Existing_Pages;

   function Delete_File (Path : Wide_Wide_String) return Database.Status.Result is
   begin
      --  Encrypted page contents are stored as sidecar artifacts named
      --  <database>.pageN.enc.  Deleting the carrier must delete these
      --  authenticated page artifacts too;
      --  otherwise recreating a database
      --  with the same path and key could accidentally expose stale pages.
      Delete_Encrypted_Page_Sidecars (Path);
      if Ada.Directories.Exists (Native (Path)) then
         Ada.Directories.Delete_File (Native (Path));
      end if;
      return Sync_Parent_Directory (Path);
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "delete file failed");
   end Delete_File;

   function Create (F : in out File_Handle; Path : Wide_Wide_String) return Database.Status.Result is
      P : Page;
      Lock_Result : Database.Status.Result;
   begin
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Allocation_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Allocation_Failure);
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Random_IO_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Random_IO_Failure);
      end if;
      if F.Opened then
         return Database.Status.Failure (Database.Status.Already_Open, "file already open");
      end if;
      Lock_Result := Acquire_Process_Lock (F, Path, Create_If_Need => True);
      if not Database.Status.Is_Ok (Lock_Result) then
         return Lock_Result;
      end if;
      Delete_Encrypted_Page_Sidecars (Path);
      Ada.Streams.Stream_IO.Create (F.File, Out_File, Native (Path));
      F.Opened := True;
      F.Name := To_Unbounded_Wide_Wide_String (Path);
      Initialize (P, 0, Header_Page);
      declare
         Magic : constant Byte_Array (0 .. 7) := (16#44#,16#41#,16#54#,16#41#,16#42#,16#36#,16#00#,16#01#);
         R     : Database.Status.Result;
      begin
         Set_Payload (P, Magic);
         R := Write_Page (F, P);
         if not Database.Status.Is_Ok (R) then
            declare
               Close_Result  : constant Database.Status.Result := Close (F);
               Delete_Result : constant Database.Status.Result := Delete_File (Path);
               pragma Unreferenced (Close_Result, Delete_Result);
            begin
               return R;
            end;
         end if;
      end;
      Initialize (P, 1, Catalog_Page);
      declare
         R : Database.Status.Result := Write_Page (F, P);
      begin
         if not Database.Status.Is_Ok (R) then
            declare
               Close_Result  : constant Database.Status.Result := Close (F);
               Delete_Result : constant Database.Status.Result := Delete_File (Path);
               pragma Unreferenced (Close_Result, Delete_Result);
            begin
               return R;
            end;
         end if;
         R := Flush (F);
         if not Database.Status.Is_Ok (R) then
            declare
               Close_Result  : constant Database.Status.Result := Close (F);
               Delete_Result : constant Database.Status.Result := Delete_File (Path);
               pragma Unreferenced (Close_Result, Delete_Result);
            begin
               return R;
            end;
         end if;
         R := Sync_Parent_Directory (Path);
         if not Database.Status.Is_Ok (R) then
            declare
               Close_Result  : constant Database.Status.Result := Close (F);
               Delete_Result : constant Database.Status.Result := Delete_File (Path);
               pragma Unreferenced (Close_Result, Delete_Result);
            begin
               return R;
            end;
         end if;
         return Database.Status.Success;
      end;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (F.File) then
               Ada.Streams.Stream_IO.Close (F.File);
            end if;
         exception
            when others => null;
         end;
         Release_Process_Lock (F);
         F.Opened := False;
         Delete_Encrypted_Page_Sidecars (Path);
         if Ada.Directories.Exists (Native (Path)) then
            begin
               Ada.Directories.Delete_File (Native (Path));
            exception
               when others => null;
            end;
         end if;
         return Database.Status.Failure (Database.Status.IOError, "could not create database file");
   end Create;

   function Open (F : in out File_Handle; Path : Wide_Wide_String) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
   begin
      if F.Opened then
         return Database.Status.Failure (Database.Status.Already_Open, "file already open");
      end if;
      R := Acquire_Process_Lock (F, Path, Create_If_Need => False);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Ada.Streams.Stream_IO.Open (F.File, In_File, Native (Path));
      F.Opened := True;
      F.Name := To_Unbounded_Wide_Wide_String (Path);
      R := Read_Page (F, 0, Header_Page, P);
      if not Database.Status.Is_Ok (R) then
         declare
            Close_Result : constant Database.Status.Result := Close (F);
            pragma Unreferenced (Close_Result);
         begin
            return R;
         end;
      end if;
      declare
         M : constant Byte_Array := Payload (P);
      begin
         if M'Length < 8
           or else M (0) /= 16#44#
           or else M (1) /= 16#41#
           or else M (2) /= 16#54#
           or else M (3) /= 16#41#
         then
            declare
               Close_Result : constant Database.Status.Result := Close (F);
               pragma Unreferenced (Close_Result);
            begin
               return Database.Status.Failure (Database.Status.Invalid_File, "invalid database file header");
            end;
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         Release_Process_Lock (F);
         F.Opened := False;
         return Database.Status.Failure (Database.Status.IOError, "could not open database file");
   end Open;

   function Close (F : in out File_Handle) return Database.Status.Result is
   begin
      if F.Opened then
         Ada.Streams.Stream_IO.Close (F.File);
         F.Opened := False;
      end if;
      Release_Process_Lock (F);
      return Database.Status.Success;
   exception
      when others =>
         Release_Process_Lock (F);
         return Database.Status.Failure (Database.Status.IOError, "close failed");
   end Close;

   function Flush (F : in out File_Handle) return Database.Status.Result is
   begin
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Random_IO_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Random_IO_Failure);
      end if;
      if Ada.Streams.Stream_IO.Mode (F.File) /= In_File then
         Ada.Streams.Stream_IO.Flush (F.File);
      end if;
      return Sync_FD (F.Lock_FD);
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "flush failed");
   end Flush;

   function Page_Count (F : in out File_Handle) return Natural is
      Size : constant Ada.Streams.Stream_IO.Count := Ada.Streams.Stream_IO.Size (F.File);
   begin
      return Natural (Size / Ada.Streams.Stream_IO.Count (Page_Size));
   exception
      when others => return 0;
   end Page_Count;

   function Truncate_To_Page_Count
     (F     : in out File_Handle;
      Count : Natural) return Database.Status.Result is
      Old_Path : constant Wide_Wide_String := Path (F);
      Tmp_Path : constant Wide_Wide_String := Old_Path & ".truncate.tmp";
      Inp : File_Type;
      Outp : File_Type;
      Buf : Stream_Element_Array (0 .. Stream_Element_Offset (Page_Size - 1));
      Last : Stream_Element_Offset;
      R : Database.Status.Result;
   begin
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;
      R := Flush (F);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Ada.Streams.Stream_IO.Close (F.File);
      F.Opened := False;
      Ada.Streams.Stream_IO.Open (Inp, In_File, Native (Old_Path));
      Ada.Streams.Stream_IO.Create (Outp, Out_File, Native (Tmp_Path));
      if Count > 0 then
         for I in 0 .. Count - 1 loop
            Set_Index (Inp, Positive_Count (I * Page_Size + 1));
            Read (Inp, Buf, Last);
            if Last /= Buf'Last then
               Close (Inp);
               Close (Outp);
               begin
                  if Ada.Directories.Exists (Native (Tmp_Path)) then
                     Ada.Directories.Delete_File (Native (Tmp_Path));
                  end if;
               exception
                  when others => null;
               end;
               Ada.Streams.Stream_IO.Open (F.File, In_File, Native (Old_Path));
               F.Opened := True;
               return Database.Status.Failure (Database.Status.Corrupt_File, "short read during truncate");
            end if;
            Write (Outp, Buf);
         end loop;
      end if;
      Close (Inp);
      Ada.Streams.Stream_IO.Flush (Outp);
      Close (Outp);
      R := Sync_File_Path (Tmp_Path);
      if not Database.Status.Is_Ok (R) then
         if Ada.Directories.Exists (Native (Tmp_Path)) then
            Ada.Directories.Delete_File (Native (Tmp_Path));
         end if;
         Ada.Streams.Stream_IO.Open (F.File, In_File, Native (Old_Path));
         F.Opened := True;
         return R;
      end if;
      if Ada.Directories.Exists (Native (Old_Path)) then
         Ada.Directories.Delete_File (Native (Old_Path));
      end if;
      Ada.Directories.Rename (Native (Tmp_Path), Native (Old_Path));
      R := Sync_Parent_Directory (Old_Path);
      if not Database.Status.Is_Ok (R) then
         Ada.Streams.Stream_IO.Open (F.File, In_File, Native (Old_Path));
         F.Opened := True;
         return R;
      end if;
      if F.Encrypted then
         Delete_Encrypted_Page_Sidecars_From (Old_Path, Count);
      end if;
      Ada.Streams.Stream_IO.Open (F.File, In_File, Native (Old_Path));
      F.Opened := True;
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Is_Open (Inp) then
               Close (Inp);
            end if;
            if Is_Open (Outp) then
               Close (Outp);
            end if;
            if not F.Opened then
               Ada.Streams.Stream_IO.Open
                 (F.File,
                  In_File,
                  Native (Old_Path));
               F.Opened := True;
            end if;
         exception
            when others =>
               null;
         end;
         return Database.Status.Failure (Database.Status.IOError, "truncate failed");
   end Truncate_To_Page_Count;

   function Read_Page
     (F    : in out File_Handle;
      Id   : Page_Id;
      Kind : Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result is
      S : Stream_Element_Array (0 .. Stream_Element_Offset (Page_Size - 1));
      Last : Stream_Element_Offset;
      R : Database.Status.Result;
   begin
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Random_IO_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Random_IO_Failure);
      end if;
      if not F.Encrypted then
         R := Ensure_Mode (F, In_File);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      if F.Encrypted then
         declare
            Plain : Database.Crypto.Byte_Array (0 .. Page_Size - 1);
            RR : Database.Encrypted_Persistence.Read_Result;
         begin
            RR := Database.Encrypted_Persistence.Read_Artifact
              (Encrypted_Page_Path (F, Id),
               Database.Crypto_Checks.Encrypted_Page_Artifact,
               F.Key, Plain);
            if not Database.Status.Is_Ok (RR.Result) then
               return RR.Result;
            end if;
            S := To_Stream (Plain);
         end;
      else
         Set_Index (F.File, Positive_Count (Natural (Id) * Page_Size + 1));
         Read (F.File, S, Last);
         if Last /= S'Last then
            return Database.Status.Failure (Database.Status.Corrupt_File, "short page read");
         end if;
      end if;
      Page := From_Stream (S);
      Database.Metrics.Increment_Page_Reads;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Storage_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("page read"), False));
      R := Validate (Page, Id, Kind);
      return R;
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "page read failed");
   end Read_Page;

   function Read_Raw_Page
     (F    : in out File_Handle;
      Id   : Page_Id;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result is
      S : Stream_Element_Array (0 .. Stream_Element_Offset (Page_Size - 1));
      Last : Stream_Element_Offset;
      R : Database.Status.Result;
   begin
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Random_IO_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Random_IO_Failure);
      end if;
      if not F.Encrypted then
         R := Ensure_Mode (F, In_File);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      if F.Encrypted then
         declare
            Plain : Database.Crypto.Byte_Array (0 .. Page_Size - 1);
            RR : Database.Encrypted_Persistence.Read_Result;
         begin
            RR := Database.Encrypted_Persistence.Read_Artifact
              (Encrypted_Page_Path (F, Id),
               Database.Crypto_Checks.Encrypted_Page_Artifact,
               F.Key, Plain);
            if not Database.Status.Is_Ok (RR.Result) then
               return RR.Result;
            end if;
            S := To_Stream (Plain);
         end;
      else
         Set_Index (F.File, Positive_Count (Natural (Id) * Page_Size + 1));
         Read (F.File, S, Last);
         if Last /= S'Last then
            return Database.Status.Failure (Database.Status.Corrupt_File, "short page read");
         end if;
      end if;
      Page := From_Stream (S);
      Database.Metrics.Increment_Page_Reads;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Storage_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("raw page read"), False));
      return Validate (Page, Id, Get_Kind (Page));
   exception
      when others => return Database.Status.Failure (Database.Status.Corrupt_File, "raw page read failed");
   end Read_Raw_Page;

   function Write_Page
     (F    : in out File_Handle;
      Page : Database.Storage.Pages.Page) return Database.Status.Result is
      S : Stream_Element_Array := To_Stream (Page);
      Kind : constant Page_Kind := Get_Kind (Page);
      R : constant Database.Status.Result := Validate (Page, Get_Id (Page), Kind);
   begin
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if not F.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "file not open");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Random_IO_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Random_IO_Failure);
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Page_Write) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Page_Write);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Page_Rewrite) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error,
           "deterministic crash during page rewrite");
      end if;

      if F.Encrypted then
         if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Corrupt_Page) then
            return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Corrupt_Page);
         end if;
         declare
            Plain : constant Database.Crypto.Byte_Array := To_Crypto (S);
            ER : constant Database.Status.Result := Database.Encrypted_Persistence.Write_Artifact
              (Encrypted_Page_Path (F, Get_Id (Page)),
               Database.Crypto_Checks.Encrypted_Page_Artifact,
               F.Key,
               1,
               Natural (Get_Id (Page)),
               Database.Log_Sequence.Log_Sequence_Number (Natural (Get_Id (Page))),
               Plain);
         begin
            if not Database.Status.Is_Ok (ER) then
               return ER;
            end if;
            declare
               Carrier_R : constant Database.Status.Result  :=
                 Ensure_Carrier_Page (F, Get_Id (Page));
            begin
               if not Database.Status.Is_Ok (Carrier_R) then
                  return Carrier_R;
               end if;
            end;
         end;
      else
         declare
            Mode_Result : constant Database.Status.Result := Ensure_Mode (F, Out_File);
         begin
            if not Database.Status.Is_Ok (Mode_Result) then
               return Mode_Result;
            end if;
         end;
         Set_Index (F.File, Positive_Count (Natural (Get_Id (Page)) * Page_Size + 1));
         if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Corrupt_Page) then
            S (0) := 0;
            Write (F.File, S);
            return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Corrupt_Page);
         end if;
         Write (F.File, S);
      end if;

      Database.Metrics.Increment_Page_Writes;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Storage_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("page write"), False));
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "page write failed");
   end Write_Page;
end Database.Storage.File_IO;
