with AUnit.Assertions;

with Ada.Directories;
with Database;
with Database.Checkpointing;
with Database.Full_Text.Postings;
with Database.Full_Text.Storage;
with Database.Log_Sequence;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
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
   end Register_Tests;
end WAL_Tests;
