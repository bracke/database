with AUnit.Assertions;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Execution_Plans;
with Database.Indexes;
with Database.Optimizer;
with Database.Ordering;
with Database.Plans;
with Database.Predicates;
with Database.Status;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Database.Aggregates;

package body Optimizer_Tests is
   use AUnit.Assertions;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("query optimizer");
   end Name;

   function User_Table return Database.Plans.Logical_Plan is
   begin
      return
        Database.Plans.Table
          ("users", 1, (Row_Count => 1000, Page_Count => 20));
   end User_Table;

   function Primary_Id_Index return Database.Indexes.Index_Metadata is
      use Ada.Strings.Wide_Wide_Unbounded;
   begin
      return
        (Id        => 1,
         Table_Id  => 1,
         Name      => To_Unbounded_Wide_Wide_String ("users_pk"),
         Kind      => Database.Indexes.Primary_Key_Index,
         Root_Page => 1,
         Unique    => True,
         Column_Id => 0,
         Key_Kind  => Database.Types.Integer_Value, others => <>);
   end Primary_Id_Index;

   function Age_Index return Database.Indexes.Index_Metadata is
      use Ada.Strings.Wide_Wide_Unbounded;
   begin
      return
        (Id        => 2,
         Table_Id  => 1,
         Name      => To_Unbounded_Wide_Wide_String ("users_age"),
         Kind      => Database.Indexes.Secondary_Index,
         Root_Page => 2,
         Unique    => False,
         Column_Id => 2,
         Key_Kind  => Database.Types.Integer_Value,
         others => <>);
   end Age_Index;

   procedure Logical_Plan_Builders
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cols  : Database.Plans.Column_Vectors.Vector;
      P     : Database.Plans.Logical_Plan;
      R     : Database.Plans.Column_Vectors.Vector;
      Aggs  : Database.Aggregates.Aggregate_Vectors.Vector;
      Right : Database.Plans.Logical_Plan;
   begin
      Cols.Append (1);
      P :=
        Database.Plans.Limit
          (Database.Plans.Order_By
             (Database.Plans.Project
                (Database.Plans.Where
                   (User_Table,
                    Database.Predicates.Column_Equals
                      (0, Database.Values.From_Integer (7))),
                 Cols),
              1),
           10);
      Assert
        (Database.Plans.Step_Count (P) = 5, "logical plan step count wrong");
      Aggs.Append (Database.Aggregates.Count);
      Aggs.Append (Database.Aggregates.Max (2));
      P := Database.Plans.Group_By (P, Cols, Aggs);
      Right :=
        Database.Plans.Table
          ("departments", 2, (Row_Count => 10, Page_Count => 1));
      P := Database.Plans.Inner_Join (P, Right, 1, 0);
      R := Database.Plans.Referenced_Columns (P);
      Assert (Natural (R.Length) >= 3, "referenced columns not reported");
      Assert
        (Database.Plans.Step_Count (P) >= 8,
         "group/join logical builders missing steps");
   end Logical_Plan_Builders;

   procedure Primary_Key_Equality_Uses_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ix : Database.Indexes.Index_Metadata_Vectors.Vector;
      P  : Database.Plans.Logical_Plan;
      Tx : Database.Transactions.Transaction;
      R  : Database.Execution_Plans.Physical_Plan_Result;
   begin
      Ix.Append (Primary_Id_Index);
      P := Database.Plans.With_Indexes (User_Table, Ix);
      P :=
        Database.Plans.Where
          (P,
           Database.Predicates.Column_Equals
             (0, Database.Values.From_Integer (42)));
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Status.Is_Ok (R.Status), "optimizer rejected valid plan");
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Index_Lookup),
         "primary key equality did not use index lookup");
      Assert
        (not Database.Execution_Plans.Contains
               (R.Plan, Database.Execution_Plans.Filter_Node),
         "index equality kept redundant filter");
   end Primary_Key_Equality_Uses_Index;

   procedure Nonunique_Secondary_Equality_Uses_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ix : Database.Indexes.Index_Metadata_Vectors.Vector;
      P  : Database.Plans.Logical_Plan;
      Tx : Database.Transactions.Transaction;
      R  : Database.Execution_Plans.Physical_Plan_Result;
   begin
      Ix.Append (Age_Index);
      P := Database.Plans.With_Indexes (User_Table, Ix);
      P :=
        Database.Plans.Where
          (P,
           Database.Predicates.Column_Equals
             (2, Database.Values.From_Integer (30)));
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Index_Lookup),
         "secondary equality did not use index lookup");
      Assert
        (Database.Execution_Plans.Step (R.Plan, 0).Estimated_Rows > 1,
         "nonunique index estimate should allow duplicates");
   end Nonunique_Secondary_Equality_Uses_Index;

   procedure Unindexed_Predicate_Uses_Heap_Scan
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P  : Database.Plans.Logical_Plan;
      Tx : Database.Transactions.Transaction;
      R  : Database.Execution_Plans.Physical_Plan_Result;
   begin
      P :=
        Database.Plans.Where
          (User_Table,
           Database.Predicates.Column_Equals
             (2, Database.Values.From_Integer (30)));
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Heap_Scan),
         "unindexed predicate did not use heap scan");
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Filter_Node),
         "unindexed predicate lost filter node");
   end Unindexed_Predicate_Uses_Heap_Scan;

   procedure Range_Predicate_Uses_Index_Range_Scan
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ix : Database.Indexes.Index_Metadata_Vectors.Vector;
      P  : Database.Plans.Logical_Plan;
      Tx : Database.Transactions.Transaction;
      R  : Database.Execution_Plans.Physical_Plan_Result;
   begin
      Ix.Append (Age_Index);
      P := Database.Plans.With_Indexes (User_Table, Ix);
      P :=
        Database.Plans.Where
          (P,
           Database.Predicates.Column_Greater_Or_Equal
             (2, Database.Values.From_Integer (18)));
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Index_Range_Scan),
         "range predicate did not use index range scan");
   end Range_Predicate_Uses_Index_Range_Scan;

   procedure Sort_Elimination_For_Ascending_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ix : Database.Indexes.Index_Metadata_Vectors.Vector;
      P  : Database.Plans.Logical_Plan;
      Tx : Database.Transactions.Transaction;
      R  : Database.Execution_Plans.Physical_Plan_Result;
   begin
      Ix.Append (Age_Index);
      P := Database.Plans.With_Indexes (User_Table, Ix);
      P := Database.Plans.Order_By (P, 2, Database.Ordering.Ascending);
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (not Database.Execution_Plans.Contains
               (R.Plan, Database.Execution_Plans.Sort_Node),
         "ascending indexed order was sorted unnecessarily");
      P :=
        Database.Plans.Order_By
          (Database.Plans.With_Indexes (User_Table, Ix),
           2,
           Database.Ordering.Descending);
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Sort_Node),
         "descending order should sort without reverse scan support");
   end Sort_Elimination_For_Ascending_Index;

   procedure Force_Heap_Scan_Control
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ix       : Database.Indexes.Index_Metadata_Vectors.Vector;
      P        : Database.Plans.Logical_Plan;
      Tx       : Database.Transactions.Transaction;
      R        : Database.Execution_Plans.Physical_Plan_Result;
      Settings : Database.Optimizer.Optimizer_Settings :=
        Database.Optimizer.Default_Settings;
   begin
      Settings.Force_Heap_Scan := True;
      Ix.Append (Primary_Id_Index);
      P := Database.Plans.With_Indexes (User_Table, Ix);
      P :=
        Database.Plans.Where
          (P,
           Database.Predicates.Column_Equals
             (0, Database.Values.From_Integer (1)));
      R := Database.Optimizer.Optimize (Tx, P, Settings);
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Heap_Scan),
         "force heap scan ignored");
      Assert
        (not Database.Execution_Plans.Contains
               (R.Plan, Database.Execution_Plans.Index_Lookup),
         "force heap scan still used index");
   end Force_Heap_Scan_Control;

   procedure Explain_Is_Stable (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      P  : constant Database.Plans.Logical_Plan :=
        Database.Plans.Where
          (User_Table,
           Database.Predicates.Column_Equals
             (9, Database.Values.From_Integer (1)));
      Tx : Database.Transactions.Transaction;
      R  : constant Database.Execution_Plans.Physical_Plan_Result :=
        Database.Optimizer.Optimize (Tx, P);
      E  : constant Wide_Wide_String :=
        Database.Execution_Plans.Explain (R.Plan);
   begin
      Assert (E'Length > 0, "explain returned empty string");
   end Explain_Is_Stable;

   procedure Empty_Explain_Is_Safe
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P : Database.Execution_Plans.Physical_Plan;
      E : constant Wide_Wide_String := Database.Execution_Plans.Explain (P);
   begin
      Assert (E = "<empty physical plan>", "empty explain should be stable");
   end Empty_Explain_Is_Safe;

   procedure Indexed_Join_Chooses_Index_Nested_Loop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ix    : Database.Indexes.Index_Metadata_Vectors.Vector;
      Left  : Database.Plans.Logical_Plan;
      Right : Database.Plans.Logical_Plan;
      P     : Database.Plans.Logical_Plan;
      Tx    : Database.Transactions.Transaction;
      R     : Database.Execution_Plans.Physical_Plan_Result;
   begin
      Ix.Append (Age_Index);
      Left := Database.Plans.With_Indexes (User_Table, Ix);
      Right :=
        Database.Plans.Table ("right", 2, (Row_Count => 100, Page_Count => 4));
      P := Database.Plans.Inner_Join (Left, Right, 0, 2);
      R := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Execution_Plans.Contains
           (R.Plan, Database.Execution_Plans.Index_Nested_Loop_Join),
         "indexed join did not choose index nested loop");
   end Indexed_Join_Chooses_Index_Nested_Loop;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Logical_Plan_Builders'Access, "logical plan builders");
      Register_Routine
        (T,
         Primary_Key_Equality_Uses_Index'Access,
         "primary key equality uses index");
      Register_Routine
        (T,
         Nonunique_Secondary_Equality_Uses_Index'Access,
         "nonunique secondary equality uses index");
      Register_Routine
        (T,
         Unindexed_Predicate_Uses_Heap_Scan'Access,
         "unindexed predicate uses heap scan");
      Register_Routine
        (T,
         Range_Predicate_Uses_Index_Range_Scan'Access,
         "range predicate uses index range scan");
      Register_Routine
        (T,
         Sort_Elimination_For_Ascending_Index'Access,
         "sort elimination for indexed ascending order");
      Register_Routine
        (T, Force_Heap_Scan_Control'Access, "force heap scan control");
      Register_Routine (T, Explain_Is_Stable'Access, "plan explain is stable");
      Register_Routine
        (T, Empty_Explain_Is_Safe'Access, "empty explain is safe");
      Register_Routine
        (T,
         Indexed_Join_Chooses_Index_Nested_Loop'Access,
         "indexed join chooses index nested loop");
   end Register_Tests;
end Optimizer_Tests;
