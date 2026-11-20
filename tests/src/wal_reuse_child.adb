--  Regression helper for the primary-key-reuse recovery bug.
--
--  Runs in two phases as a real separate process (the bug only manifests
--  across an uncheckpointed restart, not between two handles in one process):
--
--    wal_reuse_child setup  <path>
--        Create the database, insert key 6, delete key 6, commit, then exit
--        abruptly via OS_Exit WITHOUT closing -- leaving an uncheckpointed WAL.
--
--    wal_reuse_child verify <path>
--        Open the database (which replays that WAL), then insert key 6 again
--        and delete it. Before the fix, the replayed committed deletion read
--        back as an untracked transaction, so the row resurrected: the insert
--        returned DUPLICATE_KEY (and a later delete NOT_FOUND). Exits 0 only
--        when both the re-insert and the delete succeed.
--
--  It also ends the process in the middle of a transaction (setup_crash), and
--  checks that recovery undoes it (verify_crash) and leaves it undone after
--  later work (verify_crash_again); and it loses the write of a committed
--  catalog page (setup_lost_catalog) for recovery to restore
--  (verify_lost_catalog).

with Ada.Command_Line;
with Ada.Characters.Conversions; use Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Strings.Wide_Wide_Unbounded; use Ada.Strings.Wide_Wide_Unbounded;

with GNAT.OS_Lib;

with Database;
with Database.Catalog;
with Database.Check;
with Database.Status;
with Database.Storage.Pages;
with Database.Types;
with Database.Values;
with Database.Rows;
with Database.Schema;
with Database.Transactions;
with Database.Tables;

procedure WAL_Reuse_Child is

   type Item is record
      Id : Natural;
   end record;

   function To_Row (I : Item) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (Integer (I.Id)));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Item is
     (Id => Natural (Database.Rows.Get (R, 0).Int));
   function Key_Of (I : Item) return Natural is (I.Id);
   function Key_Value (K : Natural) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (K)));

   package T is new Database.Tables.Typed
     (Row_Type => Item, Key_Type => Natural, To_Row => To_Row,
      From_Row => From_Row, Key_Of => Key_Of, Key_Value => Key_Value);

   function Make_Schema (Name : Wide_Wide_String := "items") return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
   begin
      S.Name := To_Unbounded_Wide_Wide_String (Name);
      Database.Schema.Add_Column
        (S, Name => "id", Kind => Database.Types.Integer_Value,
         Nullable => False, Primary_Key => True);
      return S;
   end Make_Schema;

   Reused_Key : constant Natural := 6;

   Schema : Database.Schema.Table_Schema := Make_Schema;
   DB     : Database.Handle;
   Tx     : Database.Transactions.Transaction;
   Status : Database.Status.Result;

   procedure Fail (Code : Integer) is
   begin
      GNAT.OS_Lib.OS_Exit (Code);
   end Fail;

   function Healthy return Boolean is
      Check_Tx : Database.Transactions.Transaction;
      Result   : Database.Check.Check_Result;
   begin
      Database.Transactions.Begin_Read (DB, Check_Tx);
      Result := Database.Check.Check_Database (Check_Tx);
      Database.Transactions.Commit (Check_Tx);
      return Result.Success;
   end Healthy;

   function Present (Key : Natural) return Boolean is
      Read_Tx : Database.Transactions.Transaction;
      Found   : Item;
      R       : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (DB, Read_Tx);
      R := T.Find (Read_Tx, DB, Schema, Key, Found);
      Database.Transactions.Commit (Read_Tx);
      return Database.Status.Is_Ok (R);
   end Present;

   function Registered (Name : Wide_Wide_String) return Boolean is
      Found : Database.Schema.Table_Schema;
   begin
      return Database.Status.Is_Ok (Database.Catalog.Find_By_Name (Database.Catalog_State_Key (DB), Name, Found));
   end Registered;

   procedure Remove (Name : String) is
   begin
      if Ada.Directories.Exists (Name) then
         Ada.Directories.Delete_File (Name);
      end if;
   end Remove;

begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Fail (64);
   end if;

   declare
      Phase : constant String := Ada.Command_Line.Argument (1);
      Path  : constant String := Ada.Command_Line.Argument (2);
      WPath : constant Wide_Wide_String := To_Wide_Wide_String (Path);
   begin
      if Phase = "setup" then
         Remove (Path);
         Remove (Path & ".wal");
         Remove (Path & ".fts");

         Database.Create (DB, WPath);
         Status := T.Register (DB => DB, Schema => Schema);

         Database.Transactions.Begin_Write (DB, Tx);
         Status := T.Insert (Tx, DB, Schema, (Id => Reused_Key));
         Status := Database.Transactions.Commit (Tx);

         Database.Transactions.Begin_Write (DB, Tx);
         Status := T.Delete (Tx, DB, Schema, Reused_Key);
         Status := Database.Transactions.Commit (Tx);

         --  Exit abruptly, skipping finalization, so the WAL is left
         --  uncheckpointed for the verify phase to replay.
         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "verify" then
         Database.Open (DB, WPath);   --  replays the uncheckpointed WAL
         Status := T.Register (DB => DB, Schema => Schema);

         Database.Transactions.Begin_Write (DB, Tx);
         Status := T.Insert (Tx, DB, Schema, (Id => Reused_Key));
         if not Database.Status.Is_Ok (Status) then
            Database.Transactions.Rollback (Tx);
            Fail (1);   --  re-insert of the reused key failed (DUPLICATE_KEY)
         end if;
         Status := Database.Transactions.Commit (Tx);

         Database.Transactions.Begin_Write (DB, Tx);
         Status := T.Delete (Tx, DB, Schema, Reused_Key);
         if not Database.Status.Is_Ok (Status) then
            Database.Transactions.Rollback (Tx);
            Fail (2);   --  delete of the reused key failed (NOT_FOUND)
         end if;
         Status := Database.Transactions.Commit (Tx);

         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "setup_clean" then
         Remove (Path);
         Remove (Path & ".wal");
         Remove (Path & ".fts");

         Database.Create (DB, WPath);
         Status := T.Register (DB => DB, Schema => Schema);

         --  Many committed transactions, then a clean Close (which checkpoints
         --  and deletes the WAL). The persisted rows carry transaction ids up
         --  to roughly 30, but no WAL survives to replay.
         for K in 1 .. 30 loop
            Database.Transactions.Begin_Write (DB, Tx);
            Status := T.Insert (Tx, DB, Schema, (Id => K));
            Status := Database.Transactions.Commit (Tx);
         end loop;
         Database.Close (DB);
         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "verify_txid" then
         --  Reopen a cleanly checkpointed database (no WAL to replay). A fresh
         --  process resets the transaction counter to 1, so without the
         --  open-time reservation the first write transaction would reuse a low
         --  id that persisted rows still reference. The recovered high-water
         --  mark (derived from the heap) must push it well above them.
         Database.Open (DB, WPath);
         Database.Transactions.Begin_Write (DB, Tx);
         if Database.Transactions.Id (Tx) > 20 then
            GNAT.OS_Lib.OS_Exit (0);
         else
            Fail (3);   --  transaction id was reused after restart
         end if;

      elsif Phase = "setup_crash" then
         Remove (Path);
         Remove (Path & ".wal");
         Remove (Path & ".fts");

         Database.Create (DB, WPath);
         Status := T.Register (DB => DB, Schema => Schema);
         Database.Transactions.Begin_Write (DB, Tx);
         for K in 1 .. 50 loop
            Status := T.Insert (Tx, DB, Schema, (Id => K));
         end loop;
         Status := Database.Transactions.Commit (Tx);

         --  A transaction that grows the file, changes pages the file had and
         --  registers a table, ended by the process before it commits.
         Database.Transactions.Begin_Write (DB, Tx);
         for K in 51 .. 2_000 loop
            Status := T.Insert (Tx, DB, Schema, (Id => K));
         end loop;
         Status := T.Delete (Tx, DB, Schema, 1);
         declare
            Extra : Database.Schema.Table_Schema := Make_Schema ("extra");
         begin
            Status := T.Register (Tx, DB, Extra);
         end;
         if not Database.Status.Is_Ok (Status) then
            Fail (3);
         end if;
         --  The verify phase checks that no later transaction reuses its id.
         declare
            Id_File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Create (Id_File, Ada.Text_IO.Out_File, Path & ".txid");
            Ada.Text_IO.Put_Line (Id_File, Natural'Image (Natural (Database.Transactions.Id (Tx))));
            Ada.Text_IO.Close (Id_File);
         end;
         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "verify_crash" then
         Database.Open (DB, WPath);   --  undoes the interrupted transaction
         Status := T.Register (DB => DB, Schema => Schema);

         --  Later work is logged after the interrupted transaction, under an
         --  id of its own: replay tells transactions apart by id.
         declare
            Id_File     : Ada.Text_IO.File_Type;
            Interrupted : Natural;
         begin
            Ada.Text_IO.Open (Id_File, Ada.Text_IO.In_File, Path & ".txid");
            Interrupted := Natural'Value (Ada.Text_IO.Get_Line (Id_File));
            Ada.Text_IO.Close (Id_File);
            Database.Transactions.Begin_Write (DB, Tx);
            if Natural (Database.Transactions.Id (Tx)) <= Interrupted then
               Fail (12);   --  the interrupted transaction's id is used again
            end if;
         end;
         Status := T.Insert (Tx, DB, Schema, (Id => 60));
         if Database.Status.Is_Ok (Status) then
            Status := Database.Transactions.Commit (Tx);
         end if;
         if not Database.Status.Is_Ok (Status) then
            Fail (8);
         end if;

         if not Healthy then
            Fail (4);   --  pages of the interrupted transaction remain
         elsif not Present (1) then
            Fail (5);   --  its delete remains
         elsif Present (51) then
            Fail (6);   --  its insert remains
         elsif Registered ("extra") then
            Fail (7);   --  its registration remains
         end if;
         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "verify_crash_again" then
         Database.Open (DB, WPath);   --  replays the same log once more
         Status := T.Register (DB => DB, Schema => Schema);
         if not Healthy then
            Fail (9);
         elsif not Present (60) then
            Fail (10);   --  the later work was undone with the interrupted transaction
         elsif Present (51) or else not Present (1) then
            Fail (11);   --  the interrupted transaction came back
         end if;
         Database.Close (DB);
         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "setup_lost_catalog" then
         Remove (Path);
         Remove (Path & ".wal");
         Remove (Path & ".fts");

         Database.Create (DB, WPath);
         Database.Close (DB);
         declare
            use Ada.Streams;
            Catalog_At : constant Stream_IO.Positive_Count :=
              Stream_IO.Positive_Count (Database.Storage.Pages.Page_Size + 1);
            File       : Stream_IO.File_Type;
            Old_Page   : Stream_Element_Array (1 .. Database.Storage.Pages.Page_Size);
            Last       : Stream_Element_Offset;
         begin
            Stream_IO.Open (File, Stream_IO.In_File, Path);
            Stream_IO.Set_Index (File, Catalog_At);
            Stream_IO.Read (File, Old_Page, Last);
            Stream_IO.Close (File);

            --  Registering commits the catalog page through the WAL.
            Database.Open (DB, WPath);
            Status := T.Register (DB => DB, Schema => Schema);
            if not Database.Status.Is_Ok (Status) then
               Fail (20);
            end if;

            --  Lose the write of the page: put the page as it was back.
            declare
               Content : Stream_Element_Array (1 .. Stream_Element_Offset (Ada.Directories.Size (Path)));
               At_Page : constant Stream_Element_Offset := Stream_Element_Offset (Catalog_At);
            begin
               --  The database still has the file open.
               Stream_IO.Open (File, Stream_IO.In_File, Path, Form => "shared=no");
               Stream_IO.Read (File, Content, Last);
               Stream_IO.Close (File);
               Content (At_Page .. At_Page + Old_Page'Length - 1) := Old_Page;
               Stream_IO.Create (File, Stream_IO.Out_File, Path, Form => "shared=no");
               Stream_IO.Write (File, Content);
               Stream_IO.Close (File);
            end;
         end;
         GNAT.OS_Lib.OS_Exit (0);

      elsif Phase = "verify_lost_catalog" then
         Database.Open (DB, WPath);   --  writes the committed catalog page again
         if not Registered ("items") then
            Fail (21);
         elsif not Healthy then
            Fail (22);
         end if;
         Database.Close (DB);
         GNAT.OS_Lib.OS_Exit (0);

      else
         Fail (64);
      end if;
   end;
end WAL_Reuse_Child;
