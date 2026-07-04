with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Catalog;
with Database.Cursors; use Database.Cursors;
with Database.Check;
with Database.Diagnostics;
with Database.Predicates;
with Database.Queries;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;
with Database.Storage.Record_Format;
with Database.Tables;
with Database.Transactions; use Database.Transactions;
with Database.Types;
with Database.Values;

package body Release_Hardening_Tests is
   use AUnit.Assertions;
   use Ada.Strings.Wide_Wide_Unbounded;

   type Item is record
      Id    : Integer;
      Name  : Wide_Wide_String (1 .. 16);
      Score : Integer;
   end record;

   function To_Row (I : Item) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (I.Id));
      Database.Rows.Append (R, Database.Values.From_Text (I.Name));
      Database.Rows.Append (R, Database.Values.From_Integer (I.Score));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Item is
      S : constant Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      I : Item :=
        (Database.Rows.Get (R, 0).Int,
         (others => ' '),
         Database.Rows.Get (R, 2).Int);
   begin
      for N in 1 .. Integer'Min (16, S'Length) loop
         I.Name (N) := S (S'First + N - 1);
      end loop;
      return I;
   end From_Row;

   function Key_Of (I : Item) return Integer
   is (I.Id);
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

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("release hardening");
   end Name;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Build_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name := To_Unbounded_Wide_Wide_String ("items");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "score", Database.Types.Integer_Value, False);
   end Build_Schema;

   procedure Deterministic_Mixed_Workload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema;
      R        : Database.Status.Result;
      Out_Item : Item;
      Path     : constant Wide_Wide_String := "release_hardening_workload.database";
   begin
      Delete_If_Exists ("release_hardening_workload.database");
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (DB, Tx);
      for N in 1 .. 200 loop
         R := Items.Insert (Tx, DB, S, (N, "release-item    ", N * 3));
         Assert (Database.Status.Is_Ok (R), "bulk insert failed");
      end loop;
      for N in 1 .. 50 loop
         R := Items.Update (Tx, DB, S, (N, "updated-item    ", N * 5));
         Assert (Database.Status.Is_Ok (R), "bulk update failed");
      end loop;
      for N in 151 .. 200 loop
         R := Items.Delete (Tx, DB, S, N);
         Assert (Database.Status.Is_Ok (R), "bulk delete failed");
      end loop;
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "reopen failed");
      R := Database.Catalog.Find_By_Name ("items", S);
      Assert (Database.Status.Is_Ok (R), "catalog lookup failed");
      Database.Transactions.Begin_Read (DB, Tx);
      R := Items.Find (Tx, DB, S, 25, Out_Item);
      Assert (Database.Status.Is_Ok (R), "find updated row failed");
      Assert (Out_Item.Score = 125, "updated score was not durable");
      R := Items.Find (Tx, DB, S, 175, Out_Item);
      Assert (not Database.Status.Is_Ok (R), "deleted row was durable");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");
      Database.Close (DB);
      Delete_If_Exists ("release_hardening_workload.database");
   end Deterministic_Mixed_Workload;

   procedure Serialization_Property_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S      : Database.Schema.Table_Schema;
      R1, R2 : Database.Rows.Row;
      Enc    : Database.Storage.Record_Format.Byte_Vector;
      Res    : Database.Status.Result;
   begin
      Build_Schema (S);
      for N in 1 .. 64 loop
         R1.Values.Clear;
         Database.Rows.Append (R1, Database.Values.From_Integer (N));
         Database.Rows.Append (R1, Database.Values.From_Text ("Grüße 😀"));
         Database.Rows.Append
           (R1, Database.Values.From_Integer ((N * 7919) mod 997));
         Res := Database.Storage.Record_Format.Serialize (S, R1, Enc);
         Assert (Database.Status.Is_Ok (Res), "serialize failed");
         Assert (Enc.Last > 0, "serialized record must not be empty");
         declare
            D : Database.Storage.Pages.Byte_Array (0 .. Enc.Last - 1);
         begin
            for I in D'Range loop
               D (I) := Enc.Data (I);
            end loop;
            R2.Values.Clear;
            Res := Database.Storage.Record_Format.Deserialize (S, D, R2);
         end;
         Assert (Database.Status.Is_Ok (Res), "deserialize failed");
         Assert
           (Database.Values.Equal
              (Database.Rows.Get (R1, 0), Database.Rows.Get (R2, 0)),
            "id changed");
         Assert
           (Database.Values.Equal
              (Database.Rows.Get (R1, 1), Database.Rows.Get (R2, 1)),
            "unicode text changed");
         Assert
           (Database.Values.Equal
              (Database.Rows.Get (R1, 2), Database.Rows.Get (R2, 2)),
            "score changed");
      end loop;
   end Serialization_Property_Round_Trips;

   procedure Check_And_Diagnostics_Are_Usable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      Tx    : Database.Transactions.Transaction;
      S     : Database.Schema.Table_Schema;
      R     : Database.Status.Result;
      Check : Database.Check.Check_Result;
   begin
      Database.Open_In_Memory (DB);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Read (DB, Tx);
      Check := Database.Check.Check_Database (Tx);
      Assert (Check.Success, "check failed on fresh in-memory database");
      Assert
        (Database.Diagnostics.Page_Count (Tx) >= 0,
         "page count diagnostic invalid");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
   end Check_And_Diagnostics_Are_Usable;

   procedure Cursor_Owner_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      Tx    : Database.Transactions.Transaction;
      State : Database.Cursors.Cursor_State;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      State :=
        Database.Cursors.Validate_Owner
          (Tx,
           Database.Transactions.Id (Tx),
           Database.Transactions.Snapshot_Version (Tx),
           True);
      Assert
        (Database.Cursors.Is_Valid (State), "cursor owner should validate");
      State :=
        Database.Cursors.Validate_Owner
          (Tx,
           Database.Transactions.Id (Tx) + 1,
           Database.Transactions.Snapshot_Version (Tx),
           True);
      Assert
        (State = Database.Cursors.Wrong_Transaction,
         "wrong owner transaction was not detected");
      State :=
        Database.Cursors.Validate_Owner
          (Tx,
           Database.Transactions.Id (Tx),
           Database.Transactions.Snapshot_Version (Tx),
           False);
      Assert
        (State = Database.Cursors.No_Element,
         "empty cursor state was not detected");
      Assert
        (not Database.Status.Is_Ok (Database.Cursors.To_Result (State)),
         "invalid cursor state converted to success");
      Database.Transactions.Rollback (Tx);
      State :=
        Database.Cursors.Validate_Owner
          (Tx,
           Database.Transactions.Id (Tx),
           Database.Transactions.Snapshot_Version (Tx),
           True);
      Assert
        (State = Database.Cursors.Closed_Transaction,
         "closed transaction was not detected");
      Database.Close (DB);
   end Cursor_Owner_Validation;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Deterministic_Mixed_Workload'Access,
         "deterministic persistent mixed workload");
      Register_Routine
        (T,
         Serialization_Property_Round_Trips'Access,
         "deterministic serialization property round trips");
      Register_Routine
        (T,
         Check_And_Diagnostics_Are_Usable'Access,
         "check and diagnostics smoke test");
      Register_Routine
        (T, Cursor_Owner_Validation'Access, "cursor owner validation");
   end Register_Tests;
end Release_Hardening_Tests;
