with AUnit.Assertions;

with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Check;
with Database.Catalog;
with Database.Diagnostics;

with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Database.Vacuum;

package body Maintenance_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;

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

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("maintenance check vacuum diagnostics");
   end Name;

   procedure Build_Schema (S : in out Database.Schema.Table_Schema) is
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("items");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "value", Database.Types.Integer_Value, False);
   end Build_Schema;

   procedure Healthy_Check_And_Diagnostics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      CR   : Database.Check.Check_Result;
      Path : constant Wide_Wide_String := "maintenance_check.database";
   begin
      if Ada.Directories.Exists ("maintenance_check.database") then
         Ada.Directories.Delete_File ("maintenance_check.database");
      end if;
      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      for I in 1 .. 20 loop
         R := Items.Insert (Tx, DB, S, (Id => I, Value => I * 10));
         Assert (Database.Status.Is_Ok (R), "insert failed");
      end loop;
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");

      Database.Transactions.Begin_Read (DB, Tx);
      CR := Database.Check.Check_Database (Tx);
      Assert (CR.Success, "healthy database failed integrity check");
      Assert
        (Database.Diagnostics.Page_Count (Tx) >= 2, "page count not reported");
      Assert
        (Database.Diagnostics.Table_Row_Count (Tx, S) = 20, "wrong row count");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");
      Database.Close (DB);
      if Ada.Directories.Exists ("maintenance_check.database") then
         Ada.Directories.Delete_File ("maintenance_check.database");
      end if;
   end Healthy_Check_And_Diagnostics;

   procedure Vacuum_Requires_Write_And_Preserves_Data
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema;
      R        : Database.Status.Result;
      Out_Item : Item;
      Path     : constant Wide_Wide_String := "maintenance_vacuum.database";
   begin
      if Ada.Directories.Exists ("maintenance_vacuum.database") then
         Ada.Directories.Delete_File ("maintenance_vacuum.database");
      end if;
      Database.Create (DB, Path);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 100));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");

      Database.Transactions.Begin_Read (DB, Tx);
      R := Database.Vacuum.Vacuum (Tx);
      Assert (not Database.Status.Is_Ok (R), "read-only vacuum accepted");
      Database.Transactions.Rollback (Tx);

      Database.Transactions.Begin_Write (DB, Tx);
      R := Database.Vacuum.Vacuum (Tx);
      Assert (Database.Status.Is_Ok (R), "vacuum failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "vacuum commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name ("items", S);
      Assert (Database.Status.Is_Ok (R), "catalog not preserved");
      Database.Transactions.Begin_Read (DB, Tx);
      R := Items.Find (Tx, DB, S, 1, Out_Item);
      Assert (Database.Status.Is_Ok (R), "row missing after vacuum");
      Assert (Out_Item.Value = 100, "wrong row after vacuum");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
      if Ada.Directories.Exists ("maintenance_vacuum.database") then
         Ada.Directories.Delete_File ("maintenance_vacuum.database");
      end if;
   end Vacuum_Requires_Write_And_Preserves_Data;

   procedure Vacuum_Reclaims_Index_Candidates
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema;
      R        : Database.Status.Result;
      Out_Item : Item;
      Path     : constant Wide_Wide_String := "maintenance_vacuum_indexes.database";
   begin
      if Ada.Directories.Exists ("maintenance_vacuum_indexes.database") then
         Ada.Directories.Delete_File ("maintenance_vacuum_indexes.database");
      end if;

      Database.Create (DB, Path);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Create_Index (Tx, DB, S, "value_unique", 1, True);
      Assert (Database.Status.Is_Ok (R), "create unique secondary index failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "index commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 100));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "insert commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Delete (Tx, DB, S, 1);
      Assert (Database.Status.Is_Ok (R), "delete failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "delete commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Database.Vacuum.Vacuum (Tx);
      Assert (Database.Status.Is_Ok (R), "vacuum failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "vacuum commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 100));
      Assert
        (Database.Status.Is_Ok (R),
         "reinsert after vacuum should not see reclaimed index candidates");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "reinsert commit failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      R := Database.Catalog.Find_By_Name ("items", S);
      Assert (Database.Status.Is_Ok (R), "catalog not preserved");
      Database.Transactions.Begin_Read (DB, Tx);
      R := Items.Find (Tx, DB, S, 1, Out_Item);
      Assert (Database.Status.Is_Ok (R), "reinserted row missing after reopen");
      Assert (Out_Item.Value = 100, "wrong reinserted row after reopen");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);

      if Ada.Directories.Exists ("maintenance_vacuum_indexes.database") then
         Ada.Directories.Delete_File ("maintenance_vacuum_indexes.database");
      end if;
   end Vacuum_Reclaims_Index_Candidates;

   procedure Corrupt_Heap_Page_Is_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Ada.Streams;
      use Ada.Streams.Stream_IO;
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      CR   : Database.Check.Check_Result;
      F    : File_Type;
      B    : Stream_Element_Array (1 .. 1) := [1 => 16#FF#];
      Path : constant Wide_Wide_String := "maintenance_corrupt.database";
   begin
      if Ada.Directories.Exists ("maintenance_corrupt.database") then
         Ada.Directories.Delete_File ("maintenance_corrupt.database");
      end if;
      Database.Create (DB, Path);
      Build_Schema (S);
      R := Items.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R := Items.Insert (Tx, DB, S, (Id => 1, Value => 10));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      Open (F, Out_File, "maintenance_corrupt.database");
      Set_Index
        (F,
         Positive_Count
           (S.Heap_First_Page
            * Database.Storage.Pages.Page_Size
            + 6));
      Write (F, B);
      Close (F);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "open after heap corruption failed before check");
      Database.Transactions.Begin_Read (DB, Tx);
      CR := Database.Check.Check_Database (Tx);
      Assert (not CR.Success, "corrupt heap page was not detected");
      Database.Transactions.Rollback (Tx);
      Database.Close (DB);
      if Ada.Directories.Exists ("maintenance_corrupt.database") then
         Ada.Directories.Delete_File ("maintenance_corrupt.database");
      end if;
   end Corrupt_Heap_Page_Is_Detected;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Healthy_Check_And_Diagnostics'Access,
         "healthy check and diagnostics");
      Register_Routine
        (T,
         Vacuum_Requires_Write_And_Preserves_Data'Access,
         "vacuum requires write and preserves rows");
      Register_Routine
        (T,
         Vacuum_Reclaims_Index_Candidates'Access,
         "vacuum reclaims obsolete index candidates");
      Register_Routine
        (T,
         Corrupt_Heap_Page_Is_Detected'Access,
         "corrupt heap page is detected");
   end Register_Tests;
end Maintenance_Tests;
