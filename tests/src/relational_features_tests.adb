with AUnit.Assertions;

with Database.Transactions;
with Database.Tables;
with Database.Catalog;
with Database;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Directories;
with Database.Check_Constraints;
with Database.Expressions;
with Database.Foreign_Keys;
with Database.Generated_Columns;
with Database.Indexes;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Types;
with Database.Values;
with Database.Views;
with Database.Materialized_Views;
with Database.Queries;

package body Relational_Features_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;
   use type Database.Indexes.Ordering;
   use type Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;

   type Person_Row is record
      Id         : Integer;
      Age        : Integer;
      Double_Age : Integer;
   end record;

   function To_Row (P : Person_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (P.Id));
      Database.Rows.Append (R, Database.Values.From_Integer (P.Age));
      Database.Rows.Append (R, Database.Values.From_Integer (P.Double_Age));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Person_Row is
   begin
      return
        (Id         => Database.Rows.Get (R, 0).Int,
         Age        => Database.Rows.Get (R, 1).Int,
         Double_Age => Database.Rows.Get (R, 2).Int);
   end From_Row;

   function Key_Of (P : Person_Row) return Integer
   is (P.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   package People is new
     Database.Tables.Typed
       (Person_Row,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   type Child_Row is record
      Id        : Integer;
      Parent_Id : Integer;
   end record;

   function Child_To_Row (C : Child_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (C.Id));
      Database.Rows.Append (R, Database.Values.From_Integer (C.Parent_Id));
      return R;
   end Child_To_Row;

   function Child_From_Row (R : Database.Rows.Row) return Child_Row is
   begin
      return
        (Id        => Database.Rows.Get (R, 0).Int,
         Parent_Id => Database.Rows.Get (R, 1).Int);
   end Child_From_Row;

   function Child_Key_Of (C : Child_Row) return Integer
   is (C.Id);
   function Child_Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   package Children is new
     Database.Tables.Typed
       (Child_Row,
        Integer,
        Child_To_Row,
        Child_From_Row,
        Child_Key_Of,
        Child_Key_Value);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("advanced relational features");
   end Name;

   function Person_Schema return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
   begin
      S.Table_Id := 1;
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False, False);
      Database.Schema.Add_Column
        (S, "double_age", Database.Types.Integer_Value, False, False);
      return S;
   end Person_Schema;

   procedure Check_Constraint_Rejects_Invalid_Row
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S   : constant Database.Schema.Table_Schema := Person_Schema;
      Rw  : Database.Rows.Row;
      C   : Database.Check_Constraints.Check_Constraint;
      Res : Database.Status.Result;
   begin
      Database.Rows.Append (Rw, Database.Values.From_Integer (1));
      Database.Rows.Append (Rw, Database.Values.From_Integer (-1));
      Database.Rows.Append (Rw, Database.Values.From_Integer (-2));
      C :=
        Database.Check_Constraints.Create
          ("age_non_negative",
           Database.Expressions.Binary
             (Database.Expressions.Greater_Or_Equal_Expr,
              Database.Expressions.Column (1),
              Database.Expressions.Literal
                (Database.Values.From_Integer (0))));
      Res := Database.Check_Constraints.Validate_Row (C, S, Rw);
      Assert
        (Res.Code = Database.Status.Constraint_Error,
         "negative age was accepted");
   end Check_Constraint_Rejects_Invalid_Row;

   procedure Generated_Column_Recomputes_Stored_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S    : constant Database.Schema.Table_Schema := Person_Schema;
      Rw   : Database.Rows.Row;
      Cols : Database.Generated_Columns.Generated_Column_Vectors.Vector;
      Res  : Database.Status.Result;
   begin
      Database.Rows.Append (Rw, Database.Values.From_Integer (1));
      Database.Rows.Append (Rw, Database.Values.From_Integer (21));
      Database.Rows.Append (Rw, Database.Values.Null_Value);
      Cols.Append
        (Database.Generated_Columns.Create
           (2,
            "double_age",
            Database.Expressions.Binary
              (Database.Expressions.Multiply_Expr,
               Database.Expressions.Column (1),
               Database.Expressions.Literal
                 (Database.Values.From_Integer (2)))));
      Res := Database.Generated_Columns.Recompute_Stored (Cols, S, Rw);
      Assert (Database.Status.Is_Ok (Res), "recompute failed");
      Assert (Database.Rows.Get (Rw, 2).Int = 42, "wrong generated value");
      Res := Database.Generated_Columns.Validate_Stored (Cols, S, Rw);
      Assert
        (Database.Status.Is_Ok (Res),
         "stored generated value failed validation");
   end Generated_Column_Recomputes_Stored_Value;

   procedure Composite_Key_Comparison_Is_Lexicographic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      L, R : Database.Indexes.Composite_Key;
      O    : Database.Indexes.Ordering;
      Res  : Database.Status.Result;
   begin
      L.Parts.Append (Database.Values.From_Integer (1));
      L.Parts.Append (Database.Values.From_Text ("b"));
      R.Parts.Append (Database.Values.From_Integer (1));
      R.Parts.Append (Database.Values.From_Text ("c"));
      Res := Database.Indexes.Compare_Composite (L, R, O);
      Assert (Database.Status.Is_Ok (Res), "composite compare failed");
      Assert
        (O = Database.Indexes.Less,
         "composite comparison is not lexicographic");
   end Composite_Key_Comparison_Is_Lexicographic;

   procedure Foreign_Key_Null_And_Match_Semantics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Parent, Child           : Database.Schema.Table_Schema;
      Child_Row, Parent_Row   : Database.Rows.Row;
      Parent_Rows             : Database.Foreign_Keys.Row_Vectors.Vector;
      Child_Cols, Parent_Cols : Database.Foreign_Keys.Column_Id_Vectors.Vector;
      FK                      : Database.Foreign_Keys.Foreign_Key_Definition;
      Res                     : Database.Status.Result;
   begin
      Parent.Table_Id := 1;
      Child.Table_Id := 2;
      Database.Schema.Add_Column
        (Parent, "a", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (Parent, "b", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (Child, "a", Database.Types.Integer_Value, True, False);
      Database.Schema.Add_Column
        (Child, "b", Database.Types.Integer_Value, True, False);
      Child_Cols.Append (0);
      Child_Cols.Append (1);
      Parent_Cols.Append (0);
      Parent_Cols.Append (1);
      FK :=
        Database.Foreign_Keys.Create
          ("fk_child_parent", 2, 1, Child_Cols, Parent_Cols);
      Database.Rows.Append (Parent_Row, Database.Values.From_Integer (7));
      Database.Rows.Append (Parent_Row, Database.Values.From_Integer (8));
      Parent_Rows.Append (Parent_Row);
      Database.Rows.Append (Child_Row, Database.Values.From_Integer (7));
      Database.Rows.Append (Child_Row, Database.Values.From_Integer (8));
      Res := Database.Foreign_Keys.Validate_Definition (FK, Child, Parent);
      Assert (Database.Status.Is_Ok (Res), "foreign key definition invalid");
      Res :=
        Database.Foreign_Keys.Validate_Insert_Or_Update
          (FK, Child, Parent, Child_Row, Parent_Rows);
      Assert
        (Database.Status.Is_Ok (Res),
         "matching composite foreign key was rejected");
      Database.Rows.Replace (Child_Row, 1, Database.Values.Null_Value);
      Assert
        (Database.Foreign_Keys.Referencing_Key_Is_Null (FK, Child, Child_Row),
         "partial null foreign key should be exempt");
   end Foreign_Key_Null_And_Match_Semantics;

   procedure Table_Check_Constraint_Is_Enforced_On_Insert
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB  : Database.Handle;
      Tx  : Database.Transactions.Transaction;
      S   : Database.Schema.Table_Schema := Person_Schema;
      C   : Database.Check_Constraints.Check_Constraint;
      Res : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("people_checks");
      Res := People.Register (DB, S);
      Assert (Database.Status.Is_Ok (Res), "register people table failed");
      C :=
        Database.Check_Constraints.Create
          ("age_non_negative",
           Database.Expressions.Binary
             (Database.Expressions.Greater_Or_Equal_Expr,
              Database.Expressions.Column (1),
              Database.Expressions.Literal
                (Database.Values.From_Integer (0))));
      Res := Database.Catalog.Add_Check_Constraint (DB, S.Table_Id, C);
      Assert (Database.Status.Is_Ok (Res), "add check constraint failed");
      Database.Transactions.Begin_Write (DB, Tx);
      Res := People.Insert (Tx, DB, S, (Id => 1, Age => -1, Double_Age => 0));
      Assert
        (Res.Code = Database.Status.Constraint_Error,
         "table insert did not enforce check constraint");
      Res := People.Insert (Tx, DB, S, (Id => 2, Age => 4, Double_Age => 0));
      Assert
        (Database.Status.Is_Ok (Res),
         "valid row rejected by check constraint");
      Res := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (Res), "commit failed");
      Database.Close (DB);
   end Table_Check_Constraint_Is_Enforced_On_Insert;

   procedure Deferred_Check_Constraint_Is_Enforced_On_Commit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB  : Database.Handle;
      Tx  : Database.Transactions.Transaction;
      S   : Database.Schema.Table_Schema := Person_Schema;
      C   : Database.Check_Constraints.Check_Constraint;
      Res : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("people_deferred_checks");
      Res := People.Register (DB, S);
      Assert (Database.Status.Is_Ok (Res), "register deferred table failed");
      C :=
        Database.Check_Constraints.Create
          ("age_non_negative_deferred",
           Database.Expressions.Binary
             (Database.Expressions.Greater_Or_Equal_Expr,
              Database.Expressions.Column (1),
              Database.Expressions.Literal
                (Database.Values.From_Integer (0))),
           Deferred => True);
      Res := Database.Catalog.Add_Check_Constraint (DB, S.Table_Id, C);
      Assert (Database.Status.Is_Ok (Res), "add deferred check failed");
      Database.Transactions.Begin_Write (DB, Tx);
      Res := People.Insert (Tx, DB, S, (Id => 1, Age => -5, Double_Age => 0));
      Assert (Database.Status.Is_Ok (Res), "deferred check fired before commit");
      Res := Database.Transactions.Commit (Tx);
      Assert
        (Res.Code = Database.Status.Constraint_Error,
         "deferred check was not enforced at commit");
      Res := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (Res), "rollback after deferred failure failed");
      Database.Close (DB);
   end Deferred_Check_Constraint_Is_Enforced_On_Commit;

   procedure Generated_Column_Is_Automatic_On_Insert
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Person_Schema;
      G       : Database.Generated_Columns.Generated_Column;
      Res     : Database.Status.Result;
      Out_Row : Person_Row;
   begin
      Database.Open_In_Memory (DB);
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("people_generated");
      Res := People.Register (DB, S);
      Assert (Database.Status.Is_Ok (Res), "register generated table failed");
      G :=
        Database.Generated_Columns.Create
          (2,
           "double_age",
           Database.Expressions.Binary
             (Database.Expressions.Multiply_Expr,
              Database.Expressions.Column (1),
              Database.Expressions.Literal
                (Database.Values.From_Integer (2))));
      Res := Database.Catalog.Add_Generated_Column (DB, S.Table_Id, G);
      Assert (Database.Status.Is_Ok (Res), "add generated column failed");
      Database.Transactions.Begin_Write (DB, Tx);
      Res := People.Insert (Tx, DB, S, (Id => 1, Age => 21, Double_Age => 0));
      Assert
        (Database.Status.Is_Ok (Res), "insert with generated column failed");
      Res := People.Find (Tx, DB, S, 1, Out_Row);
      Assert (Database.Status.Is_Ok (Res), "find generated row failed");
      Assert
        (Out_Row.Double_Age = 42,
         "generated column was not recomputed on insert");
      Res := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (Res), "commit failed");
      Database.Close (DB);
   end Generated_Column_Is_Automatic_On_Insert;

   procedure Foreign_Key_Is_Enforced_By_Table_Insert
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB                      : Database.Handle;
      Tx                      : Database.Transactions.Transaction;
      Parent_S, Child_S       : Database.Schema.Table_Schema;
      Child_Cols, Parent_Cols : Database.Foreign_Keys.Column_Id_Vectors.Vector;
      FK                      : Database.Foreign_Keys.Foreign_Key_Definition;
      Res                     : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Parent_S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("parents");
      Database.Schema.Add_Column
        (Parent_S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (Parent_S, "age", Database.Types.Integer_Value, False, False);
      Database.Schema.Add_Column
        (Parent_S, "double_age", Database.Types.Integer_Value, False, False);
      Child_S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("children");
      Database.Schema.Add_Column
        (Child_S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (Child_S, "parent_id", Database.Types.Integer_Value, False, False);
      Res := People.Register (DB, Parent_S);
      Assert (Database.Status.Is_Ok (Res), "register parent failed");
      Res := Children.Register (DB, Child_S);
      Assert (Database.Status.Is_Ok (Res), "register child failed");
      Child_Cols.Append (1);
      Parent_Cols.Append (0);
      FK :=
        Database.Foreign_Keys.Create
          ("fk_children_parent",
           Child_S.Table_Id,
           Parent_S.Table_Id,
           Child_Cols,
           Parent_Cols);
      Res := Database.Catalog.Add_Foreign_Key (DB, FK);
      Assert (Database.Status.Is_Ok (Res), "add foreign key failed");
      Database.Transactions.Begin_Write (DB, Tx);
      Res := Children.Insert (Tx, DB, Child_S, (Id => 1, Parent_Id => 999));
      Assert
        (Res.Code = Database.Status.Constraint_Error,
         "invalid foreign key insert succeeded");
      Res :=
        People.Insert (Tx, DB, Parent_S, (Id => 7, Age => 1, Double_Age => 2));
      Assert (Database.Status.Is_Ok (Res), "parent insert failed");
      Res := Children.Insert (Tx, DB, Child_S, (Id => 2, Parent_Id => 7));
      Assert (Database.Status.Is_Ok (Res), "valid foreign key insert failed");
      Res := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (Res), "commit failed");
      Database.Close (DB);
   end Foreign_Key_Is_Enforced_By_Table_Insert;

   procedure Relational_Metadata_Survives_Reopen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB                      : Database.Handle;
      Tx                      : Database.Transactions.Transaction;
      S, Reopened             : Database.Schema.Table_Schema := Person_Schema;
      Child_Cols, Parent_Cols : Database.Foreign_Keys.Column_Id_Vectors.Vector;
      FK                      : Database.Foreign_Keys.Foreign_Key_Definition;
      C                       : Database.Check_Constraints.Check_Constraint;
      G                       : Database.Generated_Columns.Generated_Column;
      V                       : Database.Views.View_Definition;
      MV                      :
        Database.Materialized_Views.Materialized_View_Definition;
      Out_Row                 : Person_Row;
      Res                     : Database.Status.Result;
      Path                    : constant Wide_Wide_String :=
        "relational_metadata.database";
   begin
      if Ada.Directories.Exists ("relational_metadata.database") then
         Ada.Directories.Delete_File ("relational_metadata.database");
      end if;

      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create relational metadata db failed");
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("relational_people");
      Res := People.Register (DB, S);
      Assert (Database.Status.Is_Ok (Res), "register relational table failed");

      Child_Cols.Append (1);
      Parent_Cols.Append (0);
      FK :=
        Database.Foreign_Keys.Create
          ("fk_self_age_id", S.Table_Id, S.Table_Id, Child_Cols, Parent_Cols);
      Res := Database.Catalog.Add_Foreign_Key (DB, FK);
      Assert
        (Database.Status.Is_Ok (Res), "persistent foreign key add failed");

      C :=
        Database.Check_Constraints.Create
          ("age_non_negative",
           Database.Expressions.Binary
             (Database.Expressions.Greater_Or_Equal_Expr,
              Database.Expressions.Column (1),
              Database.Expressions.Literal
                (Database.Values.From_Integer (0))));
      Res := Database.Catalog.Add_Check_Constraint (DB, S.Table_Id, C);
      Assert (Database.Status.Is_Ok (Res), "persistent check add failed");

      G :=
        Database.Generated_Columns.Create
          (2,
           "double_age",
           Database.Expressions.Binary
             (Database.Expressions.Multiply_Expr,
              Database.Expressions.Column (1),
              Database.Expressions.Literal
                (Database.Values.From_Integer (2))));
      Res := Database.Catalog.Add_Generated_Column (DB, S.Table_Id, G);
      Assert
        (Database.Status.Is_Ok (Res),
         "persistent generated column add failed");

      V := Database.Views.Create ("v_relational_people", Database.Queries.Empty);
      Res := Database.Catalog.Add_View (DB, V);
      Assert (Database.Status.Is_Ok (Res), "persistent view add failed");
      MV :=
        Database.Materialized_Views.Create
          ("mv_relational_people", Database.Queries.Empty, S.Table_Id);
      Res := Database.Catalog.Add_Materialized_View (DB, MV);
      Assert
        (Database.Status.Is_Ok (Res),
         "persistent materialized view add failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "reopen relational metadata db failed");
      Res := Database.Catalog.Find_By_Name ("relational_people", Reopened);
      Assert
        (Database.Status.Is_Ok (Res), "relational table missing after reopen");
      Assert
        (Natural
           (Database.Catalog.Foreign_Keys_For_Referencing_Table
              (Reopened.Table_Id)
              .Length)
         = 1,
         "foreign key metadata not durable");
      Assert
        (Natural
           (Database.Catalog.Check_Constraints_For_Table (Reopened.Table_Id)
              .Length)
         = 1,
         "check metadata not durable");
      Assert
        (Natural
           (Database.Catalog.Generated_Columns_For_Table (Reopened.Table_Id)
              .Length)
         = 1,
         "generated metadata not durable");
      Res := Database.Catalog.Find_View ("v_relational_people", V);
      Assert (Database.Status.Is_Ok (Res), "view metadata not durable");
      Res := Database.Catalog.Find_Materialized_View ("mv_relational_people", MV);
      Assert
        (Database.Status.Is_Ok (Res),
         "materialized view metadata not durable");

      Database.Transactions.Begin_Write (DB, Tx);
      Res :=
        People.Insert
          (Tx, DB, Reopened, (Id => 1, Age => 21, Double_Age => 0));
      Assert
        (Database.Status.Is_Ok (Res),
         "insert with reopened generated/check metadata failed");
      Res := People.Find (Tx, DB, Reopened, 1, Out_Row);
      Assert
        (Database.Status.Is_Ok (Res), "find reopened generated row failed");
      Assert
        (Out_Row.Double_Age = 42,
         "reopened generated metadata produced wrong value");
      Res :=
        People.Insert
          (Tx, DB, Reopened, (Id => 2, Age => -1, Double_Age => 0));
      Assert
        (Res.Code = Database.Status.Constraint_Error,
         "reopened check metadata did not reject row");
      Res := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (Res), "relational metadata commit failed");
      Database.Close (DB);

      if Ada.Directories.Exists ("relational_metadata.database") then
         Ada.Directories.Delete_File ("relational_metadata.database");
      end if;
   end Relational_Metadata_Survives_Reopen;

   procedure Updatable_View_Row_Operations_Persist
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Rows     : Database.Queries.Row_Vectors.Vector;
      Rw       : Database.Rows.Row;
      Q        : Database.Queries.Query;
      V        : Database.Views.View_Definition;
      Expanded : Database.Queries.Query;
      Res      : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Rows.Append (Rw, Database.Values.From_Integer (1));
      Database.Rows.Append (Rw, Database.Values.From_Text ("one"));
      Rows.Append (Rw);
      Q := Database.Queries.From_Rows (Rows);
      V := Database.Views.Create ("updatable_people_view", Q);
      Res := Database.Catalog.Add_View (DB, V);
      Assert (Database.Status.Is_Ok (Res), "add updatable view failed");
      Assert (Database.Views.Is_Updatable (V), "view should be updatable");

      Rw.Values.Clear;
      Database.Rows.Append (Rw, Database.Values.From_Integer (2));
      Database.Rows.Append (Rw, Database.Values.From_Text ("two"));
      Res := Database.Views.Insert_Row (V, Rw);
      Assert (Database.Status.Is_Ok (Res), "view insert failed");

      Rw.Values.Clear;
      Database.Rows.Append (Rw, Database.Values.From_Integer (2));
      Database.Rows.Append (Rw, Database.Values.From_Text ("deux"));
      Res := Database.Views.Update_Row (V, 0, Rw);
      Assert (Database.Status.Is_Ok (Res), "view update failed");

      Res := Database.Views.Delete_Row (V, 0, Database.Values.From_Integer (1));
      Assert (Database.Status.Is_Ok (Res), "view delete failed");
      Res := Database.Catalog.Update_View (DB, V);
      Assert (Database.Status.Is_Ok (Res), "catalog view update failed");
      Res := Database.Catalog.Find_View ("updatable_people_view", V);
      Assert (Database.Status.Is_Ok (Res), "updated view missing");
      Res := Database.Views.Expand (V, Expanded);
      Assert (Database.Status.Is_Ok (Res), "updated view expand failed");
      Assert (Database.Queries.Row_Count (Expanded) = 1, "view row count wrong");
      Rows := Database.Queries.Rows (Expanded);
      Assert
        (Database.Rows.Get (Rows.Element (0), 0).Int = 2,
         "view retained wrong key");
      Assert
        (Database.Rows.Get (Rows.Element (0), 1).Text =
         Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("deux"),
         "view update did not persist");
      Database.Close (DB);
   end Updatable_View_Row_Operations_Persist;

   procedure Materialized_View_Incremental_Refresh_Merges_Rows
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      MV      : Database.Materialized_Views.Materialized_View_Definition;
      Current : Database.Materialized_Views.Row_Vectors.Vector;
      Inserted, Updated, Deleted, Result : Database.Materialized_Views.Row_Vectors.Vector;
      Rw      : Database.Rows.Row;
      Res     : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      MV :=
        Database.Materialized_Views.Create
          ("mv_incremental", Database.Queries.Empty, Storage_Table => 1);
      Database.Rows.Append (Rw, Database.Values.From_Integer (1));
      Database.Rows.Append (Rw, Database.Values.From_Text ("one"));
      Current.Append (Rw);
      Rw.Values.Clear;
      Database.Rows.Append (Rw, Database.Values.From_Integer (2));
      Database.Rows.Append (Rw, Database.Values.From_Text ("two"));
      Current.Append (Rw);
      Rw.Values.Clear;
      Database.Rows.Append (Rw, Database.Values.From_Integer (2));
      Database.Rows.Append (Rw, Database.Values.From_Text ("deux"));
      Updated.Append (Rw);
      Rw.Values.Clear;
      Database.Rows.Append (Rw, Database.Values.From_Integer (3));
      Database.Rows.Append (Rw, Database.Values.From_Text ("three"));
      Inserted.Append (Rw);
      Rw.Values.Clear;
      Database.Rows.Append (Rw, Database.Values.From_Integer (1));
      Deleted.Append (Rw);

      Database.Transactions.Begin_Write (DB, Tx);
      Res :=
        Database.Materialized_Views.Refresh_Incremental
          (Tx, MV, Current, Inserted, Updated, Deleted, 0, Result);
      Assert (Database.Status.Is_Ok (Res), "incremental refresh failed");
      Assert (Natural (Result.Length) = 2, "incremental result row count wrong");
      Assert (MV.Last_Refresh_Commit = Database.Commit_Version (DB), "refresh version not recorded");
      Res := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (Res), "rollback refresh tx failed");
      Database.Close (DB);
   end Materialized_View_Incremental_Refresh_Merges_Rows;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Check_Constraint_Rejects_Invalid_Row'Access,
         "check constraints reject invalid rows");
      Register_Routine
        (T,
         Generated_Column_Recomputes_Stored_Value'Access,
         "stored generated columns recompute and validate");
      Register_Routine
        (T,
         Composite_Key_Comparison_Is_Lexicographic'Access,
         "composite keys compare lexicographically");
      Register_Routine
        (T,
         Foreign_Key_Null_And_Match_Semantics'Access,
         "foreign key composite matching and null semantics");
      Register_Routine
        (T,
         Table_Check_Constraint_Is_Enforced_On_Insert'Access,
         "table insert enforces registered check constraints");
      Register_Routine
        (T,
         Deferred_Check_Constraint_Is_Enforced_On_Commit'Access,
         "deferred check constraints are enforced on commit");
      Register_Routine
        (T,
         Generated_Column_Is_Automatic_On_Insert'Access,
         "table insert recomputes registered generated columns");
      Register_Routine
        (T,
         Foreign_Key_Is_Enforced_By_Table_Insert'Access,
         "table insert enforces registered foreign keys");
      Register_Routine
        (T,
         Relational_Metadata_Survives_Reopen'Access,
         "relational metadata survives persistent reopen");
      Register_Routine
        (T,
         Updatable_View_Row_Operations_Persist'Access,
         "updatable view row operations persist in catalog");
      Register_Routine
        (T,
         Materialized_View_Incremental_Refresh_Merges_Rows'Access,
         "incremental materialized view refresh merges row deltas");
   end Register_Tests;
end Relational_Features_Tests;
