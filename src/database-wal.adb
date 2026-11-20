with Ada.Characters.Conversions;
with Ada.Calendar;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Streams;
with Database.Metrics;
with Database.Fault_Hooks;
with Database.MVCC;
with Database.Tracing;
with Database.WAL.Payload_Rules;
with Interfaces.C;

package body Database.WAL is
   use type Database.Log_Sequence.Log_Sequence_Number;
   use Ada.Streams;
   use Ada.Streams.Stream_IO;
   use Database.Log_Sequence;
   use Database.Storage.Pages;
   use type Interfaces.C.int;

   Header_Size : constant := 40;
   Magic : constant Stream_Element_Array (0 .. 7)  :=
     [Stream_Element (Character'Pos ('D')), Stream_Element (Character'Pos ('B')),
      Stream_Element (Character'Pos ('W')), Stream_Element (Character'Pos ('A')),
      Stream_Element (Character'Pos ('L')), Stream_Element (Character'Pos ('1')),
      Stream_Element (Character'Pos ('7')), 0];
   function C_Open_File
     (Path  : Interfaces.C.char_array;
      Read_Only : Interfaces.C.int;
      Create    : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "database_posix_open_file";

   function C_Open_Directory (Path : Interfaces.C.char_array) return Interfaces.C.int
   with Import, Convention => C, External_Name => "database_posix_open_directory";

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
      FD := C_Open_File (Interfaces.C.To_C (Native (Path)), Read_Only => 0, Create => 0);
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
      FD := C_Open_Directory (Interfaces.C.To_C (Dir));
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

   --  What this process knows about a WAL it appended to and closed cleanly: the file's size and modification time
   --  then, and the last sequence number in it. Commit opens the WAL once per page frame; while the file is unchanged,
   --  Open reuses this instead of validating and scanning the whole file, which made each commit cost time
   --  proportional to the WAL.
   type Trusted_State is record
      Size     : Ada.Directories.File_Size;
      Modified : Ada.Calendar.Time;
      Last     : Log_Sequence_Number;
   end record;

   package Trust_Maps is new Ada.Containers.Indefinite_Ordered_Maps (Wide_Wide_String, Trusted_State);

   protected Trust is
      procedure Remember (Path : Wide_Wide_String; State : Trusted_State);
      procedure Forget (Path : Wide_Wide_String);
      procedure Find (Path : Wide_Wide_String; Found : out Boolean; State : out Trusted_State);
   private
      Map : Trust_Maps.Map;
   end Trust;

   protected body Trust is
      procedure Remember (Path : Wide_Wide_String; State : Trusted_State) is
      begin
         Map.Include (Path, State);
      end Remember;

      procedure Forget (Path : Wide_Wide_String) is
      begin
         Map.Exclude (Path);
      end Forget;

      procedure Find (Path : Wide_Wide_String; Found : out Boolean; State : out Trusted_State) is
      begin
         Found := Map.Contains (Path);
         if Found then
            State := Map.Element (Path);
         end if;
      end Find;
   end Trust;

   procedure Forget_Trusted (Database_Path : Wide_Wide_String) is
   begin
      Trust.Forget (Database_Path);
   end Forget_Trusted;

   --  Whether the WAL of Database_Path is unchanged since this process last closed it, and what it held then.
   function Unchanged (Database_Path : Wide_Wide_String; State : out Trusted_State) return Boolean is
      use type Ada.Directories.File_Size;
      Found : Boolean;
      Path  : constant String := Native (WAL_Path (Database_Path));
   begin
      Trust.Find (Database_Path, Found, State);
      return Found and then Ada.Directories.Exists (Path) and then Ada.Directories.Size (Path) = State.Size
        and then Ada.Calendar."=" (Ada.Directories.Modification_Time (Path), State.Modified);
   exception
      when others =>
         return False;
   end Unchanged;

   function Delete (Database_Path : Wide_Wide_String) return Database.Status.Result is
      P : constant String := Native (WAL_Path (Database_Path));
   begin
      Trust.Forget (Database_Path);
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
         when Page_Undo_Record       => return 6;
         when Begin_Record           => return 7;
         when Abort_Record           => return 8;
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
         when 6 => K := Page_Undo_Record;
         return True;
         when 7 => K := Begin_Record;
         return True;
         when 8 => K := Abort_Record;
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

   --  The sum of every header byte except the four checksum bytes 36 .. 39, and of every payload byte. A modular
   --  accumulator needs no per-byte overflow check; the result stays far below 2**32 for a frame.
   function Checksum (H : Stream_Element_Array; Payload : Stream_Element_Array) return Natural is
      use type Interfaces.Unsigned_32;
      S : Interfaces.Unsigned_32 := 0;
   begin
      for Value of H loop
         S := S + Interfaces.Unsigned_32 (Value);
      end loop;
      for I in Stream_Element_Offset'(36) .. 39 loop
         if I in H'Range then
            S := S - Interfaces.Unsigned_32 (H (I));
         end if;
      end loop;
      for Value of Payload loop
         S := S + Interfaces.Unsigned_32 (Value);
      end loop;
      return Natural (S);
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
      Ada.Streams.Stream_IO.Create (W.File, Out_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
      Ada.Streams.Stream_IO.Close (W.File);
      Ada.Streams.Stream_IO.Open (W.File, Out_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
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
         State : Trusted_State;
      begin
         if Unchanged (Database_Path, State) then
            Ada.Streams.Stream_IO.Open
              (W.File, In_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
            W.Opened := True;
            W.DB_Path := To_Unbounded_Wide_Wide_String (Database_Path);
            Database.Log_Sequence.Reset (W.Generator, State.Last);
            return Database.Status.Success;
         end if;
      end;
      Trust.Forget (Database_Path);
      declare
         Normalize_Result : constant Database.Status.Result  :=
           Normalize_For_Append (Database_Path);
      begin
         if not Database.Status.Is_Ok (Normalize_Result) then
            return Normalize_Result;
         end if;
      end;
      Ada.Streams.Stream_IO.Open (W.File, In_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
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
      Path : constant Wide_Wide_String := To_Wide_Wide_String (W.DB_Path);
   begin
      if W.Opened then
         Ada.Streams.Stream_IO.Close (W.File);
         W.Opened := False;
         --  Everything appended through W is complete and in the file, so the next Open may reuse what W knew.
         Trust.Remember
           (Path, (Size     => Ada.Directories.Size (Native (WAL_Path (Path))),
                   Modified => Ada.Directories.Modification_Time (Native (WAL_Path (Path))),
                   Last     => Database.Log_Sequence.Current (W.Generator)));
      end if;
      return Database.Status.Success;
   exception
      when others =>
         Trust.Forget (Path);
         return Database.Status.Failure (Database.Status.IOError, "could not close WAL file");
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
      H : Stream_Element_Array (0 .. Header_Size - 1) := [others => 0];
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

   function Append_Page_Undo
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page           : Database.Storage.Pages.Page;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
   begin
      return Append_Record
        (W, Page_Undo_Record, Transaction_Id, Natural (Get_Id (Page)), Page_Kind'Pos (Get_Kind (Page)),
         To_Stream (Page), LSN);
   end Append_Page_Undo;

   function Append_Begin
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Page_Count     : Natural;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      Payload : Stream_Element_Array (0 .. 3) := [others => 0];
   begin
      Put_U32 (Payload, 0, Page_Count);
      return Append_Record (W, Begin_Record, Transaction_Id, 0, 0, Payload, LSN);
   end Append_Begin;

   function Append_Abort
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      Empty : Stream_Element_Array (1 .. 0);
   begin
      return Append_Record (W, Abort_Record, Transaction_Id, 0, 0, Empty, LSN);
   end Append_Abort;

   function Append_Commit
     (W              : in out WAL_Handle;
      Transaction_Id : Natural;
      Commit_Version : Natural;
      LSN            : out Log_Sequence_Number) return Database.Status.Result is
      Payload : Stream_Element_Array (0 .. 3) := [others => 0];
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

   package Id_Sets is new Ada.Containers.Ordered_Sets (Natural);
   package Count_Maps is new Ada.Containers.Ordered_Maps (Natural, Natural);

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

   --  Write back the image a page had before an unfinished transaction changed it. Unlike a redo image it is written
   --  whatever the page holds now, and it takes the sequence number of its record, so that the images of later
   --  committed transactions are written over it again.
   function Restore_Page_Image
     (F       : in out Database.Storage.File_IO.File_Handle;
      Payload : Stream_Element_Array;
      LSN     : Log_Sequence_Number) return Database.Status.Result is
      P : Database.Storage.Pages.Page := From_Stream (Payload);
   begin
      Set_Last_LSN (P, LSN);
      return Database.Storage.File_IO.Write_Page (F, P);
   end Restore_Page_Image;

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
            when Page_Undo_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL page undo payload length");
            when Begin_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL begin payload length");
            when Abort_Record =>
               return Database.Status.Failure
                 (Database.Status.WAL_Corruption,
                  "invalid WAL abort payload length");
         end case;
      end if;

      return Database.Status.Success;
   end Validate_Payload_Length;

   --  Read the records of the WAL of Database_Path in order and pass each complete one to Visit. A short trailing
   --  record, left by a power loss during an append, ends the scan; a complete record that fails validation ends it
   --  with that failure, as does Visit returning one.
   generic
      with function Visit
        (H       : Stream_Element_Array;
         K       : Record_Kind;
         LSN     : Log_Sequence_Number;
         Payload : Stream_Element_Array) return Database.Status.Result;
   function Scan_Records (Database_Path : Wide_Wide_String) return Database.Status.Result;

   function Scan_Records (Database_Path : Wide_Wide_String) return Database.Status.Result is
      File : File_Type;
      H    : Stream_Element_Array (0 .. Header_Size - 1);
      Last : Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      K    : Record_Kind;
      L    : Log_Sequence_Number;
      R    : Database.Status.Result := Database.Status.Success;
   begin
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
      while Database.Status.Is_Ok (R) and then not End_Of_File (File) loop
         exit when not Read_Header (File, H);
         declare
            Len : constant Natural := Get_U32 (H, 26);
         begin
            --  The length is checked before the payload is allocated, so a corrupt header cannot ask for any amount.
            R := Validate_Payload_Length (H, Len);
            exit when not Database.Status.Is_Ok (R);
            declare
               Payload      : Stream_Element_Array (0 .. Stream_Element_Offset (Len) - 1);
               Payload_Last : Stream_Element_Offset := Payload'Last;
            begin
               if Len > 0 then
                  Read (File, Payload, Payload_Last);
               end if;
               exit when Payload_Last /= Payload'Last;
               R := Validate_Header (H, Payload, Last, K, L);
               if Database.Status.Is_Ok (R) then
                  R := Visit (H, K, L, Payload);
               end if;
            end;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      return R;
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
         return Database.Status.Failure (Database.Status.Replay_Failure, "WAL replay failed");
   end Scan_Records;

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
      Trust.Forget (Database_Path);
      if Ada.Directories.Exists (Native (Tmp_Path)) then
         Ada.Directories.Delete_File (Native (Tmp_Path));
      end if;

      if New_Size = 0 then
         Ada.Streams.Stream_IO.Create (Outp, Out_File, Native (Tmp_Path), Form => "shared=no");
         Ada.Streams.Stream_IO.Flush (Outp);
         Ada.Streams.Stream_IO.Close (Outp);
      else
         Ada.Streams.Stream_IO.Open (Inp, In_File, Native (Source_Path), Form => "shared=no");
         Ada.Streams.Stream_IO.Create (Outp, Out_File, Native (Tmp_Path), Form => "shared=no");
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
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
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
      Ada.Streams.Stream_IO.Open (File, In_File, Native (WAL_Path (Database_Path)), Form => "shared=no");
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
      Committed, Finished : Id_Sets.Set;
      --  The length of the database file before each transaction's first write.
      Begun               : Count_Maps.Map;
      --  One past the highest page a committed transaction writes.
      Committed_End       : Natural := 0;
      Keep                : Natural := Natural'Last;
      R                   : Database.Status.Result;

      function Note
        (H       : Stream_Element_Array;
         K       : Record_Kind;
         LSN     : Log_Sequence_Number;
         Payload : Stream_Element_Array) return Database.Status.Result is
         pragma Unreferenced (LSN);
         Tx : constant Natural := Get_U32 (H, 17);
      begin
         case K is
            when Commit_Record =>
               Committed.Include (Tx);
               Finished.Include (Tx);
            when Abort_Record =>
               Finished.Include (Tx);
            when Begin_Record =>
               Begun.Include (Tx, Get_U32 (Payload, 0));
            when others =>
               null;
         end case;
         return Database.Status.Success;
      end Note;

      function Apply
        (H       : Stream_Element_Array;
         K       : Record_Kind;
         LSN     : Log_Sequence_Number;
         Payload : Stream_Element_Array) return Database.Status.Result is
         Tx : constant Natural := Get_U32 (H, 17);
      begin
         case K is
            when Page_Frame =>
               if Committed.Contains (Tx) then
                  Committed_End := Natural'Max (Committed_End, Get_U32 (H, 21) + 1);
                  return Apply_Page_Image (F, Payload, LSN, False);
               end if;
            when Page_Undo_Record =>
               if not Finished.Contains (Tx) then
                  return Restore_Page_Image (F, Payload, LSN);
               end if;
            when Full_Text_Redo_Record =>
               if Committed.Contains (Tx) then
                  return Apply_Page_Image (F, Payload, LSN, True);
               end if;
            when Full_Text_Undo_Record =>
               if not Committed.Contains (Tx) then
                  return Apply_Page_Image (F, Payload, LSN, True);
               end if;
            when others =>
               null;
         end case;
         return Database.Status.Success;
      end Apply;

      function Scan_Notes is new Scan_Records (Note);
      function Scan_Applies is new Scan_Records (Apply);
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
      R := Scan_Notes (Database_Path);
      if Database.Status.Is_Ok (R) then
         R := Scan_Applies (Database_Path);
      end if;
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      for C in Begun.Iterate loop
         if not Finished.Contains (Count_Maps.Key (C)) then
            Keep := Natural'Min (Keep, Count_Maps.Element (C));
         end if;
      end loop;
      if Keep /= Natural'Last then
         Keep := Natural'Max (Keep, Committed_End);
         if Database.Storage.File_IO.Page_Count (F) > Keep then
            R := Database.Storage.File_IO.Truncate_To_Page_Count (F, Keep);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end if;
         R := Database.Storage.File_IO.Flush (F);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         declare
            W : WAL_Handle;
            L : Log_Sequence_Number;
         begin
            R := Open (W, Database_Path);
            for C in Begun.Iterate loop
               exit when not Database.Status.Is_Ok (R);
               if not Finished.Contains (Count_Maps.Key (C)) then
                  R := Append_Abort (W, Count_Maps.Key (C), L);
               end if;
            end loop;
            if Database.Status.Is_Ok (R) then
               R := Flush (W);
            end if;
            declare
               CR : constant Database.Status.Result := Close (W);
            begin
               if Database.Status.Is_Ok (R) then
                  R := CR;
               end if;
            end;
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end;
      end if;
      return Database.Storage.File_IO.Flush (F);
   end Replay_Committed;

   function Max_Commit_Version (Database_Path : Wide_Wide_String) return Natural is
      Max : Natural := 0;

      function Note
        (H       : Stream_Element_Array;
         K       : Record_Kind;
         LSN     : Log_Sequence_Number;
         Payload : Stream_Element_Array) return Database.Status.Result is
         pragma Unreferenced (H, LSN);
      begin
         if K = Commit_Record then
            Max := Natural'Max (Max, Get_U32 (Payload, 0));
         end if;
         return Database.Status.Success;
      end Note;

      function Scan is new Scan_Records (Note);
   begin
      if Exists (Database_Path) then
         declare
            R : constant Database.Status.Result := Scan (Database_Path);
            pragma Unreferenced (R);
         begin
            null;
         end;
      end if;
      return Max;
   end Max_Commit_Version;

   function Max_Transaction_Id (Database_Path : Wide_Wide_String) return Natural is
      Max : Natural := 0;

      function Note
        (H       : Stream_Element_Array;
         K       : Record_Kind;
         LSN     : Log_Sequence_Number;
         Payload : Stream_Element_Array) return Database.Status.Result is
         pragma Unreferenced (K, LSN, Payload);
      begin
         Max := Natural'Max (Max, Get_U32 (H, 17));
         return Database.Status.Success;
      end Note;

      function Scan is new Scan_Records (Note);
   begin
      if Exists (Database_Path) then
         declare
            R : constant Database.Status.Result := Scan (Database_Path);
            pragma Unreferenced (R);
         begin
            null;
         end;
      end if;
      return Max;
   end Max_Transaction_Id;

   procedure Restore_Committed_Lifecycles (Database_Path : Wide_Wide_String) is
      function Note
        (H       : Stream_Element_Array;
         K       : Record_Kind;
         LSN     : Log_Sequence_Number;
         Payload : Stream_Element_Array) return Database.Status.Result is
         pragma Unreferenced (LSN);
      begin
         if K = Commit_Record then
            --  Header offset 17 holds the transaction id; payload
            --  offset 0 holds the commit version (see Append_Commit).
            Database.MVCC.Mark_Committed (Get_U32 (H, 17), Get_U32 (Payload, 0));
         end if;
         return Database.Status.Success;
      end Note;

      function Scan is new Scan_Records (Note);
   begin
      if Exists (Database_Path) then
         declare
            R : constant Database.Status.Result := Scan (Database_Path);
            pragma Unreferenced (R);
         begin
            null;
         end;
      end if;
   end Restore_Committed_Lifecycles;

end Database.WAL;
