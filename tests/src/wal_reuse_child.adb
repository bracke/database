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

with Ada.Command_Line;
with Ada.Characters.Conversions; use Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded; use Ada.Strings.Wide_Wide_Unbounded;

with GNAT.OS_Lib;

with Database;
with Database.Status;
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

   function Make_Schema return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
   begin
      S.Name := To_Unbounded_Wide_Wide_String ("items");
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

      else
         Fail (64);
      end if;
   end;
end WAL_Reuse_Child;
