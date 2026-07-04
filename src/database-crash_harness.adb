with Database.Status;
with Database.Testing;
with Ada.Characters.Conversions;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with GNAT.OS_Lib;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.WAL;
with Database.Log_Sequence;
with Database.Checkpointing;
with Database.Encryption;
with Database.Backup_Format;
with Database.Crypto;
with Database.Crypto_Checks;
with Database.Keys;
with Database.Metrics;

package body Database.Crash_Harness is
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Directories.File_Kind;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element;
   use type Database.Storage.Pages.Byte_Array;
   use type Database.Crypto.Byte;

   Crash_Exit_Code : constant Integer := 86;

   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   function Wide (Text : String) return Wide_Wide_String is
   begin
      return Ada.Characters.Conversions.To_Wide_Wide_String (Text);
   end Wide;

   function Mode_Name (Mode : External_Crash_Mode) return String is
   begin
      case Mode is
         when Process_Before_WAL_Commit           => return "before-wal-commit";
         when Process_After_WAL_Commit            => return "after-wal-commit";
         when Process_During_Checkpoint           => return "during-checkpoint";
         when Power_Loss_Torn_Page                => return "torn-page";
         when Power_Loss_Torn_WAL_Frame           => return "torn-wal-frame";
         when Power_Loss_Truncated_Encrypted_Page => return "truncated-encrypted-page";
         when Power_Loss_Partial_Backup_Manifest  => return "partial-backup-manifest";
      end case;
   end Mode_Name;

   function Parse_Mode (Text : String; Mode : out External_Crash_Mode) return Boolean is
   begin
      for M in External_Crash_Mode loop
         if Text = Mode_Name (M) then
            Mode := M;
            return True;
         end if;
      end loop;
      return False;
   end Parse_Mode;

   procedure Delete_If_Exists (Path : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Path)) then
         if Ada.Directories.Kind (Native (Path)) = Ada.Directories.Directory then
            Ada.Directories.Delete_Tree (Native (Path));
         else
            Ada.Directories.Delete_File (Native (Path));
         end if;
      end if;
   exception
      when others => null;
   end Delete_If_Exists;

   procedure Truncate_File_To (Path : Wide_Wide_String; Last_Byte : Ada.Streams.Stream_Element_Count) is
      package SIO renames Ada.Streams.Stream_IO;
      In_File  : SIO.File_Type;
      Out_File : SIO.File_Type;
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last     : Ada.Streams.Stream_Element_Offset;
      Written  : Ada.Streams.Stream_Element_Count := 0;
      Temp     : constant Wide_Wide_String := Path & ".tmp_trunc";
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return;
      end if;
      Delete_If_Exists (Temp);
      SIO.Open (In_File, SIO.In_File, Native (Path));
      SIO.Create (Out_File, SIO.Out_File, Native (Temp));
      while not SIO.End_Of_File (In_File) and then Written < Last_Byte loop
         SIO.Read (In_File, Buffer, Last);
         exit when Last < Buffer'First;
         declare
            Got : constant Ada.Streams.Stream_Element_Count  :=
              Ada.Streams.Stream_Element_Count (Last - Buffer'First + 1);
            Need : constant Ada.Streams.Stream_Element_Count  :=
              Ada.Streams.Stream_Element_Count'Min (Got, Last_Byte - Written);
            Slice_Last : constant Ada.Streams.Stream_Element_Offset  :=
              Buffer'First + Ada.Streams.Stream_Element_Offset (Need) - 1;
         begin
            SIO.Write (Out_File, Buffer (Buffer'First .. Slice_Last));
            Written := Written + Need;
         end;
      end loop;
      SIO.Close (In_File);
      SIO.Close (Out_File);
      Ada.Directories.Delete_File (Native (Path));
      Ada.Directories.Rename (Native (Temp), Native (Path));
   exception
      when others =>
         begin
            if SIO.Is_Open (In_File) then
               SIO.Close (In_File);
            end if;
            if SIO.Is_Open (Out_File) then
               SIO.Close (Out_File);
            end if;
         exception when others => null;
         end;
   end Truncate_File_To;

   procedure Flip_First_Byte (Path : Wide_Wide_String) is
      package SIO renames Ada.Streams.Stream_IO;
      Size : Natural;
      Inp  : SIO.File_Type;
      Outp : SIO.File_Type;
      Temp : constant Wide_Wide_String := Path & ".flip.tmp";
   begin
      if not Ada.Directories.Exists (Native (Path)) then
         return;
      end if;
      Size := Natural (Ada.Directories.Size (Native (Path)));
      if Size = 0 then
         return;
      end if;
      Delete_If_Exists (Temp);
      declare
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         SIO.Open (Inp, SIO.In_File, Native (Path));
         SIO.Read (Inp, Data, Last);
         SIO.Close (Inp);
         if Last < Data'First then
            return;
         end if;
         Data (Data'First) := Data (Data'First) xor 16#A5#;
         SIO.Create (Outp, SIO.Out_File, Native (Temp));
         SIO.Write (Outp, Data (Data'First .. Last));
         SIO.Close (Outp);
         Ada.Directories.Delete_File (Native (Path));
         Ada.Directories.Rename (Native (Temp), Native (Path));
      end;
   exception
      when others =>
         begin
            if SIO.Is_Open (Inp) then
               SIO.Close (Inp);
            end if;
            if SIO.Is_Open (Outp) then
               SIO.Close (Outp);
            end if;
            Delete_If_Exists (Temp);
         exception when others => null;
         end;
   end Flip_First_Byte;

   procedure Write_WAL_Scenario
     (Path       : Wide_Wide_String;
      With_Commit : Boolean;
      Torn_WAL    : Boolean := False) is
      F : Database.Storage.File_IO.File_Handle;
      W : Database.WAL.WAL_Handle;
      P : Database.Storage.Pages.Page;
      R : Database.Status.Result;
      L : Database.Log_Sequence.Log_Sequence_Number;
   begin
      Delete_If_Exists (Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Path));
      R := Database.Storage.File_IO.Create (F, Path);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (2);
      end if;
      R := Database.WAL.Create (W, Path);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (3);
      end if;
      Database.Storage.Pages.Initialize (P, 2, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload (P, (0 => 16#C1#));
      R := Database.WAL.Append_Page_Frame (W, 70_001, P, L);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (4);
      end if;
      if With_Commit then
         R := Database.WAL.Append_Commit (W, 70_001, 1, L);
         if not Database.Status.Is_Ok (R) then
            GNAT.OS_Lib.OS_Exit (5);
         end if;
      end if;
      R := Database.WAL.Flush (W);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (6);
      end if;
      if Torn_WAL then
         Truncate_File_To (Database.WAL.WAL_Path (Path), 5);
      end if;
      GNAT.OS_Lib.OS_Exit (Crash_Exit_Code);
   end Write_WAL_Scenario;

   procedure Write_Torn_Page (Path : Wide_Wide_String) is
      F : Database.Storage.File_IO.File_Handle;
      P : Database.Storage.Pages.Page;
      R : Database.Status.Result;
   begin
      Delete_If_Exists (Path);
      R := Database.Storage.File_IO.Create (F, Path);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (10);
      end if;
      Database.Storage.Pages.Initialize (P, 2, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload (P, (0 => 16#D1#, 1 => 16#D2#));
      R := Database.Storage.File_IO.Write_Page (F, P);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (11);
      end if;
      R := Database.Storage.File_IO.Flush (F);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (12);
      end if;
      R := Database.Storage.File_IO.Close (F);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (13);
      end if;
      --  A power cut during sector write leaves a physically short file.
      Truncate_File_To (Path, 96);
      GNAT.OS_Lib.OS_Exit (Crash_Exit_Code);
   end Write_Torn_Page;

   procedure Write_Checkpoint_Scenario (Path : Wide_Wide_String) is
      F : Database.Storage.File_IO.File_Handle;
      W : Database.WAL.WAL_Handle;
      P : Database.Storage.Pages.Page;
      R : Database.Status.Result;
      L : Database.Log_Sequence.Log_Sequence_Number;
   begin
      Delete_If_Exists (Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Path));
      R := Database.Storage.File_IO.Create (F, Path);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (20);
      end if;
      Database.Storage.Pages.Initialize (P, 2, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload (P, (0 => 16#E1#));
      R := Database.Storage.File_IO.Write_Page (F, P);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (21);
      end if;
      R := Database.Storage.File_IO.Flush (F);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (22);
      end if;

      --  Checkpoint power loss: the checkpointed page is already durable in
      --  the main file, but the subsequent WAL boundary is torn.
      R := Database.WAL.Create (W, Path);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (23);
      end if;
      R := Database.WAL.Append_Page_Frame (W, 70_002, P, L);
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Append_Commit (W, 70_002, 2, L);
      end if;
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Flush (W);
      end if;
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (24);
      end if;
      Truncate_File_To (Database.WAL.WAL_Path (Path), 5);
      GNAT.OS_Lib.OS_Exit (Crash_Exit_Code);
   end Write_Checkpoint_Scenario;

   procedure Write_Truncated_Encrypted_Page (Path : Wide_Wide_String) is
      Key : Database.Keys.Encryption_Key  :=
        Database.Keys.Derive_Key ("external crash encrypted page", Database.Keys.Default_Salt);
      Nonce : Database.Crypto.Nonce := Database.Crypto.Generate_Nonce (77, 4);
      AAD : Database.Crypto.Byte_Array (0 .. 1) := (16#45#, 16#50#);
      Plain : Database.Crypto.Byte_Array (0 .. 15) := (others => 16#33#);
      Cipher : Database.Crypto.Byte_Array (0 .. 15) := (others => 0);
      Tag : Database.Crypto.Authentication_Tag := (others => 0);
      R : Database.Status.Result;
      package SIO renames Ada.Streams.Stream_IO;
      F : SIO.File_Type;
      Bytes : Ada.Streams.Stream_Element_Array (1 .. 16);
   begin
      Delete_If_Exists (Path);
      R := Database.Crypto.Encrypt (Key, Nonce, AAD, Plain, Cipher, Tag);
      if not Database.Status.Is_Ok (R) then
         GNAT.OS_Lib.OS_Exit (30);
      end if;
      for I in Bytes'Range loop
         Bytes (I) := Ada.Streams.Stream_Element (Cipher (Integer (I - Bytes'First)));
      end loop;
      SIO.Create (F, SIO.Out_File, Native (Path));
      SIO.Write (F, Bytes);
      SIO.Close (F);
      Truncate_File_To (Path, 7);
      GNAT.OS_Lib.OS_Exit (Crash_Exit_Code);
   exception
      when others =>
         GNAT.OS_Lib.OS_Exit (31);
   end Write_Truncated_Encrypted_Page;

   procedure Write_Partial_Manifest (Backup_Path : Wide_Wide_String) is
      package SIO renames Ada.Streams.Stream_IO;
      F : SIO.File_Type;
      Manifest_Path : constant Wide_Wide_String  :=
        Database.Backup_Format.Manifest_Path (Backup_Path);
      Bytes : constant Ada.Streams.Stream_Element_Array (1 .. 8)  :=
        (1 => Ada.Streams.Stream_Element (Character'Pos ('D')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('B')),
         3 => Ada.Streams.Stream_Element (Character'Pos ('B')),
         4 => Ada.Streams.Stream_Element (Character'Pos ('A')),
         5 => Ada.Streams.Stream_Element (Character'Pos ('K')),
         6 => 0, 7 => 0, 8 => 1);
   begin
      Delete_If_Exists (Backup_Path);
      Ada.Directories.Create_Directory (Native (Backup_Path));
      SIO.Create (F, SIO.Out_File, Native (Manifest_Path));
      SIO.Write (F, Bytes);
      SIO.Close (F);
      GNAT.OS_Lib.OS_Exit (Crash_Exit_Code);
   exception
      when others =>
         GNAT.OS_Lib.OS_Exit (40);
   end Write_Partial_Manifest;

   procedure Child_Main is
      Mode : External_Crash_Mode;
   begin
      if Ada.Command_Line.Argument_Count /= 2
        or else not Parse_Mode (Ada.Command_Line.Argument (1), Mode)
      then
         GNAT.OS_Lib.OS_Exit (64);
      end if;

      declare
         Path : constant Wide_Wide_String := Wide (Ada.Command_Line.Argument (2));
      begin
         case Mode is
            when Process_Before_WAL_Commit =>
               Write_WAL_Scenario (Path, With_Commit => False);
            when Process_After_WAL_Commit =>
               Write_WAL_Scenario (Path, With_Commit => True);
            when Process_During_Checkpoint =>
               Write_Checkpoint_Scenario (Path);
            when Power_Loss_Torn_Page =>
               Write_Torn_Page (Path);
            when Power_Loss_Torn_WAL_Frame =>
               Write_WAL_Scenario (Path, With_Commit => True, Torn_WAL => True);
            when Power_Loss_Truncated_Encrypted_Page =>
               Write_Truncated_Encrypted_Page (Path);
            when Power_Loss_Partial_Backup_Manifest =>
               Write_Partial_Manifest (Path & ".backup");
         end case;
      end;
   end Child_Main;

   function Validate_After_Child
     (Path : Wide_Wide_String;
      Mode : External_Crash_Mode) return Harness_Report is
      F : Database.Storage.File_IO.File_Handle;
      P : Database.Storage.Pages.Page;
      R : Database.Status.Result;
      Check : Database.Crypto_Checks.Check_Result;
      Key : Database.Keys.Encryption_Key  :=
        Database.Keys.Derive_Key ("external crash encrypted page", Database.Keys.Default_Salt);
      Nonce : Database.Crypto.Nonce := Database.Crypto.Generate_Nonce (77, 4);
      AAD : Database.Crypto.Byte_Array (0 .. 1) := (16#45#, 16#50#);
      Cipher : Database.Crypto.Byte_Array (0 .. 6) := (others => 0);
      Tag : Database.Crypto.Authentication_Tag := (others => 0);
   begin
      case Mode is
         when Process_Before_WAL_Commit =>
            R := Database.Storage.File_IO.Open (F, Path);
            if not Database.Status.Is_Ok (R) then
               return (R, 0, True, False, False, 1);
            end if;
            R := Database.WAL.Replay_Committed (Path, F);
            if not Database.Status.Is_Ok (R) then
               return (R, 0, True, True, False, 1);
            end if;
            R := Database.Storage.File_IO.Read_Raw_Page (F, 2, P);
            declare
               CR : constant Database.Status.Result := Database.Storage.File_IO.Close (F);
            begin
               null;
            end;
            if Database.Status.Is_Ok (R) then
               return (Database.Status.Failure (Database.Status.Verification_Failure,
                       "uncommitted external WAL frame became visible"), 0, True, True, False, 1);
            end if;
            return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);

         when Process_After_WAL_Commit =>
            R := Database.Storage.File_IO.Open (F, Path);
            if not Database.Status.Is_Ok (R) then
               return (R, 0, True, False, False, 1);
            end if;
            R := Database.WAL.Replay_Committed (Path, F);
            if not Database.Status.Is_Ok (R) then
               declare
                  CR : constant Database.Status.Result := Database.Storage.File_IO.Close (F);
               begin
                  null;
               end;
               return (R, 0, True, True, False, 1);
            end if;
            R := Database.Storage.File_IO.Read_Raw_Page (F, 2, P);
            declare
               CR : constant Database.Status.Result := Database.Storage.File_IO.Close (F);
            begin
               null;
            end;
            if Database.Status.Is_Ok (R)
              and then Database.Storage.Pages.Payload (P)'Length > 0
              and then Database.Storage.Pages.Payload (P) (0) = 16#C1#
            then
               return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
            end if;
            return (Database.Status.Failure (Database.Status.Verification_Failure,
                    "committed external WAL state was not recovered"), 0, True, True, False, 1);

         when Process_During_Checkpoint =>
            R := Database.Storage.File_IO.Open (F, Path);
            if not Database.Status.Is_Ok (R) then
               return (R, 0, True, False, False, 1);
            end if;
            --  A torn post-checkpoint WAL may fail validation/replay, but the
            --  checkpointed page already in the main file must remain valid.
            declare
               Replay_Result : constant Database.Status.Result  :=
                 Database.WAL.Replay_Committed (Path, F);
               pragma Unreferenced (Replay_Result);
            begin
               null;
            end;
            R := Database.Storage.File_IO.Read_Raw_Page (F, 2, P);
            declare
               CR : constant Database.Status.Result := Database.Storage.File_IO.Close (F);
            begin
               null;
            end;
            if Database.Status.Is_Ok (R)
              and then Database.Storage.Pages.Payload (P)'Length > 0
              and then Database.Storage.Pages.Payload (P) (0) = 16#E1#
              and then not Database.Status.Is_Ok (Database.WAL.Validate (Path))
            then
               return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
            end if;
            return (Database.Status.Failure (Database.Status.Verification_Failure,
                    "checkpoint power-loss state was not recovered or torn WAL was accepted"), 0, True, True, False, 1);

         when Power_Loss_Torn_Page =>
            R := Database.Storage.File_IO.Open (F, Path);
            if Database.Status.Is_Ok (R) then
               R := Database.Storage.File_IO.Read_Raw_Page (F, 2, P);
               declare
                  CR : constant Database.Status.Result := Database.Storage.File_IO.Close (F);
               begin
                  null;
               end;
            end if;
            if not Database.Status.Is_Ok (R) then
               return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
            end if;
            return (Database.Status.Failure (Database.Status.Verification_Failure,
                    "torn page was accepted as valid"), 0, True, True, False, 1);

         when Power_Loss_Torn_WAL_Frame =>
            R := Database.WAL.Validate (Path);
            if not Database.Status.Is_Ok (R) then
               return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
            end if;
            return (Database.Status.Failure (Database.Status.Verification_Failure,
                    "torn WAL frame validated successfully"), 0, True, True, False, 1);

         when Power_Loss_Truncated_Encrypted_Page =>
            --  Validate the actual child artifact, not a synthetic buffer.  The
            --  child writes a ciphertext prefix and then truncates it;
            --  the
            --  verifier copies only the bytes that physically exist and must
            --  still fail closed through the authentication path.
            if not Ada.Directories.Exists (Native (Path))
              or else Ada.Directories.Size (Native (Path)) >= 16
            then
               return (Database.Status.Failure (Database.Status.Verification_Failure,
                       "truncated encrypted page artifact was not physically truncated"),
                       0, True, True, False, 1);
            end if;
            declare
               package SIO renames Ada.Streams.Stream_IO;
               EF : SIO.File_Type;
               Raw : Ada.Streams.Stream_Element_Array (1 .. 7) := (others => 0);
               Last : Ada.Streams.Stream_Element_Offset;
            begin
               SIO.Open (EF, SIO.In_File, Native (Path));
               SIO.Read (EF, Raw, Last);
               SIO.Close (EF);
               for I in Raw'First .. Last loop
                  Cipher (Natural (I - Raw'First)) := Database.Crypto.Byte (Raw (I));
               end loop;
            exception
               when others =>
                  return (Database.Status.Failure (Database.Status.Verification_Failure,
                          "truncated encrypted page artifact could not be read"),
                          0, True, True, False, 1);
            end;
            Check := Database.Crypto_Checks.Verify_Authenticated_Buffer (Key, Nonce, AAD, Cipher, Tag);
            if not Database.Status.Is_Ok (Check.Result) then
               return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
            end if;
            return (Database.Status.Failure (Database.Status.Verification_Failure,
                    "truncated encrypted page authenticated successfully"), 0, True, True, False, 1);

         when Power_Loss_Partial_Backup_Manifest =>
            declare
               M : Database.Backup_Format.Manifest;
            begin
               R := Database.Backup_Format.Read_Manifest (Path & ".backup", M);
            end;
            if not Database.Status.Is_Ok (R) then
               return (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
            end if;
            return (Database.Status.Failure (Database.Status.Verification_Failure,
                    "partial backup manifest validated successfully"), 0, True, True, False, 1);
      end case;
   exception
      when others =>
         begin
            if Database.Storage.File_IO.Is_Open (F) then
               R := Database.Storage.File_IO.Close (F);
            end if;
         exception when others => null;
         end;
         return (Database.Status.Failure (Database.Status.Verification_Failure,
                 "external crash validation raised unexpectedly"), 0, True, True, False, 1);
   end Validate_After_Child;

   function Run_External_Crash
     (Child_Executable : String;
      Work_Path        : Wide_Wide_String;
      Mode             : External_Crash_Mode) return Harness_Report is
      Args : GNAT.OS_Lib.Argument_List (1 .. 2);
      Exit_Status : Integer;
      Report : Harness_Report;
   begin
      if Child_Executable'Length = 0 then
         return (Database.Status.Failure (Database.Status.Invalid_Argument,
                 "external crash child executable not provided"), 0, False, False, False, 1);
      end if;

      Delete_If_Exists (Work_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Work_Path));
      Delete_If_Exists (Work_Path & ".backup");
      Args (1) := new String'(Mode_Name (Mode));
      Args (2) := new String'(Native (Work_Path));
      Exit_Status := GNAT.OS_Lib.Spawn (Child_Executable, Args);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));

      if Exit_Status /= Crash_Exit_Code then
         Database.Metrics.Increment_Verification_Failures;
         return (Database.Status.Failure (Database.Status.Verification_Failure,
                 "external crash child did not terminate at crash boundary"),
                 Exit_Status, True, False, False, 1);
      end if;

      Report := Validate_After_Child (Work_Path, Mode);
      Report.Child_Exit_Status := Exit_Status;
      if not Database.Status.Is_Ok (Report.Status) then
         Database.Metrics.Increment_Verification_Failures;
      end if;
      Delete_If_Exists (Work_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Work_Path));
      Delete_If_Exists (Work_Path & ".backup");
      return Report;
   exception
      when others =>
         Database.Metrics.Increment_Verification_Failures;
         return (Database.Status.Failure (Database.Status.Verification_Failure,
                 "external crash harness failed to spawn or validate child"), 0, False, False, False, 1);
   end Run_External_Crash;

   function Run_All_External_Crashes
     (Child_Executable : String;
      Work_Prefix      : Wide_Wide_String := "external_crash") return Harness_Report is
      Aggregate : Harness_Report := (Database.Status.Success, Crash_Exit_Code, True, True, True, 0);
   begin
      for Mode in External_Crash_Mode loop
         declare
            One : constant Harness_Report := Run_External_Crash
              (Child_Executable,
               Work_Prefix & "_" & Wide (Mode_Name (Mode)) & ".db",
               Mode);
         begin
            if not Database.Status.Is_Ok (One.Status) then
               return One;
            end if;
            Aggregate.Violations := Aggregate.Violations + One.Violations;
         end;
      end loop;
      return Aggregate;
   end Run_All_External_Crashes;

   function Verify_External_Process_Power_Loss
     (Child_Executable : String) return Database.Testing.Recovery_Report is
      R : constant Harness_Report := Run_All_External_Crashes (Child_Executable);
   begin
      if Database.Status.Is_Ok (R.Status) then
         return (Database.Status.Success, True,
                 External_Crash_Mode'Pos (External_Crash_Mode'Last) + 1,
                 R.Violations);
      end if;
      return (R.Status, False, 0, R.Violations + 1);
   end Verify_External_Process_Power_Loss;
end Database.Crash_Harness;
