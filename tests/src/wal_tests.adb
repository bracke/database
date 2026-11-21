with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Streams.Stream_IO;
with Database;
with Database.Checkpointing;
with Database.Fault_Hooks;
with Database.Full_Text.Postings;
with Database.Full_Text.Storage;
with Database.Log_Sequence;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Transactions;
with Database.WAL;
with Ada.Strings.Wide_Wide_Unbounded;

package body WAL_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;
   use type Database.Log_Sequence.Log_Sequence_Number;
   use type Database.Storage.Pages.Page_Id;
   use type Database.Storage.Pages.Page_Kind;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("write ahead log");
   end Name;

   procedure Remove_File (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_File;

   procedure Append_Validate_Reopen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant Wide_Wide_String := "wal_basic.database";
      F      : Database.Storage.File_IO.File_Handle;
      W      : Database.WAL.WAL_Handle;
      P      : Database.Storage.Pages.Page;
      L1, L2 : Database.Log_Sequence.Log_Sequence_Number;
      R      : Database.Status.Result;
   begin
      Remove_File ("wal_basic.database");
      Remove_File ("wal_basic.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.WAL.Append_Page_Frame (W, 1, P, L1);
      Assert (Database.Status.Is_Ok (R), "append page failed");
      R := Database.WAL.Append_Commit (W, 1, 1, L2);
      Assert (Database.Status.Is_Ok (R), "append commit failed");
      Assert (L2 > L1, "commit LSN did not advance");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "flush failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "wal close failed");
      Assert (Database.WAL.Exists (Path), "wal file missing");
      R := Database.WAL.Validate (Path);
      Assert (Database.Status.Is_Ok (R), "wal validate failed");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("wal_basic.database");
      Remove_File ("wal_basic.database.wal");
   end Append_Validate_Reopen;

   procedure Replay_Ignores_Uncommitted_Frames
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "wal_uncommitted.database";
      F    : Database.Storage.File_IO.File_Handle;
      W    : Database.WAL.WAL_Handle;
      P, Q : Database.Storage.Pages.Page;
      L    : Database.Log_Sequence.Log_Sequence_Number;
      R    : Database.Status.Result;
   begin
      Remove_File ("wal_uncommitted.database");
      Remove_File ("wal_uncommitted.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      R := Database.WAL.Append_Page_Frame (W, 42, P, L);
      Assert (Database.Status.Is_Ok (R), "append failed");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "flush failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "close failed");
      R := Database.WAL.Replay_Committed (Path, F);
      Assert (Database.Status.Is_Ok (R), "replay failed");
      R := Database.Storage.File_IO.Read_Raw_Page (F, 2, Q);
      Assert (R.Code /= Database.Status.Ok, "uncommitted frame was replayed");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("wal_uncommitted.database");
      Remove_File ("wal_uncommitted.database.wal");
   end Replay_Ignores_Uncommitted_Frames;

   procedure Replay_Applies_Committed_Frames
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "wal_committed.database";
      F    : Database.Storage.File_IO.File_Handle;
      W    : Database.WAL.WAL_Handle;
      P, Q : Database.Storage.Pages.Page;
      L    : Database.Log_Sequence.Log_Sequence_Number;
      R    : Database.Status.Result;
   begin
      Remove_File ("wal_committed.database");
      Remove_File ("wal_committed.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      R := Database.WAL.Append_Page_Frame (W, 7, P, L);
      Assert (Database.Status.Is_Ok (R), "append page failed");
      R := Database.WAL.Append_Commit (W, 7, 1, L);
      Assert (Database.Status.Is_Ok (R), "append commit failed");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "flush failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "close failed");
      R := Database.WAL.Replay_Committed (Path, F);
      Assert (Database.Status.Is_Ok (R), "replay failed");
      R :=
        Database.Storage.File_IO.Read_Page
          (F, 2, Database.Storage.Pages.Table_Heap_Page, Q);
      Assert (Database.Status.Is_Ok (R), "committed page not replayed");
      Assert (Database.Storage.Pages.Get_Id (Q) = 2, "wrong replayed page id");
      Assert
        (Database.Storage.Pages.Last_LSN (Q) > 0,
         "page LSN not set by replay");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("wal_committed.database");
      Remove_File ("wal_committed.database.wal");
   end Replay_Applies_Committed_Frames;

   procedure Checkpoint_Removes_Safe_WAL
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "wal_checkpoint.database";
      DB   : Database.Handle;
      R    : Database.Status.Result;
   begin
      Remove_File ("wal_checkpoint.database");
      Remove_File ("wal_checkpoint.database.wal");
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "database create failed");
      R := Database.Checkpointing.Checkpoint (DB);
      Assert (Database.Status.Is_Ok (R), "empty checkpoint failed");
      Assert
        (not Database.WAL.Exists (Path), "checkpoint left empty WAL behind");

      --  A checkpoint holds the write lock: it is refused beside a writer, and
      --  gives the lock back however it ends.
      declare
         Tx      : Database.Transactions.Transaction;
         Granted : Boolean;
      begin
         Database.Transactions.Try_Begin_Write (DB, Tx, Granted);
         Assert (Granted, "a checkpoint gives the write lock back");
         R := Database.Checkpointing.Checkpoint (DB);
         Assert (R.Code = Database.Status.Checkpoint_Failure, "a checkpoint beside a writer is refused");
         R := Database.Transactions.Commit (Tx);
         Assert (Database.Status.Is_Ok (R), "commit failed");

         Database.Fault_Hooks.Enable_Fault (Database.Fault_Hooks.Fail_Checkpoint);
         R := Database.Checkpointing.Checkpoint (DB);
         Database.Fault_Hooks.Disable_Fault (Database.Fault_Hooks.Fail_Checkpoint);
         Assert (not Database.Status.Is_Ok (R), "the injected checkpoint failure is reported");
         Database.Transactions.Try_Begin_Write (DB, Tx, Granted);
         Assert (Granted, "a failed checkpoint gives the write lock back");
         R := Database.Transactions.Commit (Tx);
      end;
      Database.Close (DB);
      Remove_File ("wal_checkpoint.database");
      Remove_File ("wal_checkpoint.database.wal");
   end Checkpoint_Removes_Safe_WAL;

   function One_Posting (Row_Id : Natural) return Database.Full_Text.Postings.Posting_Vectors.Vector is
      P : Database.Full_Text.Postings.Posting;
      V : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      P.Ref.Table_Id := 1;
      P.Ref.Row_Id := Row_Id;
      P.Ref.Row_Key :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          (Natural'Wide_Wide_Image (Row_Id));
      P.Ref.Column_Id := 1;
      P.Frequency := 1;
      Database.Full_Text.Postings.Add_Position (P, 0);
      V.Append (P);
      return V;
   end One_Posting;

   procedure Full_Text_Redo_Replays_Committed_Image
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "wal_ft_redo.database";
      F    : Database.Storage.File_IO.File_Handle;
      W    : Database.WAL.WAL_Handle;
      P, Q : Database.Storage.Pages.Page;
      Term : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Hits : Database.Full_Text.Postings.Posting_Vectors.Vector;
      L    : Database.Log_Sequence.Log_Sequence_Number;
      R    : Database.Status.Result;
   begin
      Remove_File ("wal_ft_redo.database");
      Remove_File ("wal_ft_redo.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      P := Database.Full_Text.Storage.Build_Posting_Page
        (3, "ada", One_Posting (9));
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      R := Database.WAL.Append_Full_Text_Redo (W, 88, P, L);
      Assert (Database.Status.Is_Ok (R), "append full-text redo failed");
      R := Database.WAL.Append_Commit (W, 88, 1, L);
      Assert (Database.Status.Is_Ok (R), "append commit failed");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "flush failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "close failed");
      R := Database.WAL.Replay_Committed (Path, F);
      Assert (Database.Status.Is_Ok (R), "replay failed");
      R :=
        Database.Storage.File_IO.Read_Page
          (F, 3, Database.Storage.Pages.Full_Text_Posting_Page, Q);
      Assert (Database.Status.Is_Ok (R), "full-text redo page not replayed");
      R := Database.Full_Text.Storage.Parse_Posting_Page (Q, Term, Hits);
      Assert (Database.Status.Is_Ok (R), "replayed posting page did not parse");
      Assert (Natural (Hits.Length) = 1, "wrong replayed posting count");
      Assert (Hits.Element (0).Ref.Row_Id = 9, "wrong replayed posting row");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("wal_ft_redo.database");
      Remove_File ("wal_ft_redo.database.wal");
   end Full_Text_Redo_Replays_Committed_Image;

   procedure Full_Text_Undo_Replays_Uncommitted_Before_Image
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "wal_ft_undo.database";
      F    : Database.Storage.File_IO.File_Handle;
      W    : Database.WAL.WAL_Handle;
      Before, After, Q : Database.Storage.Pages.Page;
      Term : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Hits : Database.Full_Text.Postings.Posting_Vectors.Vector;
      L    : Database.Log_Sequence.Log_Sequence_Number;
      R    : Database.Status.Result;
   begin
      Remove_File ("wal_ft_undo.database");
      Remove_File ("wal_ft_undo.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      Before := Database.Full_Text.Storage.Build_Posting_Page
        (4, "ada", One_Posting (1));
      After := Database.Full_Text.Storage.Build_Posting_Page
        (4, "ada", One_Posting (2));
      R := Database.Storage.File_IO.Write_Page (F, After);
      Assert (Database.Status.Is_Ok (R), "dirty full-text page write failed");
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      R := Database.WAL.Append_Full_Text_Undo (W, 89, Before, L);
      Assert (Database.Status.Is_Ok (R), "append full-text undo failed");
      R := Database.WAL.Flush (W);
      Assert (Database.Status.Is_Ok (R), "flush failed");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "close failed");
      R := Database.WAL.Replay_Committed (Path, F);
      Assert (Database.Status.Is_Ok (R), "replay failed");
      R :=
        Database.Storage.File_IO.Read_Page
          (F, 4, Database.Storage.Pages.Full_Text_Posting_Page, Q);
      Assert (Database.Status.Is_Ok (R), "full-text undo page not readable");
      R := Database.Full_Text.Storage.Parse_Posting_Page (Q, Term, Hits);
      Assert (Database.Status.Is_Ok (R), "undo posting page did not parse");
      Assert (Natural (Hits.Length) = 1, "wrong undo posting count");
      Assert (Hits.Element (0).Ref.Row_Id = 1, "undo did not restore before image");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("wal_ft_undo.database");
      Remove_File ("wal_ft_undo.database.wal");
   end Full_Text_Undo_Replays_Uncommitted_Before_Image;

   procedure Full_Text_WAL_Rejects_Non_Full_Text_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "wal_ft_reject.database";
      F    : Database.Storage.File_IO.File_Handle;
      W    : Database.WAL.WAL_Handle;
      P    : Database.Storage.Pages.Page;
      L    : Database.Log_Sequence.Log_Sequence_Number;
      R    : Database.Status.Result;
   begin
      Remove_File ("wal_ft_reject.database");
      Remove_File ("wal_ft_reject.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.WAL.Append_Full_Text_Redo (W, 90, P, L);
      Assert
        (R.Code = Database.Status.Invalid_Argument,
         "full-text WAL accepted non-full-text page");
      R := Database.WAL.Close (W);
      Assert (Database.Status.Is_Ok (R), "close failed");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Remove_File ("wal_ft_reject.database");
      Remove_File ("wal_ft_reject.database.wal");
   end Full_Text_WAL_Rejects_Non_Full_Text_Page;

   --  Reopening a WAL this process closed cleanly reuses what it knew, continuing the sequence numbers; a WAL that
   --  changed since, or that is no longer trusted, is scanned and normalized again.
   procedure Reopen_Reuses_Clean_Close
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path     : constant Wide_Wide_String := "wal_reopen.database";
      F        : Database.Storage.File_IO.File_Handle;
      W        : Database.WAL.WAL_Handle;
      Previous : Database.Log_Sequence.Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      R        : Database.Status.Result;

      --  Append one commit record and close; its sequence number must follow the previous one.
      procedure Commit_Once (Message : String) is
         L : Database.Log_Sequence.Log_Sequence_Number;
      begin
         R := Database.WAL.Append_Commit (W, 1, 1, L);
         Assert (Database.Status.Is_Ok (R), Message & ": append failed");
         Assert (L > Previous, Message & ": the sequence continues");
         Previous := L;
         R := Database.WAL.Flush (W);
         Assert (Database.Status.Is_Ok (R), Message & ": flush failed");
         R := Database.WAL.Close (W);
         Assert (Database.Status.Is_Ok (R), Message & ": close failed");
      end Commit_Once;

      procedure Reopen (Message : String) is
      begin
         R := Database.WAL.Open (W, Path);
         Assert (Database.Status.Is_Ok (R), Message & ": open failed");
      end Reopen;
   begin
      Remove_File ("wal_reopen.database");
      Remove_File ("wal_reopen.database.wal");
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "db create failed");
      R := Database.WAL.Create (W, Path);
      Assert (Database.Status.Is_Ok (R), "wal create failed");
      Commit_Once ("first commit");
      Reopen ("trusted reopen");
      Commit_Once ("commit after a trusted reopen");
      Database.WAL.Forget_Trusted (Path);
      Reopen ("scanned reopen");
      Commit_Once ("commit after a scanned reopen");
      --  A torn suffix written behind this process's back changes the file, so the next open normalizes it.
      declare
         File : Ada.Streams.Stream_IO.File_Type;
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.Append_File, "wal_reopen.database.wal");
         Ada.Streams.Stream_IO.Write (File, [1 .. 5 => 16#FF#]);
         Ada.Streams.Stream_IO.Close (File);
      end;
      Reopen ("reopen after a torn suffix");
      Commit_Once ("commit after normalizing");
      R := Database.WAL.Validate (Path);
      Assert (Database.Status.Is_Ok (R), "the WAL validates");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "file close failed");
      Database.WAL.Forget_Trusted (Path);
      Remove_File ("wal_reopen.database");
      Remove_File ("wal_reopen.database.wal");
   end Reopen_Reuses_Clean_Close;

   --  The SPARK proof of the payload rules compiles against a copy of the record kinds in spark_stubs, which must name
   --  the same kinds in the same order as the WAL itself.
   procedure SPARK_Stub_Matches_Record_Kinds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  The literals of Record_Kind in the source file at Path, without spaces or line breaks.
      function Record_Kinds (Path : String) return String is
         use Ada.Strings.Unbounded;
         File   : Ada.Text_IO.File_Type;
         Kinds  : Unbounded_String;
         Inside : Boolean := False;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line : constant String := Ada.Text_IO.Get_Line (File);
            begin
               if Ada.Strings.Fixed.Index (Line, "type Record_Kind is") > 0 then
                  Inside := True;
               elsif Inside then
                  for C of Line loop
                     if C /= ' ' then
                        Append (Kinds, C);
                     end if;
                  end loop;
                  exit when Ada.Strings.Fixed.Index (Line, ");") > 0;
               end if;
            end;
         end loop;
         Ada.Text_IO.Close (File);
         return To_String (Kinds);
      end Record_Kinds;

      Kinds : constant String := Record_Kinds ("../src/database-wal.ads");
   begin
      Assert (Kinds'Length > 0, "the WAL record kinds were not found");
      Assert (Record_Kinds ("../spark_stubs/database-wal.ads") = Kinds,
              "spark_stubs/database-wal.ads lists other record kinds than src/database-wal.ads");
   end SPARK_Stub_Matches_Record_Kinds;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Append_Validate_Reopen'Access,
         "append, flush, validate, and reopen WAL");
      Register_Routine
        (T,
         Replay_Ignores_Uncommitted_Frames'Access,
         "replay ignores uncommitted WAL frames");
      Register_Routine
        (T,
         Replay_Applies_Committed_Frames'Access,
         "replay applies committed WAL frames");
      Register_Routine
        (T, Checkpoint_Removes_Safe_WAL'Access, "checkpoint removes safe WAL");
      Register_Routine
        (T,
         Full_Text_Redo_Replays_Committed_Image'Access,
         "full-text redo replays committed image");
      Register_Routine
        (T,
         Full_Text_Undo_Replays_Uncommitted_Before_Image'Access,
         "full-text undo replays uncommitted before image");
      Register_Routine
        (T,
         Full_Text_WAL_Rejects_Non_Full_Text_Page'Access,
         "full-text WAL rejects non-full-text page");
      Register_Routine
        (T, Reopen_Reuses_Clean_Close'Access, "reopening a cleanly closed WAL continues its sequence");
      Register_Routine
        (T, SPARK_Stub_Matches_Record_Kinds'Access, "the SPARK stub lists the WAL record kinds");
   end Register_Tests;
end WAL_Tests;
