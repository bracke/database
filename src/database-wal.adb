with Ada.Characters.Conversions;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Metrics;
with Database.Fault_Hooks;
with Database.Log_Sequence;
with Database.Status;
with Database.Tracing;
with Database.WAL.Payload_Rules;
with Interfaces.C;

package body Database.WAL is
   use type Database.Log_Sequence.Log_Sequence_Number;
   use Ada.Streams;
   use Ada.Streams.Stream_IO;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Database.Log_Sequence;
   use Database.Storage.Pages;
   use type Interfaces.C.int;

   Header_Size : constant := 40;
   Magic : constant Stream_Element_Array (0 .. 7)  :=
     (Stream_Element (Character'Pos ('D')), Stream_Element (Character'Pos ('B')),
      Stream_Element (Character'Pos ('W')), Stream_Element (Character'Pos ('A')),
      Stream_Element (Character'Pos ('L')), Stream_Element (Character'Pos ('1')),
      Stream_Element (Character'Pos ('7')), 0);
   O_RDONLY : constant Interfaces.C.int := 0;
   O_RDWR : constant Interfaces.C.int := 2;
   O_DIRECTORY : constant Interfaces.C.int := 16#10000#;
   Mode_RW : constant Interfaces.C.int := 8#666#;

   function C_Open
     (Path  : Interfaces.C.char_array;
      Flags : Interfaces.C.int;
      Mode  : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "open";

   function C_Close (FD : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "close";

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

   function Sync_File_Path (Path : Wide_Wide_String) return Database.Status.Result is
      FD : Interfaces.C.int;
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return Database.Status.Success;
      end if;
      FD := C_Open (Interfaces.C.To_C (Native (Path)), O_RDWR, Mode_RW);
      if FD < 0 then
         return Database.Status.Failure
           (Database.Status.IOError, "could not open WAL file for fsync");
      end if;
      declare
         Fsync_Result : constant Interfaces.C.int := C_Fsync (FD);
         Close_Result : constant Interfaces.C.int := C_Close (FD);
         pragma Unreferenced (Close_Result);
      begin
         if Fsync_Result /= 0 then
            return Database.Status.Failure
              (Database.Status.IOError, "could not fsync WAL file");
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError, "could not fsync WAL file");
   end Sync_File_Path;

   function Sync_Parent_Directory (Path : Wide_Wide_String) return Database.Status.Result is
      Dir : constant String := Parent_Directory (Path);
      FD  : Interfaces.C.int;
   begin
      FD := C_Open (Interfaces.C.To_C (Dir), O_RDONLY + O_DIRECTORY, Mode_RW);
      if FD < 0 then
         return Database.Status.Failure
           (Database.Status.IOError, "could not open WAL directory for fsync");
      end if;
      declare
         Fsync_Result : constant Interfaces.C.int := C_Fsync (FD);
         Close_Result : constant Interfaces.C.int := C_Close (FD);
         pragma Unreferenced (Close_Result);
      begin
         if Fsync_Result /= 0 then
            return Database.Status.Failure
              (Database.Status.IOError, "could not fsync WAL directory");
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.IOError, "could not fsync WAL directory");
   end Sync_Parent_Directory;

   function WAL_Path (Database_Path : Wide_Wide_String) return Wide_Wide_String is
   begin
      return Database_Path & ".wal";
   end WAL_Path;

   function Exists (Database_Path : Wide_Wide_String) return Boolean is
   begin
      return Ada.Directories.Exists (Native (WAL_Path (Database_Path)));
   end Exists;

   function Ensure_Mode
     (W    : in out WAL_Handle;
      Mode : Ada.Streams.Stream_IO.File_Mode) return Database.Status.Result is
      P : constant Wide_Wide_String := To_Wide_Wide_String (W.DB_Path);
   begin
      if not W.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "WAL not open");
      end if;
      if Ada.Streams.Stream_IO.Mode (W.File) /= Mode then
         if Ada.Streams.Stream_IO.Mode (W.File) /= In_File then
            Ada.Streams.Stream_IO.Flush (W.File);
            declare
               R : constant Database.Status.Result := Sync_File_Path (WAL_Path (P));
            begin
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end;
         end if;
         Ada.Streams.Stream_IO.Close (W.File);
         Ada.Streams.Stream_IO.Open (W.File, Mode, Native (WAL_Path (P)));
      end if;
      return Database.Status.Success;
   exception
      when others =>
         W.Opened := False;
         return Database.Status.Failure (Database.Status.IOError, "could not switch WAL file mode");
   end Ensure_Mode;

   function Delete (Database_Path : Wide_Wide_String) return Database.Status.Result is
      P : constant String := Native (WAL_Path (Database_Path));
   begin
      if Ada.Directories.Exists (P) then
         Ada.Directories.Delete_File (P);
      end if;
      return Sync_Parent_Directory (WAL_Path (Database_Path));
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "could not delete WAL file");
   end Delete;

   procedure Put_U32 (B : in out Stream_Element_Array; Offset : Stream_Element_Offset; V : Natural) is
   begin
      B (Offset + 0) := Stream_Element ((V / 16#1000000#) mod 256);
      B (Offset + 1) := Stream_Element ((V / 16#10000#) mod 256);
      B (Offset + 2) := Stream_Element ((V / 16#100#) mod 256);
      B (Offset + 3) := Stream_Element (V mod 256);
   end Put_U32;

   function Get_U32 (B : Stream_Element_Array; Offset : Stream_Element_Offset) return Natural is
   begin
      return Natural (B (Offset + 0)) * 16#1000000#
        + Natural (B (Offset + 1)) * 16#10000#
        + Natural (B (Offset + 2)) * 16#100#
        + Natural (B (Offset + 3));
   end Get_U32;

   procedure Put_U64 (B : in out Stream_Element_Array; Offset : Stream_Element_Offset; V : Log_Sequence_Number) is
      X : Log_Sequence_Number := V;
   begin
      for I in reverse 0 .. 7 loop
         B (Offset + Stream_Element_Offset (I)) := Stream_Element (X mod 256);
         X := X / 256;
      end loop;
   end Put_U64;

   function Get_U64 (B : Stream_Element_Array; Offset : Stream_Element_Offset) return Log_Sequence_Number is
      R : Log_Sequence_Number := 0;
   begin
      for I in 0 .. 7 loop
         R := R * 256 + Log_Sequence_Number (B (Offset + Stream_Element_Offset (I)));
      end loop;
      return R;
   end Get_U64;

   function Kind_Code (K : Record_Kind) return Natural is
   begin
      case K is
         when Page_Frame             => return 1;
         when Commit_Record          => return 2;
         when Checkpoint_Record      => return 3;
         when Full_Text_Redo_Record  => return 4;
         when Full_Text_Undo_Record  => return 5;
      end case;
   end Kind_Code;

   function Decode_Kind (Code : Natural; K : out Record_Kind) return Boolean is
   begin
      case Code is
         when 1 => K := Page_Frame;
         return True;
         when 2 => K := Commit_Record;
         return True;
         when 3 => K := Checkpoint_Record;
         return True;
         when 4 => K := Full_Text_Redo_Record;
         return True;
         when 5 => K := Full_Text_Undo_Record;
         return True;
         when others => return False;
      end case;
   end Decode_Kind;

   function Is_Full_Text_Page
     (Page : Database.Storage.Pages.Page) return Boolean is
      Kind : constant Page_Kind := Get_Kind (Page);
   begin
      return Kind = Full_Text_Dictionary_Page
        or else Kind = Full_Text_Posting_Page;
   end Is_Full_Text_Page;

   function Checksum (H : Stream_Element_Array; Payload : Stream_Element_Array) return Natural is
      S : Natural := 0;
   begin
      for I in H'Range loop
         if I < 36 or else I > 39 then
            S := S + Natural (H (I));
         end if;
      end loop;
      for I in Payload'Range loop
         S := S + Natural (Payload (I));
      end loop;
      return S;
   end Checksum;

   function Normalize_For_Append
     (Database_Path : Wide_Wide_String) return Database.Status.Result;

   procedure Load_Generator_From_File (W : in out WAL_Handle) is
      H : Stream_Element_Array (0 .. Header_Size - 1);
      Last_Read : Stream_Element_Offset;
   begin
      Database.Log_Sequence.Reset (W.Generator);
      Set_Index (W.File, 1);
      while not End_Of_File (W.File) loop
         Read (W.File, H, Last_Read);
         exit when Last_Read /= H'Last;
         Database.Log_Sequence.Observe (W.Generator, Get_U64 (H, 9));
         declare
            Len : constant Natural := Get_U32 (H, 26);
         begin
            exit when Len = 0 and then End_Of_File (W.File);
            if Len > 0 then
               Set_Index (W.File, Positive_Count (Index (W.File) + Ada.Streams.Stream_IO.Count (Len)));
            end if;
         end;
      end loop;
   exception
      when others =>
         Database.Log_Sequence.Reset (W.Generator);
   end Load_Generator_From_File;

   function Create (W : in out WAL_Handle; Database_Path : Wide_Wide_String) return Database.Status.Result is
   begin
      if W.Opened then
         return Database.Status.Failure (Database.Status.Already_Open, "WAL already open");
      end if;
      Ada.Streams.Stream_IO.Create (W.File, Out_File, Native (WAL_Path (Database_Path)));
      Ada.Streams.Stream_IO.Close (W.File);
      Ada.Streams.Stream_IO.Open (W.File, Out_File, Native (WAL_Path (Database_Path)));
      W.Opened := True;
      W.DB_Path := To_Unbounded_Wide_Wide_String (Database_Path);
      Database.Log_Sequence.Reset (W.Generator);
      W.Durable_Pos := Database.Log_Sequence.Invalid_LSN;
      declare
         R : Database.Status.Result;
      begin
         Ada.Streams.Stream_IO.Flush (W.File);
         R := Sync_File_Path (WAL_Path (Database_Path));
         if not Database.Status.Is_Ok (R) then
            declare
               Close_Result : constant Database.Status.Result := Close (W);
               pragma Unreferenced (Close_Result);
            begin
               return R;
            end;
         end if;
         R := Sync_Parent_Directory (WAL_Path (Database_Path));
         if not Database.Status.Is_Ok (R) then
            declare
               Close_Result : constant Database.Status.Result := Close (W);
               pragma Unreferenced (Close_Result);
            begin
               return R;
            end;
         end if;
      end;
      return Database.Status.Success;
   exception
      when others =>
         W.Opened := False;
         return Database.Status.Failure (Database.Status.IOError, "could not create WAL file");
   end Create;

   function Open (W : in out WAL_Handle; Database_Path : Wide_Wide_String) return Database.Status.Result is
   begin
      if W.Opened then
         return Database.Status.Failure (Database.Status.Already_Open, "WAL already open");
      end if;
      if not Exists (Database_Path) then
         return Create (W, Database_Path);
      end if;
      declare
         Normalize_Result : constant Database.Status.Result  :=
           Normalize_For_Append (Database_Path);
      begin
         if not Database.Status.Is_Ok (Normalize_Result) then
            return Normalize_Result;
         end if;
      end;
      Ada.Streams.Stream_IO.Open (W.File, In_File, Native (WAL_Path (Database_Path)));
      W.Opened := True;
      W.DB_Path := To_Unbounded_Wide_Wide_String (Database_Path);
      Load_Generator_From_File (W);
      return Database.Status.Success;
   exception
      when others =>
         W.Opened := False;
         return Database.Status.Failure (Database.Status.IOError, "could not open WAL file");
   end Open;

   function Close (W : in out WAL_Handle) return Database.Status.Result is
   begin
      if W.Opened then
         Ada.Streams.Stream_IO.Close (W.File);
         W.Opened := False;
      end if;
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "could not close WAL file");
   end Close;

   function Is_Open (W : WAL_Handle) return Boolean is (W.Opened);
   function Durable_LSN (W : WAL_Handle) return Log_Sequence_Number is (W.Durable_Pos);

   function Flush (W : in out WAL_Handle) return Database.Status.Result is
   begin
      if not W.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "WAL not open");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_WAL_Flush) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_WAL_Flush);
      end if;
      if Ada.Streams.Stream_IO.Mode (W.File) /= In_File then
         Ada.Streams.Stream_IO.Flush (W.File);
      end if;
      declare
         R : constant Database.Status.Result :=
           Sync_File_Path (WAL_Path (To_Wide_Wide_String (W.DB_Path)));
      begin
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end;
      W.Durable_Pos := Database.Log_Sequence.Current (W.Generator);
      Database.Metrics.Increment_WAL_Flushes;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        To_Unbounded_Wide_Wide_String ("WAL flush"), False));
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "WAL flush failed");
   end Flush;

   function Append_Record
     (W              : in out WAL_Handle;
      K              : Record_Kind;
      Transaction_Id : Natural;
      Page_Id_Value  : Natural;
      Page_Kind_Code : Natural;
      Payload        : Stream_Element_Array;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      H : Stream_Element_Array (0 .. Header_Size - 1) := (others => 0);
   begin
      if not W.Opened then
         return Database.Status.Failure (Database.Status.Not_Open, "WAL not open");
      end if;
      declare
         Mode_Result : constant Database.Status.Result := Ensure_Mode (W, Append_File);
      begin
         if not Database.Status.Is_Ok (Mode_Result) then
            return Mode_Result;
         end if;
      end;
      LSN := Database.Log_Sequence.Allocate (W.Generator);
      for I in Magic'Range loop
         H (I) := Magic (I);
      end loop;
      H (8) := Stream_Element (Kind_Code (K));
      Put_U64 (H, 9, LSN);
      Put_U32 (H, 17, Transaction_Id);
      Put_U32 (H, 21, Page_Id_Value);
      H (25) := Stream_Element (Page_Kind_Code);
      Put_U32 (H, 26, Payload'Length);
      Put_U32 (H, 30, Header_Size);
      Put_U32 (H, 36, Checksum (H, Payload));
      --  Keep WAL writes append-only.  Do not reopen an existing WAL in
      --  output mode for append, because output-mode implementations may
      --  reset or overwrite existing file contents.  Append_File preserves
      --  prior durable frames and positions writes at end-of-file.

      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Truncate_WAL) then
         --  Persist a torn frame prefix so recovery validation exercises the
         --  same path as a power loss during WAL append.  The append itself
         --  reports a structured failure;
         --  later Validate/Replay must stop
         --  safely at the incomplete frame.
         Write (W.File, H (0 .. 15));
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Truncate_WAL);
      end if;

      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Corrupt_WAL_Frame) then
         H (0) := 0;
         Write (W.File, H);
         if Payload'Length > 0 then
            Write (W.File, Payload);
         end if;
         Database.Metrics.Add_WAL_Bytes (Header_Size + Payload'Length);
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Corrupt_WAL_Frame);
      end if;

      Write (W.File, H);
      if Payload'Length > 0 then
         Write (W.File, Payload);
      end if;
      Database.Metrics.Add_WAL_Bytes (Header_Size + Payload'Length);
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        To_Unbounded_Wide_Wide_String ("WAL append"), False));
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.IOError, "WAL append failed");
   end Append_Record;

   function Append_Page_Frame
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      Payload : constant Stream_Element_Array := To_Stream (Page);
   begin
      return Append_Record
        (W, Page_Frame, Transaction_Id, Natural (Get_Id (Page)), Page_Kind'Pos (Get_Kind (Page)), Payload, LSN);
   end Append_Page_Frame;

   function Append_Full_Text_Image
     (W              : in out WAL_Handle;
      K              : Record_Kind;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      Payload : constant Stream_Element_Array := To_Stream (Page);
   begin
      if not Is_Full_Text_Page (Page) then
         LSN := Database.Log_Sequence.Invalid_LSN;
         return Database.Status.Failure
           (Database.Status.Invalid_Argument,
            "full-text WAL image requires a full-text page");
      end if;

      return Append_Record
        (W, K, Transaction_Id, Natural (Get_Id (Page)),
         Page_Kind'Pos (Get_Kind (Page)), Payload, LSN);
   end Append_Full_Text_Image;

   function Append_Full_Text_Redo
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result is
   begin
      return Append_Full_Text_Image
        (W, Full_Text_Redo_Record, Transaction_Id, Page, LSN);
   end Append_Full_Text_Redo;

   function Append_Full_Text_Undo
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Database.Log_Sequence.Log_Sequence_Number) return Database.Status.Result is
   begin
      return Append_Full_Text_Image
        (W, Full_Text_Undo_Record, Transaction_Id, Page, LSN);
   end Append_Full_Text_Undo;

   function Append_Commit
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Commit_Version : Natural;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      Payload : Stream_Element_Array (0 .. 3) := (others => 0);
      R       : Database.Status.Result;
   begin
      if Database.Fault_Hooks.Should_Crash
        (Database.Fault_Hooks.Before_WAL_Commit_Marker)
      then
         LSN := Database.Log_Sequence.Invalid_LSN;
         return Database.Status.Failure
           (Database.Status.Fault_Injection_Error,
            "deterministic crash before WAL commit marker");
      end if;

      Put_U32 (Payload, 0, Commit_Version);
      R := Append_Record (W, Commit_Record, Transaction_Id, 0, 0, Payload, LSN);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      if Database.Fault_Hooks.Should_Crash
        (Database.Fault_Hooks.After_WAL_Commit_Marker)
      then
         return Database.Status.Failure
           (Database.Status.Fault_Injection_Error,
            "deterministic crash after WAL commit marker");
      end if;

      return Database.Status.Success;
   end Append_Commit;

   function Append_Checkpoint
     (W   : in out WAL_Handle;
      LSN : out Log_Sequence_Number) return Database.Status.Result is
      Empty : Stream_Element_Array (1 .. 0);
   begin
      return Append_Record (W, Checkpoint_Record, 0, 0, 0, Empty, LSN);
   end Append_Checkpoint;

   package Natural_Vectors is new Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Natural);

   function Is_Committed (Ids : Natural_Vectors.Vector; Tx_Id : Natural) return Boolean is
   begin
      for Id of Ids loop
         if Id = Tx_Id then
            return True;
         end if;
      end loop;
      return False;
   end Is_Committed;

   function Apply_Page_Image
     (F                  : in out Database.Storage.File_IO.File_Handle;
      Payload            : Stream_Element_Array;
      LSN                : Log_Sequence_Number;
      Require_Full_Text  : Boolean) return Database.Status.Result is
      P            : Database.Storage.Pages.Page := From_Stream (Payload);
      Existing     : Database.Storage.Pages.Page;
      Read_R       : Database.Status.Result;
      Should_Write : Boolean := True;
   begin
      if Require_Full_Text and then not Is_Full_Text_Page (P) then
         return Database.Status.Failure
           (Database.Status.WAL_Corruption,
            "full-text WAL image contains non-full-text page");
      end if;

      Read_R := Database.Storage.File_IO.Read_Raw_Page
        (F, Database.Storage.Pages.Get_Id (P), Existing);
      if Database.Status.Is_Ok (Read_R)
        and then Database.Storage.Pages.Last_LSN (Existing) >= LSN
      then
         Should_Write := False;
      end if;

      if Should_Write then
         Set_Last_LSN (P, LSN);
         return Database.Storage.File_IO.Write_Page (F, P);
      end if;

      return Database.Status.Success;
   end Apply_Page_Image;

   function Read_Header
     (File : in out File_Type;
      H    : out Stream_Element_Array) return Boolean is
      Last : Stream_Element_Offset;
   begin
      Read (File, H, Last);
      return Last = H'Last;
   exception
      when others => return False;
   end Read_Header;

   function Validate_Header
     (H : Stream_Element_Array;
      Payload : Stream_Element_Array;
      Last_LSN : in out Log_Sequence_Number;
      K : out Record_Kind;
      LSN : out Log_Sequence_Number) return Database.Status.Result is
      Code : constant Natural := Natural (H (8));
   begin
      for I in Magic'Range loop
         if H (I) /= Magic (I) then
            return Database.Status.Failure (Database.Status.WAL_Corruption, "invalid WAL magic");
         end if;
      end loop;
      if not Decode_Kind (Code, K) then
         return Database.Status.Failure (Database.Status.WAL_Corruption, "invalid WAL record kind");
      end if;
      LSN := Get_U64 (H, 9);
      if LSN <= Last_LSN then
         return Database.Status.Failure (Database.Status.Invalid_LSN, "WAL LSN order violation");
      end if;
      if Get_U32 (H, 36) /= Checksum (H, Payload) then
         return Database.Status.Failure (Database.Status.WAL_Corruption, "WAL checksum mismatch");
      end if;
      Last_LSN := LSN;
      return Database.Status.Success;
   end Validate_Header;

   function Validate_Payload_Length
     (H   : Stream_Element_Array;
      Len : Natural) return Database.Status.Result is
      K : Record_Kind;
   begin
      --  Bound WAL payload allocation before reading the payload.  Fuzzed or
      --  corrupted headers must not be able to request arbitrary memory.
      for I in Magic'Range loop
         if H (I) /= Magic (I) then
            return Database.Status.Failure
              (Database.Status.WAL_Corruption, "invalid WAL magic");
         end if;
      end loop;

      if not Decode_Kind (Natural (H (8)), K) then
         return Database.Status.Failure
           (Database.Status.WAL_Corruption, "invalid WAL record kind");
      end if;

      if not Database.WAL.Payload_Rules.Payload_Length_Is_Valid (K, Len) then
         case K is
            when Page_Frame =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL page-frame payload length");
            when Commit_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL commit payload length");
            when Checkpoint_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL checkpoint payload length");
            when Full_Text_Redo_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL full-text redo payload length");
            when Full_Text_Undo_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL full-text undo payload length");
         end case;
      end if;

      return Database.Status.Success;
   end Validate_Payload_Length;

   function Truncate_WAL_File
     (Database_Path : Wide_Wide_String;
      New_Size      : Natural) return Database.Status.Result is
      Source_Path : constant Wide_Wide_String := WAL_Path (Database_Path);
      Tmp_Path    : constant Wide_Wide_String := Source_Path & ".normalize.tmp";
      Inp         : File_Type;
      Outp        : File_Type;
      Buffer      : Stream_Element_Array (0 .. 8191);
      Remaining   : Natural := New_Size;
      R           : Database.Status.Result;
   begin
      if Ada.Directories.Exists (Native (Tmp_Path)) then
         Ada.Directories.Delete_File (Native (Tmp_Path));
      end if;

      if New_Size = 0 then
         Ada.Streams.Stream_IO.Create (Outp, Out_File, Native (Tmp_Path));
         Ada.Streams.Stream_IO.Flush (Outp);
         Ada.Streams.Stream_IO.Close (Outp);
      else
         Ada.Streams.Stream_IO.Open (Inp, In_File, Native (Source_Path));
         Ada.Streams.Stream_IO.Create (Outp, Out_File, Native (Tmp_Path));
         while Remaining > 0 loop
            declare
               Want : constant Natural := Natural'Min (Remaining, Buffer'Length);
               Last : Stream_Element_Offset;
            begin
               Read (Inp, Buffer (0 .. Stream_Element_Offset (Want - 1)), Last);
               if Last /= Stream_Element_Offset (Want - 1) then
                  Ada.Streams.Stream_IO.Close (Inp);
                  Ada.Streams.Stream_IO.Close (Outp);
                  if Ada.Directories.Exists (Native (Tmp_Path)) then
                     Ada.Directories.Delete_File (Native (Tmp_Path));
                  end if;
                  return Database.Status.Failure
                    (Database.Status.WAL_Corruption,
                     "could not normalize torn WAL suffix");
               end if;
               Write (Outp, Buffer (0 .. Stream_Element_Offset (Want - 1)));
               Remaining := Remaining - Want;
            end;
         end loop;
         Ada.Streams.Stream_IO.Close (Inp);
         Ada.Streams.Stream_IO.Flush (Outp);
         Ada.Streams.Stream_IO.Close (Outp);
      end if;

      R := Sync_File_Path (Tmp_Path);
      if not Database.Status.Is_Ok (R) then
         if Ada.Directories.Exists (Native (Tmp_Path)) then
            Ada.Directories.Delete_File (Native (Tmp_Path));
         end if;
         return R;
      end if;
      Ada.Directories.Delete_File (Native (Source_Path));
      Ada.Directories.Rename (Native (Tmp_Path), Native (Source_Path));
      return Sync_Parent_Directory (Source_Path);
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (Inp) then
               Ada.Streams.Stream_IO.Close (Inp);
            end if;
            if Ada.Streams.Stream_IO.Is_Open (Outp) then
               Ada.Streams.Stream_IO.Close (Outp);
            end if;
            if Ada.Directories.Exists (Native (Tmp_Path)) then
               Ada.Directories.Delete_File (Native (Tmp_Path));
            end if;
         exception
            when others => null;
         end;
         return Database.Status.Failure
           (Database.Status.IOError, "could not truncate torn WAL suffix");
   end Truncate_WAL_File;

   function Normalize_For_Append
     (Database_Path : Wide_Wide_String) return Database.Status.Result is
      File      : File_Type;
      H         : Stream_Element_Array (0 .. Header_Size - 1);
      Last_LSN  : Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      K         : Record_Kind;
      L         : Log_Sequence_Number;
      Good_Size : Natural := 0;
      File_Size : Natural := 0;
      R         : Database.Status.Result;
   begin
      if not Exists (Database_Path) then
         return Database.Status.Success;
      end if;

      File_Size := Natural (Ada.Directories.Size (Native (WAL_Path (Database_Path))));
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)));
      while not End_Of_File (File) loop
         declare
            Frame_Start : constant Positive_Count := Index (File);
         begin
            if not Read_Header (File, H) then
               exit;
            end if;
            declare
               Len   : constant Natural := Get_U32 (H, 26);
               Len_R : constant Database.Status.Result := Validate_Payload_Length (H, Len);
            begin
               if not Database.Status.Is_Ok (Len_R) then
                  Ada.Streams.Stream_IO.Close (File);
                  return Len_R;
               end if;

               if Len = 0 then
                  declare
                     Empty : Stream_Element_Array (1 .. 0);
                  begin
                     R := Validate_Header (H, Empty, Last_LSN, K, L);
                  end;
                  if not Database.Status.Is_Ok (R) then
                     Ada.Streams.Stream_IO.Close (File);
                     return R;
                  end if;
               else
                  declare
                     Payload      : Stream_Element_Array (0 .. Stream_Element_Offset (Len - 1));
                     Payload_Last : Stream_Element_Offset;
                  begin
                     Read (File, Payload, Payload_Last);
                     if Payload_Last /= Payload'Last then
                        --  Only an incomplete final frame is normalized away.
                        exit;
                     end if;
                     R := Validate_Header (H, Payload, Last_LSN, K, L);
                     if not Database.Status.Is_Ok (R) then
                        Ada.Streams.Stream_IO.Close (File);
                        return R;
                     end if;
                  end;
               end if;

               Good_Size := Natural (Index (File) - 1);
               pragma Assert (Good_Size >= Natural (Frame_Start));
            end;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);

      if Good_Size < File_Size then
         return Truncate_WAL_File (Database_Path, Good_Size);
      end if;
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception
            when others => null;
         end;
         return Database.Status.Failure
           (Database.Status.IOError, "could not normalize WAL for append");
   end Normalize_For_Append;

   function Validate (Database_Path : Wide_Wide_String) return Database.Status.Result is
      File : File_Type;
      H : Stream_Element_Array (0 .. Header_Size - 1);
      Last : Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      K : Record_Kind;
      L : Log_Sequence_Number;
   begin
      if not Exists (Database_Path) then
         return Database.Status.Success;
      end if;
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)));
      while not End_Of_File (File) loop
         if not Read_Header (File, H) then
            Ada.Streams.Stream_IO.Close (File);
            return Database.Status.Failure (Database.Status.WAL_Corruption, "torn WAL record header");
         end if;
         declare
            Len : constant Natural := Get_U32 (H, 26);
            Len_R : constant Database.Status.Result := Validate_Payload_Length (H, Len);
         begin
            if not Database.Status.Is_Ok (Len_R) then
               Ada.Streams.Stream_IO.Close (File);
               return Len_R;
            end if;
            if Len = 0 then
               declare
                  Empty : Stream_Element_Array (1 .. 0);
                  R : constant Database.Status.Result := Validate_Header (H, Empty, Last, K, L);
               begin
                  if not Database.Status.Is_Ok (R) then
                     Ada.Streams.Stream_IO.Close (File);
                     return R;
                  end if;
               end;
            else
               declare
                  Payload : Stream_Element_Array (0 .. Stream_Element_Offset (Len - 1));
                  Payload_Last : Stream_Element_Offset;
               begin
                  Read (File, Payload, Payload_Last);
                  if Payload_Last /= Payload'Last then
                     Ada.Streams.Stream_IO.Close (File);
                     return Database.Status.Failure (Database.Status.WAL_Corruption, "torn WAL record payload");
                  end if;
                  declare
                     R : constant Database.Status.Result := Validate_Header (H, Payload, Last, K, L);
                  begin
                     if not Database.Status.Is_Ok (R) then
                        Ada.Streams.Stream_IO.Close (File);
                        return R;
                     end if;
                  end;
               end;
            end if;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception
            when others =>
               null;
         end;
         return Database.Status.Failure
           (Database.Status.IOError, "WAL validation failed");
   end Validate;

   function Replay_Committed
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result is
      File : File_Type;
      H : Stream_Element_Array (0 .. Header_Size - 1);
      Last : Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      K : Record_Kind;
      L : Log_Sequence_Number;
      Committed : Natural_Vectors.Vector;
      R : Database.Status.Result;
   begin
      if not Exists (Database_Path) then
         return Database.Status.Success;
      end if;
      Database.Metrics.Increment_WAL_Replays;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        To_Unbounded_Wide_Wide_String ("WAL replay start"), False));
      --  Replay is intentionally more permissive than Validate: a power loss
      --  may leave one incomplete trailing frame.  Complete frames must still
      --  validate strictly, while a short final header or payload terminates
      --  replay at the last complete durable record.
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)));
      while not End_Of_File (File) loop
         exit when not Read_Header (File, H);
         declare
            Len : constant Natural := Get_U32 (H, 26);
            Len_R : constant Database.Status.Result := Validate_Payload_Length (H, Len);
         begin
            if not Database.Status.Is_Ok (Len_R) then
               Ada.Streams.Stream_IO.Close (File);
               return Len_R;
            end if;
            if Len = 0 then
               declare
                  Empty : Stream_Element_Array (1 .. 0);
               begin
                  R := Validate_Header (H, Empty, Last, K, L);
               end;
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (File);
                  return R;
               end if;
            else
               declare
                  Payload : Stream_Element_Array (0 .. Stream_Element_Offset (Len - 1));
                  Payload_Last : Stream_Element_Offset;
               begin
                  Read (File, Payload, Payload_Last);
                  exit when Payload_Last /= Payload'Last;
                  R := Validate_Header (H, Payload, Last, K, L);
                  if not Database.Status.Is_Ok (R) then
                     Ada.Streams.Stream_IO.Close (File);
                     return R;
                  end if;
               end;
            end if;
            if K = Commit_Record then
               Committed.Append (Get_U32 (H, 17));
            end if;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);

      Last := Database.Log_Sequence.Invalid_LSN;
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)));
      while not End_Of_File (File) loop
         exit when not Read_Header (File, H);
         declare
            Len : constant Natural := Get_U32 (H, 26);
            Len_R : constant Database.Status.Result := Validate_Payload_Length (H, Len);
         begin
            if not Database.Status.Is_Ok (Len_R) then
               Ada.Streams.Stream_IO.Close (File);
               return Len_R;
            end if;
            if Len = 0 then
               declare
                  Empty : Stream_Element_Array (1 .. 0);
               begin
                  R := Validate_Header (H, Empty, Last, K, L);
               end;
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (File);
                  return R;
               end if;
            else
               declare
                  Payload : Stream_Element_Array (0 .. Stream_Element_Offset (Len - 1));
                  Payload_Last : Stream_Element_Offset;
               begin
                  Read (File, Payload, Payload_Last);
                  exit when Payload_Last /= Payload'Last;
                  R := Validate_Header (H, Payload, Last, K, L);
                  if not Database.Status.Is_Ok (R) then
                     Ada.Streams.Stream_IO.Close (File);
                     return R;
                  end if;
                  if K = Page_Frame
                    and then Is_Committed (Committed, Get_U32 (H, 17))
                  then
                     R := Apply_Page_Image (F, Payload, L, False);
                     if not Database.Status.Is_Ok (R) then
                        Ada.Streams.Stream_IO.Close (File);
                        return R;
                     end if;
                  elsif K = Full_Text_Redo_Record
                    and then Is_Committed (Committed, Get_U32 (H, 17))
                  then
                     R := Apply_Page_Image (F, Payload, L, True);
                     if not Database.Status.Is_Ok (R) then
                        Ada.Streams.Stream_IO.Close (File);
                        return R;
                     end if;
                  elsif K = Full_Text_Undo_Record
                    and then not Is_Committed (Committed, Get_U32 (H, 17))
                  then
                     R := Apply_Page_Image (F, Payload, L, True);
                     if not Database.Status.Is_Ok (R) then
                        Ada.Streams.Stream_IO.Close (File);
                        return R;
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      return Database.Storage.File_IO.Flush (F);
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception
            when others =>
               null;
         end;
         return Database.Status.Failure
           (Database.Status.Replay_Failure, "WAL replay failed");
   end Replay_Committed;

   function Max_Commit_Version (Database_Path : Wide_Wide_String) return Natural is
      File : Ada.Streams.Stream_IO.File_Type;
      H    : Stream_Element_Array (0 .. Header_Size - 1);
      Last : Database.Log_Sequence.Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      K    : Record_Kind;
      L    : Log_Sequence_Number;
      R    : Database.Status.Result;
      Max  : Natural := 0;
   begin
      if not Exists (Database_Path) then
         return 0;
      end if;

      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)));
      while not End_Of_File (File) loop
         exit when not Read_Header (File, H);
         declare
            Len   : constant Natural := Get_U32 (H, 26);
            Len_R : constant Database.Status.Result := Validate_Payload_Length (H, Len);
         begin
            exit when not Database.Status.Is_Ok (Len_R);
            if Len = 0 then
               declare
                  Empty : Stream_Element_Array (1 .. 0);
               begin
                  R := Validate_Header (H, Empty, Last, K, L);
               end;
               exit when not Database.Status.Is_Ok (R);
            else
               declare
                  Payload      : Stream_Element_Array (0 .. Stream_Element_Offset (Len - 1));
                  Payload_Last : Stream_Element_Offset;
               begin
                  Read (File, Payload, Payload_Last);
                  exit when Payload_Last /= Payload'Last;
                  R := Validate_Header (H, Payload, Last, K, L);
                  exit when not Database.Status.Is_Ok (R);
                  if K = Commit_Record and then Len >= 4 then
                     Max := Natural'Max (Max, Get_U32 (Payload, 0));
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      return Max;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
         exception
            when others => null;
         end;
         return Max;
   end Max_Commit_Version;

end Database.WAL;
