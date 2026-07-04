with AUnit.Assertions;

with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.MVCC;
with Database.Predicates;
with Database.Queries;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body MVCC_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("mvcc snapshot isolation");
   end Name;

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
   begin
      return
        (Id    => Database.Rows.Get (R, 0).Int,
         Value => Database.Rows.Get (R, 1).Int);
   end From_Row;

   function Key_Of (X : Item) return Integer
   is (X.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   package Items is new
     Database.Tables.Typed
       (Item,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   procedure Build_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("mvcc_items");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "value", Database.Types.Integer_Value, False);
   end Build_Schema;

   procedure Snapshot_Hides_Newer_Committed_Row
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB     : Database.Handle;
      S      : Database.Schema.Table_Schema;
      Reader : Database.Transactions.Transaction;
      Writer : Database.Transactions.Transaction;
      Later  : Database.Transactions.Transaction;
      R      : Database.Status.Result;
      Found  : Item;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Read (DB, Reader);
      Database.Transactions.Begin_Write (DB, Writer);
      R := Items.Insert (Writer, DB, S, (Id => 1, Value => 10));
      Assert (Database.Status.Is_Ok (R), "writer insert failed");
      R := Items.Find (Reader, DB, S, 1, Found);
      Assert
        (R.Code = Database.Status.Not_Found,
         "old snapshot saw uncommitted row");
      R := Database.Transactions.Commit (Writer);
      Assert (Database.Status.Is_Ok (R), "writer commit failed");
      R := Items.Find (Reader, DB, S, 1, Found);
      Assert
        (R.Code = Database.Status.Not_Found,
         "old snapshot saw newer committed row");
      R := Database.Transactions.Commit (Reader);
      Assert (Database.Status.Is_Ok (R), "reader commit failed");

      Database.Transactions.Begin_Read (DB, Later);
      R := Items.Find (Later, DB, S, 1, Found);
      Assert
        (Database.Status.Is_Ok (R),
         "later snapshot did not see committed row");
      Assert (Found.Value = 10, "later snapshot read wrong value");
      R := Database.Transactions.Commit (Later);
      Assert (Database.Status.Is_Ok (R), "later commit failed");
      Database.Close (DB);
   end Snapshot_Hides_Newer_Committed_Row;

   procedure Own_Writes_And_Rollback
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB     : Database.Handle;
      S      : Database.Schema.Table_Schema;
      Writer : Database.Transactions.Transaction;
      Reader : Database.Transactions.Transaction;
      R      : Database.Status.Result;
      Found  : Item;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Writer);
      R := Items.Insert (Writer, DB, S, (Id => 7, Value => 70));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Items.Find (Writer, DB, S, 7, Found);
      Assert (Database.Status.Is_Ok (R), "writer did not see own insert");
      R := Database.Transactions.Rollback (Writer);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Transactions.Begin_Read (DB, Reader);
      R := Items.Find (Reader, DB, S, 7, Found);
      Assert
        (R.Code = Database.Status.Not_Found,
         "rolled-back insert remained visible");
      R := Database.Transactions.Commit (Reader);
      Assert (Database.Status.Is_Ok (R), "reader commit failed");
      Database.Close (DB);
   end Own_Writes_And_Rollback;

   procedure Delete_Remains_Visible_To_Older_Snapshot
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      S     : Database.Schema.Table_Schema;
      W     : Database.Transactions.Transaction;
      Old_R : Database.Transactions.Transaction;
      New_R : Database.Transactions.Transaction;
      R     : Database.Status.Result;
      Found : Item;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, W);
      R := Items.Insert (W, DB, S, (Id => 3, Value => 30));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (W);
      Assert (Database.Status.Is_Ok (R), "insert commit failed");

      Database.Transactions.Begin_Read (DB, Old_R);
      Database.Transactions.Begin_Write (DB, W);
      R := Items.Delete (W, DB, S, 3);
      Assert (Database.Status.Is_Ok (R), "delete failed");
      R := Database.Transactions.Commit (W);
      Assert (Database.Status.Is_Ok (R), "delete commit failed");
      R := Items.Find (Old_R, DB, S, 3, Found);
      Assert (Database.Status.Is_Ok (R), "older snapshot lost deleted row");
      R := Database.Transactions.Commit (Old_R);
      Assert (Database.Status.Is_Ok (R), "old reader commit failed");

      Database.Transactions.Begin_Read (DB, New_R);
      R := Items.Find (New_R, DB, S, 3, Found);
      Assert
        (R.Code = Database.Status.Not_Found, "new snapshot saw deleted row");
      R := Database.Transactions.Commit (New_R);
      Assert (Database.Status.Is_Ok (R), "new reader commit failed");
      Database.Close (DB);
   end Delete_Remains_Visible_To_Older_Snapshot;

   procedure Rolled_Back_Insert_Stays_Invisible_After_Later_Commit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      S     : Database.Schema.Table_Schema;
      W     : Database.Transactions.Transaction;
      Rdr   : Database.Transactions.Transaction;
      R     : Database.Status.Result;
      Found : Item;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (DB, W);
      R := Items.Insert (W, DB, S, (Id => 11, Value => 110));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Rollback (W);
      Assert (Database.Status.Is_Ok (R), "rollback failed");

      Database.Transactions.Begin_Write (DB, W);
      R := Items.Insert (W, DB, S, (Id => 12, Value => 120));
      Assert (Database.Status.Is_Ok (R), "second insert failed");
      R := Database.Transactions.Commit (W);
      Assert (Database.Status.Is_Ok (R), "second commit failed");

      Database.Transactions.Begin_Read (DB, Rdr);
      R := Items.Find (Rdr, DB, S, 11, Found);
      Assert
        (R.Code = Database.Status.Not_Found,
         "rolled-back insert became visible after unrelated commit");
      R := Items.Find (Rdr, DB, S, 12, Found);
      Assert (Database.Status.Is_Ok (R), "committed insert missing");
      R := Database.Transactions.Commit (Rdr);
      Assert (Database.Status.Is_Ok (R), "reader commit failed");
      Database.Close (DB);
   end Rolled_Back_Insert_Stays_Invisible_After_Later_Commit;

   procedure Rolled_Back_Delete_Does_Not_Delete_After_Later_Commit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      S     : Database.Schema.Table_Schema;
      W     : Database.Transactions.Transaction;
      Rdr   : Database.Transactions.Transaction;
      R     : Database.Status.Result;
      Found : Item;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (DB, W);
      R := Items.Insert (W, DB, S, (Id => 21, Value => 210));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (W);
      Assert (Database.Status.Is_Ok (R), "commit failed");

      Database.Transactions.Begin_Write (DB, W);
      R := Items.Delete (W, DB, S, 21);
      Assert (Database.Status.Is_Ok (R), "delete failed");
      R := Database.Transactions.Rollback (W);
      Assert (Database.Status.Is_Ok (R), "rollback delete failed");

      Database.Transactions.Begin_Write (DB, W);
      R := Items.Insert (W, DB, S, (Id => 22, Value => 220));
      Assert (Database.Status.Is_Ok (R), "unrelated insert failed");
      R := Database.Transactions.Commit (W);
      Assert (Database.Status.Is_Ok (R), "unrelated commit failed");

      Database.Transactions.Begin_Read (DB, Rdr);
      R := Items.Find (Rdr, DB, S, 21, Found);
      Assert
        (Database.Status.Is_Ok (R),
         "rolled-back delete became effective after unrelated commit");
      Assert (Found.Value = 210, "wrong restored row value");
      R := Database.Transactions.Commit (Rdr);
      Assert (Database.Status.Is_Ok (R), "reader commit failed");
      Database.Close (DB);
   end Rolled_Back_Delete_Does_Not_Delete_After_Later_Commit;

   procedure Active_Snapshot_Tracking
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      Assert
        (Database.MVCC.Has_Active_Snapshot, "active snapshot not tracked");
      Assert
        (Database.MVCC.Oldest_Active_Snapshot
         = Database.Transactions.Snapshot_Version (Tx),
         "oldest active snapshot wrong");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
   end Active_Snapshot_Tracking;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Snapshot_Hides_Newer_Committed_Row'Access,
         "snapshot hides uncommitted and newer committed row");
      Register_Routine
        (T,
         Own_Writes_And_Rollback'Access,
         "own writes visible and rollback hides insert");
      Register_Routine
        (T,
         Delete_Remains_Visible_To_Older_Snapshot'Access,
         "delete remains visible to older snapshot");
      Register_Routine
        (T,
         Rolled_Back_Insert_Stays_Invisible_After_Later_Commit'Access,
         "rolled-back insert stays invisible after later commit");
      Register_Routine
        (T,
         Rolled_Back_Delete_Does_Not_Delete_After_Later_Commit'Access,
         "rolled-back delete does not become effective later");
      Register_Routine
        (T,
         Active_Snapshot_Tracking'Access,
         "active snapshot tracking supports vacuum safety");
   end Register_Tests;
end MVCC_Tests;
