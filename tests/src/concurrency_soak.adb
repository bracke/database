--  Phase 0 acceptance runnable for concurrent multi-database support.
--
--  Each worker task drives its OWN in-memory database concurrently and must see
--  only its own data. It exposes the process-global "current database"
--  selection bug (see docs/concurrency-multidb-plan.md): today it fails
--  intermittently; after the fix it must pass every round, and -- built with
--  -fsanitize=thread -- report no data races.
--
--  It is deliberately NOT part of the always-green AUnit suite, because it
--  fails against the current engine. Run it directly:
--
--     ./bin/concurrency_soak [rounds]      -- default rounds = 8
--
--  Exit status 0 = every concurrent database stayed isolated; 1 = corruption.

with Ada.Command_Line;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Text_IO;

with Database;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

procedure Concurrency_Soak is

   Workers_Per_Round : constant := 6;
   Rows_Per_Worker   : constant := 40;
   Reads_Per_Worker  : constant := 40;

   type Item is record
      Id    : Integer;
      Value : Integer;
   end record;

   function To_Row (X : Item) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (X.Id));
      Database.Rows.Append (R, Database.Values.From_Integer (X.Value));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Item is
     (Id    => Database.Rows.Get (R, 0).Int,
      Value => Database.Rows.Get (R, 1).Int);

   function Key_Of (X : Item) return Integer is (X.Id);
   function Key_Value (K : Integer) return Database.Values.Value is
     (Database.Values.From_Integer (K));

   package Items is new Database.Tables.Typed
     (Item, Integer, To_Row, From_Row, Key_Of, Key_Value);

   procedure Build_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("items");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "value", Database.Types.Integer_Value, False);
   end Build_Schema;

   protected Outcome is
      procedure Fail;
      function Failed return Boolean;
      procedure Next_Seed (Seed : out Natural);
   private
      Bad       : Boolean := False;
      Seed_Next : Natural := 1;
   end Outcome;

   protected body Outcome is
      procedure Fail is
      begin
         Bad := True;
      end Fail;
      function Failed return Boolean is (Bad);
      procedure Next_Seed (Seed : out Natural) is
      begin
         Seed := Seed_Next;
         Seed_Next := Seed_Next + 1;
      end Next_Seed;
   end Outcome;

   task type Worker;
   task body Worker is
      Seed  : Natural;
      DB    : Database.Handle;
      S     : Database.Schema.Table_Schema;
      Tx    : Database.Transactions.Transaction;
      R     : Database.Status.Result;
      Found : Item;
   begin
      Outcome.Next_Seed (Seed);
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      if not Database.Status.Is_Ok (R) then
         Outcome.Fail;
      else
         for K in 1 .. Rows_Per_Worker loop
            Database.Transactions.Begin_Write (DB, Tx);
            R := Items.Insert
              (Tx, DB, S, (Id => K, Value => Seed * 10_000 + K));
            R := Database.Transactions.Commit (Tx);
         end loop;

         for Rep in 1 .. Reads_Per_Worker loop
            for K in 1 .. Rows_Per_Worker loop
               Database.Transactions.Begin_Read (DB, Tx);
               R := Items.Find (Tx, DB, S, K, Found);
               if not Database.Status.Is_Ok (R)
                 or else Found.Value /= Seed * 10_000 + K
               then
                  Outcome.Fail;
               end if;
               R := Database.Transactions.Commit (Tx);
            end loop;
         end loop;

         Database.Close (DB);
      end if;
   end Worker;

   Rounds : Natural := 8;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      begin
         Rounds := Natural'Value (Ada.Command_Line.Argument (1));
      exception
         when others => Rounds := 8;
      end;
   end if;

   for Round in 1 .. Rounds loop
      declare
         Team : array (1 .. Workers_Per_Round) of Worker;
         pragma Unreferenced (Team);
      begin
         null;  --  block until every worker in this round terminates
      end;
      exit when Outcome.Failed;
   end loop;

   if Outcome.Failed then
      Ada.Text_IO.Put_Line
        ("SOAK FAIL: concurrent databases were not isolated");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Ada.Text_IO.Put_Line
        ("SOAK OK: concurrent databases stayed isolated ("
         & Rounds'Image & " rounds)");
      Ada.Command_Line.Set_Exit_Status (0);
   end if;
end Concurrency_Soak;
