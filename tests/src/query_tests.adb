with AUnit.Assertions;

with Ada.Directories;
with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Aggregates;
with Database.Catalog;
with Database.Joins;
with Database.Ordering;
with Database.Predicates;
with Database.Queries;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body Query_Tests is
   use AUnit.Assertions;
   use type Database.Types.Value_Kind;
   use type Database.Status.Status_Code;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("query composition");
   end Name;

   type Stored_User is record
      Id   : Integer;
      Name : Wide_Wide_String (1 .. 16);
      Age  : Integer;
   end record;

   function To_Row (U : Stored_User) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (U.Id));
      Database.Rows.Append (R, Database.Values.From_Text (U.Name));
      Database.Rows.Append (R, Database.Values.From_Integer (U.Age));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Stored_User is
      use Ada.Strings.Wide_Wide_Unbounded;
      S : constant Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      U : Stored_User :=
        (Id   => Database.Rows.Get (R, 0).Int,
         Name => (others => ' '),
         Age  => Database.Rows.Get (R, 2).Int);
   begin
      for I in 1 .. Integer'Min (16, S'Length) loop
         U.Name (I) := S (S'First + I - 1);
      end loop;
      return U;
   end From_Row;

   function Key_Of (U : Stored_User) return Integer
   is (U.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));
   package Stored_Users is new
     Database.Tables.Typed
       (Stored_User,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   function User_Row
     (Id, Age : Integer; Name : Wide_Wide_String) return Database.Rows.Row
   is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (Id));
      Database.Rows.Append (R, Database.Values.From_Text (Name));
      Database.Rows.Append (R, Database.Values.From_Integer (Age));
      return R;
   end User_Row;

   function User_Row_Null_Age
     (Id : Integer; Name : Wide_Wide_String) return Database.Rows.Row
   is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (Id));
      Database.Rows.Append (R, Database.Values.From_Text (Name));
      Database.Rows.Append (R, Database.Values.Null_Value);
      return R;
   end User_Row_Null_Age;

   function Users return Database.Queries.Query is
      Q : Database.Queries.Query := Database.Queries.Empty;
   begin
      Database.Queries.Append (Q, User_Row (1, 42, "Bent"));
      Database.Queries.Append (Q, User_Row (2, 17, "Aage"));
      Database.Queries.Append (Q, User_Row (3, 42, "Clara"));
      Database.Queries.Append (Q, User_Row_Null_Age (4, "NullAge"));
      return Q;
   end Users;

   function Text_Group_Users return Database.Queries.Query is
      Q : Database.Queries.Query := Database.Queries.Empty;
   begin
      Database.Queries.Append (Q, User_Row (1, 10, "blue"));
      Database.Queries.Append (Q, User_Row (2, 20, "red"));
      Database.Queries.Append (Q, User_Row (3, 30, "blue"));
      return Q;
   end Text_Group_Users;

   procedure Projection_Single_Column
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cols : Database.Queries.Column_Vectors.Vector;
      Q    : Database.Queries.Query;
      C    : Database.Queries.Cursor;
      S    : Database.Status.Result;
      R    : Database.Rows.Row;
   begin
      Cols.Append (1);
      S := Database.Queries.Try_Project (Users, Cols, Q);
      Assert (Database.Status.Is_Ok (S), "single-column projection failed");
      Assert
        (Database.Queries.Row_Count (Q) = 4,
         "single-column projection changed row count");
      Database.Queries.Execute (Q, C);
      R := Database.Queries.Element (C);
      Assert
        (Database.Rows.Column_Count (R) = 1,
         "single-column projection column count wrong");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (R, 0), Database.Values.From_Text ("Bent")),
         "single-column projection wrong");
   end Projection_Single_Column;

   procedure Projection_Multi_Column_Order
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cols : Database.Queries.Column_Vectors.Vector;
      Q    : Database.Queries.Query;
      S    : Database.Status.Result;
      C    : Database.Queries.Cursor;
   begin
      Cols.Append (1);
      Cols.Append (0);
      S := Database.Queries.Try_Project (Users, Cols, Q);
      Assert (Database.Status.Is_Ok (S), "multi-column projection failed");
      Database.Queries.Execute (Q, C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 1).Int = 1,
         "first projected row wrong");
      Database.Queries.Next (C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 1).Int = 2,
         "projection did not preserve row order");
   end Projection_Multi_Column_Order;

   procedure Projection_Rejects_Invalid_Column
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cols : Database.Queries.Column_Vectors.Vector;
      Q    : Database.Queries.Query;
      S    : Database.Status.Result;
   begin
      Cols.Append (99);
      S := Database.Queries.Try_Project (Users, Cols, Q);
      Assert
        (S.Code = Database.Status.Invalid_Argument,
         "invalid projection column accepted");
      Assert
        (Database.Queries.Row_Count (Q) = 0,
         "failed projection produced rows");
   end Projection_Rejects_Invalid_Column;

   procedure Ordering_Integer_Ascending
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Q : Database.Queries.Query;
      C : Database.Queries.Cursor;
   begin
      Q := Database.Queries.Order_By (Users, 2, Database.Ordering.Ascending);
      Database.Queries.Execute (Q, C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 2).Int = 17,
         "ascending integer sort failed");
   end Ordering_Integer_Ascending;

   procedure Ordering_Integer_Descending_Stable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Q : Database.Queries.Query;
      C : Database.Queries.Cursor;
   begin
      Q := Database.Queries.Order_By (Users, 2, Database.Ordering.Descending);
      Database.Queries.Execute (Q, C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 0).Int = 1,
         "descending first equal row not stable");
      Database.Queries.Next (C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 0).Int = 3,
         "descending second equal row not stable");
   end Ordering_Integer_Descending_Stable;

   procedure Ordering_Text_And_Nulls_Last
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Q : Database.Queries.Query;
      C : Database.Queries.Cursor;
   begin
      Q := Database.Queries.Order_By (Users, 1, Database.Ordering.Ascending);
      Database.Queries.Execute (Q, C);
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Database.Queries.Element (C), 1),
            Database.Values.From_Text ("Aage")),
         "text sort failed");
      Q := Database.Queries.Order_By (Users, 2, Database.Ordering.Ascending);
      Database.Queries.Execute (Q, C);
      while Database.Queries.Has_Element (C) loop
         if Database.Rows.Get (Database.Queries.Element (C), 0).Int = 4 then
            Assert
              (Database.Rows.Get (Database.Queries.Element (C), 2).Kind
               = Database.Types.Null_Value,
               "expected null age");
            Database.Queries.Next (C);
            Assert
              (not Database.Queries.Has_Element (C),
               "NULL was not sorted last");
            exit;
         end if;
         Database.Queries.Next (C);
      end loop;
   end Ordering_Text_And_Nulls_Last;

   procedure Limit_Offset_Cases (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Q : Database.Queries.Query;
      C : Database.Queries.Cursor;
   begin
      Assert
        (Database.Queries.Row_Count (Database.Queries.Limit (Users, 0)) = 0,
         "limit 0 not empty");
      Assert
        (Database.Queries.Row_Count (Database.Queries.Limit (Users, 99)) = 4,
         "oversized limit wrong");
      Q := Database.Queries.Offset (Users, 2);
      Assert (Database.Queries.Row_Count (Q) = 2, "offset count wrong");
      Database.Queries.Execute (Q, C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 0).Int = 3,
         "offset first row wrong");
      Q := Database.Queries.Slice (Users, 1, 2);
      Assert (Database.Queries.Row_Count (Q) = 2, "limit+offset count wrong");
      Database.Queries.Execute (Q, C);
      Assert
        (Database.Rows.Get (Database.Queries.Element (C), 0).Int = 2,
         "limit+offset first row wrong");
      Assert
        (Database.Queries.Row_Count (Database.Queries.Offset (Users, 99)) = 0,
         "offset beyond size not empty");
   end Limit_Offset_Cases;

   procedure Aggregates_Cases (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Aggs : Database.Aggregates.Aggregate_Vectors.Vector;
      R    : Database.Rows.Row;
      S    : Database.Status.Result;
      Q    : Database.Queries.Query;
   begin
      Aggs.Append (Database.Aggregates.Count);
      Aggs.Append (Database.Aggregates.Count (2));
      Aggs.Append (Database.Aggregates.Min (2));
      Aggs.Append (Database.Aggregates.Max (2));
      Aggs.Append (Database.Aggregates.Sum (2));
      Aggs.Append (Database.Aggregates.Avg (2));
      S := Database.Queries.Aggregate (Users, Aggs, R);
      Assert (Database.Status.Is_Ok (S), "aggregate failed");
      Assert (Database.Rows.Get (R, 0).Int = 4, "count all wrong");
      Assert
        (Database.Rows.Get (R, 1).Int = 3, "count column should ignore null");
      Assert (Database.Rows.Get (R, 2).Int = 17, "min wrong");
      Assert (Database.Rows.Get (R, 3).Int = 42, "max wrong");
      Assert (Integer (Database.Rows.Get (R, 4).Flt) = 101, "sum wrong");
      Assert (Integer (Database.Rows.Get (R, 5).Flt) = 33, "avg wrong");

      Q :=
        Database.Queries.Filter
          (Users,
           Database.Predicates.Column_Equals
             (2, Database.Values.From_Integer (42)));
      Aggs.Clear;
      Aggs.Append (Database.Aggregates.Count);
      S := Database.Queries.Aggregate (Q, Aggs, R);
      Assert
        (Database.Status.Is_Ok (S) and then Database.Rows.Get (R, 0).Int = 2,
         "count filtered rows wrong");

      Aggs.Clear;
      Aggs.Append (Database.Aggregates.Sum (1));
      S := Database.Queries.Aggregate (Users, Aggs, R);
      Assert
        (S.Code = Database.Status.Invalid_Argument,
         "invalid aggregate type accepted");
   end Aggregates_Cases;

   procedure Grouping_Cases (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Cols       : Database.Queries.Column_Vectors.Vector;
      Aggs       : Database.Aggregates.Aggregate_Vectors.Vector;
      G          : Database.Queries.Query;
      S          : Database.Status.Result;
      C          : Database.Queries.Cursor;
      Found_Blue : Boolean := False;
      Found_Null : Boolean := False;
   begin
      Cols.Append (2);
      Aggs.Append (Database.Aggregates.Count);
      S := Database.Queries.Group_By (Users, Cols, Aggs, G);
      Assert (Database.Status.Is_Ok (S), "group by integer failed");
      Assert
        (Database.Queries.Row_Count (G) = 3,
         "integer group count wrong including null group");
      Database.Queries.Execute (G, C);
      while Database.Queries.Has_Element (C) loop
         if Database.Rows.Get (Database.Queries.Element (C), 0).Kind
           = Database.Types.Null_Value
         then
            Found_Null := True;
            Assert
              (Database.Rows.Get (Database.Queries.Element (C), 1).Int = 1,
               "null group aggregate wrong");
         end if;
         Database.Queries.Next (C);
      end loop;
      Assert (Found_Null, "null group missing");

      Cols.Clear;
      Aggs.Clear;
      Cols.Append (1);
      Aggs.Append (Database.Aggregates.Count);
      S := Database.Queries.Group_By (Text_Group_Users, Cols, Aggs, G);
      Assert (Database.Status.Is_Ok (S), "group by text failed");
      Assert (Database.Queries.Row_Count (G) = 2, "text group count wrong");
      Database.Queries.Execute (G, C);
      while Database.Queries.Has_Element (C) loop
         if Database.Values.Equal
              (Database.Rows.Get (Database.Queries.Element (C), 0),
               Database.Values.From_Text ("blue"))
         then
            Found_Blue := True;
            Assert
              (Database.Rows.Get (Database.Queries.Element (C), 1).Int = 2,
               "aggregate per text group wrong");
         end if;
         Database.Queries.Next (C);
      end loop;
      Assert (Found_Blue, "blue group missing");
   end Grouping_Cases;

   procedure Join_Cases (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Orders : Database.Queries.Query := Database.Queries.Empty;
      Joined : Database.Queries.Query;
      S      : Database.Status.Result;
   begin
      Database.Queries.Append (Orders, User_Row (10, 1, "Book"));
      Database.Queries.Append (Orders, User_Row (11, 1, "Pen"));
      Database.Queries.Append (Orders, User_Row (12, 99, "NoMatch"));
      S :=
        Database.Joins.Try_Inner_Join
          (Users, Orders, Database.Joins.On_Equal (0, 2), Joined);
      Assert (Database.Status.Is_Ok (S), "inner join failed");
      Assert
        (Database.Queries.Row_Count (Joined) = 2,
         "multi-row inner join count wrong");
      Assert
        (Database.Rows.Column_Count
           (Database.Queries.Rows (Joined).Element (0))
         = 6,
         "joined row column count wrong");

      S :=
        Database.Joins.Try_Inner_Join
          (Users, Orders, Database.Joins.On_Equal (0, 0), Joined);
      Assert (Database.Status.Is_Ok (S), "no-match join failed unexpectedly");
      Assert
        (Database.Queries.Row_Count (Joined) = 0,
         "join with no matches produced rows");

      S :=
        Database.Joins.Try_Inner_Join
          (Users, Orders, Database.Joins.On_Equal (99, 0), Joined);
      Assert
        (S.Code = Database.Status.Invalid_Argument,
         "invalid join column accepted");
   end Join_Cases;

   procedure Join_With_Predicate_And_Aggregate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Orders   : Database.Queries.Query := Database.Queries.Empty;
      Joined   : Database.Queries.Query;
      Filtered : Database.Queries.Query;
      Aggs     : Database.Aggregates.Aggregate_Vectors.Vector;
      R        : Database.Rows.Row;
      S        : Database.Status.Result;
   begin
      Database.Queries.Append (Orders, User_Row (10, 1, "Book"));
      Database.Queries.Append (Orders, User_Row (11, 1, "Pen"));
      Database.Queries.Append (Orders, User_Row (12, 3, "Bag"));
      Joined :=
        Database.Joins.Inner_Join
          (Users, Orders, Database.Joins.On_Equal (0, 2));
      Filtered :=
        Database.Queries.Filter
          (Joined,
           Database.Predicates.Column_Equals
             (2, Database.Values.From_Integer (42)));
      Aggs.Append (Database.Aggregates.Count);
      S := Database.Queries.Aggregate (Filtered, Aggs, R);
      Assert (Database.Status.Is_Ok (S), "join+aggregate failed");
      Assert
        (Database.Rows.Get (R, 0).Int = 3, "join predicate aggregate wrong");
   end Join_With_Predicate_And_Aggregate;

   procedure Grouping_And_Ordering_Composition
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cols       : Database.Queries.Column_Vectors.Vector;
      Aggs       : Database.Aggregates.Aggregate_Vectors.Vector;
      G, Ordered : Database.Queries.Query;
      S          : Database.Status.Result;
      C          : Database.Queries.Cursor;
   begin
      Cols.Append (1);
      Aggs.Append (Database.Aggregates.Count);
      S := Database.Queries.Group_By (Text_Group_Users, Cols, Aggs, G);
      Assert (Database.Status.Is_Ok (S), "grouping before order failed");
      Ordered :=
        Database.Queries.Order_By (G, 0, Database.Ordering.Descending);
      Database.Queries.Execute (Ordered, C);
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Database.Queries.Element (C), 0),
            Database.Values.From_Text ("red")),
         "grouping+ordering result wrong");
   end Grouping_And_Ordering_Composition;

   procedure Cursor_Iteration_Correctness
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : Database.Queries.Cursor;
      Count : Natural := 0;
   begin
      Database.Queries.Execute (Users, C);
      while Database.Queries.Has_Element (C) loop
         Count := Count + 1;
         Database.Queries.Next (C);
      end loop;
      Assert (Count = 4, "cursor iteration count wrong");
      Assert
        (not Database.Queries.Has_Element (C),
         "cursor still has element after exhaustion");
   end Cursor_Iteration_Correctness;

   procedure Transaction_Scoped_Query_Execution
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;
      Q  : Database.Queries.Query;
   begin
      Database.Open_In_Memory (DB);
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      R := Stored_Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "query register failed");
      R :=
        Stored_Users.Scan_Query
          (Tx, DB, S, Database.Predicates.True_Predicate, Q);
      Assert
        (R.Code = Database.Status.Transaction_Error,
         "Scan_Query accepted inactive transaction");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Stored_Users.Insert
          (Tx, DB, S, (Id => 1, Name => "Bent            ", Age => 42));
      Assert (Database.Status.Is_Ok (R), "query insert failed");
      R :=
        Stored_Users.Scan_Query
          (Tx, DB, S, Database.Predicates.True_Predicate, Q);
      Assert
        (Database.Status.Is_Ok (R), "Scan_Query in active transaction failed");
      Assert
        (Database.Queries.Row_Count (Q) = 1, "Scan_Query row count wrong");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "query tx commit failed");
      Database.Close (DB);
   end Transaction_Scoped_Query_Execution;

   procedure Query_Rollback_And_Reopen_Visibility
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB   : Database.Handle;
      Tx   : Database.Transactions.Transaction;
      S    : Database.Schema.Table_Schema;
      R    : Database.Status.Result;
      Q    : Database.Queries.Query;
      Path : constant Wide_Wide_String := "query_visibility.database";
   begin
      if Ada.Directories.Exists ("query_visibility.database") then
         Ada.Directories.Delete_File ("query_visibility.database");
      end if;

      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "query DB create failed");
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      R := Stored_Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "visibility register failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Stored_Users.Insert
          (Tx, DB, S, (Id => 1, Name => "Committed       ", Age => 30));
      Assert (Database.Status.Is_Ok (R), "visibility baseline insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "visibility baseline commit failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Stored_Users.Insert
          (Tx, DB, S, (Id => 2, Name => "RolledBack      ", Age => 99));
      Assert (Database.Status.Is_Ok (R), "visibility rollback insert failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "visibility rollback failed");
      Database.Close (DB);

      Database.Open (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "visibility reopen failed");
      R := Database.Catalog.Find_By_Name ("users", S);
      Assert (Database.Status.Is_Ok (R), "visibility catalog restore failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Stored_Users.Scan_Query
          (Tx, DB, S, Database.Predicates.True_Predicate, Q);
      Assert
        (Database.Status.Is_Ok (R), "visibility scan after reopen failed");
      Assert
        (Database.Queries.Row_Count (Q) = 1,
         "rolled-back row visible after reopen");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "visibility final commit failed");
      Database.Close (DB);
      if Ada.Directories.Exists ("query_visibility.database") then
         Ada.Directories.Delete_File ("query_visibility.database");
      end if;
   end Query_Rollback_And_Reopen_Visibility;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Projection_Single_Column'Access, "projection single column");
      Register_Routine
        (T,
         Projection_Multi_Column_Order'Access,
         "projection multi column preserves order");
      Register_Routine
        (T,
         Projection_Rejects_Invalid_Column'Access,
         "projection rejects invalid column");
      Register_Routine
        (T, Ordering_Integer_Ascending'Access, "ordering integer ascending");
      Register_Routine
        (T,
         Ordering_Integer_Descending_Stable'Access,
         "ordering integer descending stable");
      Register_Routine
        (T,
         Ordering_Text_And_Nulls_Last'Access,
         "ordering text and nulls last");
      Register_Routine (T, Limit_Offset_Cases'Access, "limit offset cases");
      Register_Routine (T, Aggregates_Cases'Access, "aggregate cases");
      Register_Routine (T, Grouping_Cases'Access, "grouping cases");
      Register_Routine (T, Join_Cases'Access, "join cases");
      Register_Routine
        (T,
         Join_With_Predicate_And_Aggregate'Access,
         "join predicate aggregate composition");
      Register_Routine
        (T,
         Grouping_And_Ordering_Composition'Access,
         "grouping ordering composition");
      Register_Routine
        (T,
         Cursor_Iteration_Correctness'Access,
         "cursor iteration correctness");
      Register_Routine
        (T,
         Transaction_Scoped_Query_Execution'Access,
         "transaction scoped query execution");
      Register_Routine
        (T,
         Query_Rollback_And_Reopen_Visibility'Access,
         "query rollback and reopen visibility");
   end Register_Tests;
end Query_Tests;
