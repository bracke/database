with AUnit.Assertions;

with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Directories;
with Database; use Database;
with Database.Full_Text;
with Database.Full_Text.Indexes;
with Database.Full_Text.Normalization;
with Database.Full_Text.Queries;
with Database.Full_Text.Snippets;
with Database.Full_Text.Compression;
with Database.Full_Text.Ranking; use Database.Full_Text.Ranking;
with Database.Full_Text.Storage;
with Database.Full_Text.Postings;
with Database.Full_Text.Segments;
with Database.Storage.Pages;
with Database.Full_Text.Tokenizers;
with Database.MVCC;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types; use Database.Types;
with Database.Values;
with Database.Versioning;
with Database.Plans;
with Database.Optimizer;
with Database.Execution_Plans;
with Database.Queries;
with Database.Ordering;

package body Full_Text_Tests is
   use AUnit.Assertions;
   use type Database.Status.Status_Code;
   use type Database.Full_Text.Segments.Segment_Id;
   use type Database.Full_Text.Segments.Segment_State;

   type Doc_Row is record
      Id      : Integer;
      Content : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   end record;

   function To_Row (D : Doc_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (D.Id));
      Database.Rows.Append
        (R,
         Database.Values.From_Text
           (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (D.Content)));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return Doc_Row is
   begin
      return
        (Id      => Database.Rows.Get (R, 0).Int,
         Content => Database.Rows.Get (R, 1).Text);
   end From_Row;

   function Key_Of (D : Doc_Row) return Integer
   is (D.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   package Docs is new
     Database.Tables.Typed
       (Doc_Row,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   function Doc_Schema return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("docs");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "body", Database.Types.Text_Value, False, False);
      return S;
   end Doc_Schema;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("full-text search");
   end Name;

   procedure Tokenizer_Tracks_Positions
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      V : constant Database.Full_Text.Tokenizers.Token_Vectors.Vector :=
        Database.Full_Text.Tokenizers.Tokenize ("Ada, database  engine");
   begin
      Assert (Natural (V.Length) = 3, "wrong token count");
      Assert
        (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String
           (V.Element (0).Text)
         = "Ada",
         "first token wrong");
      Assert (V.Element (2).Position = 2, "position tracking wrong");
   end Tokenizer_Tracks_Positions;

   procedure Normalization_Is_Conservative
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Config : Database.Full_Text.Normalization.Normalization_Config :=
        Database.Full_Text.Normalization.Default_Config;
   begin
      Assert
        (Database.Full_Text.Normalization.Normalize ("ÄDA") = "äda",
         "basic Unicode lowercasing failed");
      Assert
        (Database.Full_Text.Normalization.Normalize ("é") = "é",
         "accent should be preserved by default");
      Assert
        (Database.Full_Text.Normalization.Normalize ("ŁÓDŹ") = "łódź",
         "Latin Extended lowercasing failed");
      Config.Accents := Database.Full_Text.Normalization.Strip_Basic_Latin_Accents;
      Assert
        (Database.Full_Text.Normalization.Normalize ("Ærø Łódź Škoda", Config) =
         "aro lodz skoda",
         "expanded Latin accent stripping failed");
      Config.Accents := Database.Full_Text.Normalization.Preserve_Accents;
      Config.Stemming := Database.Full_Text.Normalization.Simple_English_Stemming;
      Assert
        (Database.Full_Text.Normalization.Normalize ("databases", Config) = "database",
         "plural stemming failed");
      Assert
        (Database.Full_Text.Normalization.Normalize ("queries", Config) = "query",
         "ies stemming failed");
   end Normalization_Is_Conservative;

   procedure Configured_Stemmed_Search
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema;
      R  : Database.Status.Result;
      C  : Database.Full_Text.Search_Cursor;
   begin
      Database.Full_Text.Clear;
      Database.Open_In_Memory (DB);
      S := Doc_Schema;
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_stemmed", "docs", 1, True);
      Assert (Database.Status.Is_Ok (R), "create configured full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada database engines process relational queries")));
      Assert (Database.Status.Is_Ok (R), "insert failed");

      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_stemmed",
           "query");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "stemmed query did not match plural indexed term");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_stemmed",
           "engine");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "singular query did not match plural indexed term");

      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Configured_Stemmed_Search;

   procedure Index_Rejects_Non_Text_Column
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : constant Database.Schema.Table_Schema := Doc_Schema;
      R : Database.Status.Result;
   begin
      R := Database.Full_Text.Indexes.Validate_Definition (S, 0);
      Assert
        (R.Code = Database.Status.Invalid_Argument,
         "integer full-text column accepted");
      R := Database.Full_Text.Indexes.Validate_Definition (S, 1);
      Assert (Database.Status.Is_Ok (R), "text full-text column rejected");
   end Index_Rejects_Non_Text_Column;

   procedure Search_Term_And_Boolean_Queries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema := Doc_Schema;
      R  : Database.Status.Result;
      C  : Database.Full_Text.Search_Cursor;
   begin
      Database.Full_Text.Clear;
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada database database")));
      Assert (Database.Status.Is_Ok (R), "insert doc 1 failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 2,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("storage engine")));
      Assert (Database.Status.Is_Ok (R), "insert doc 2 failed");
      C :=
        Database.Full_Text.Search
          (Tx, "docs_body_ft", "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "term search returned wrong count");
      Assert
        (Database.Full_Text.Element (C).Score > 1.0,
         "frequency score not reflected");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft",
           "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "database search returned wrong count");
      C :=
        Database.Full_Text.Search
          (Tx, "docs_body_ft", "storage");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "storage search returned wrong count");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);
   end Search_Term_And_Boolean_Queries;

   procedure Delete_Update_Phrase_And_Rollback
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Read_Tx : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      C       : Database.Full_Text.Search_Cursor;
   begin
      Database.Full_Text.Clear;
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_maintenance", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 10,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada database engine")));
      Assert (Database.Status.Is_Ok (R), "insert failed");

      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_maintenance",
           "Ada");
      Assert
        (Database.Full_Text.Row_Count (C) = 1, "Ada term not found");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_maintenance",
           "missing");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "missing term matched");

      R :=
        Docs.Update
          (Tx,
           DB,
           S,
           (Id      => 10,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada storage engine")));
      Assert (Database.Status.Is_Ok (R), "update failed");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_maintenance",
           "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "old term visible after update");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_maintenance",
           "storage");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "new term invisible after update");

      R := Docs.Delete (Tx, DB, S, 10);
      Assert (Database.Status.Is_Ok (R), "delete failed");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_maintenance",
           "storage");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "deleted term visible to deleting transaction");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");

      Database.Transactions.Begin_Read (DB, Read_Tx);
      C :=
        Database.Full_Text.Search
          (Read_Tx,
           "docs_body_ft_maintenance",
           "storage");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "deleted term visible after commit");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      Database.Close (DB);
   end Delete_Update_Phrase_And_Rollback;

   procedure Rollback_Hides_Uncommitted_Postings
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Read_Tx : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      C       : Database.Full_Text.Search_Cursor;
   begin
      Database.Full_Text.Clear;
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_rollback", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 20,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("rollback token")));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_rollback",
           "rollback");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "own uncommitted posting not visible");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");

      Database.Transactions.Begin_Read (DB, Read_Tx);
      C :=
        Database.Full_Text.Search
          (Read_Tx,
           "docs_body_ft_rollback",
           "rollback");
      Assert
        (Database.Full_Text.Row_Count (C) = 0, "rolled-back posting visible");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      Database.Close (DB);
   end Rollback_Hides_Uncommitted_Postings;

   procedure Save_And_Load_Preserves_Full_Text_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Read_Tx : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      C       : Database.Full_Text.Search_Cursor;
      Path    : constant Wide_Wide_String := "full_text_sidecar_test_db";
   begin
      Database.Full_Text.Clear;
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_sidecar", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 30,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("persistent token")));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      R := Database.Full_Text.Save (Path);
      Assert (Database.Status.Is_Ok (R), "full-text save failed");
      Database.Full_Text.Clear;
      R := Database.Full_Text.Load (DB, Path);
      Assert (Database.Status.Is_Ok (R), "full-text load failed");
      Database.Transactions.Begin_Read (DB, Read_Tx);
      C :=
        Database.Full_Text.Search
          (Read_Tx,
           "docs_body_ft_sidecar",
           "persistent");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "loaded full-text index did not return committed posting");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      Database.Close (DB);
   end Save_And_Load_Preserves_Full_Text_Index;

   procedure Delete_Does_Not_Shift_Full_Text_Row_References
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema := Doc_Schema;
      R  : Database.Status.Result;
      C  : Database.Full_Text.Search_Cursor;
   begin
      Database.Full_Text.Clear;
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_stable_refs", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("first alpha")));
      Assert (Database.Status.Is_Ok (R), "insert first failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 2,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("second beta")));
      Assert (Database.Status.Is_Ok (R), "insert second failed");
      R := Docs.Delete (Tx, DB, S, 1);
      Assert (Database.Status.Is_Ok (R), "delete first failed");

      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_stable_refs",
           "beta");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "deleting an earlier row shifted or hid the later row posting");
      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_stable_refs",
           "alpha");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "deleted earlier row remained visible");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Delete_Does_Not_Shift_Full_Text_Row_References;

   procedure Open_Rebuilds_Full_Text_From_Definitions_When_Sidecar_Missing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      DB2     : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Read_Tx : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      C       : Database.Full_Text.Search_Cursor;
      Path    : constant Wide_Wide_String := "full_text_rebuild_open_test_db";
      Path_S  : constant String := "full_text_rebuild_open_test_db";
   begin
      if Ada.Directories.Exists (Path_S) then
         Ada.Directories.Delete_File (Path_S);
      end if;
      if Ada.Directories.Exists (Path_S & ".wal") then
         Ada.Directories.Delete_File (Path_S & ".wal");
      end if;
      if Ada.Directories.Exists (Path_S & ".fts") then
         Ada.Directories.Delete_File (Path_S & ".fts");
      end if;

      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create persistent DB failed");
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_rebuild", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 100,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("rebuildable persistent token")));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      if Ada.Directories.Exists (Path_S & ".fts") then
         Ada.Directories.Delete_File (Path_S & ".fts");
      end if;

      Database.Open (DB2, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB2)),
         "open persistent DB failed");
      Database.Transactions.Begin_Read (DB2, Read_Tx);
      C :=
        Database.Full_Text.Search
          (Read_Tx,
           "docs_body_ft_rebuild",
           "persistent");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "open did not rebuild full-text postings from catalog definitions and table rows");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      Database.Close (DB2);
   end Open_Rebuilds_Full_Text_From_Definitions_When_Sidecar_Missing;

   procedure Full_Text_Optimizer_Plan_Node
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      P  : Database.Plans.Logical_Plan;
      PR : Database.Execution_Plans.Physical_Plan_Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      P :=
        Database.Plans.Table ("docs", 1, (Row_Count => 100, Page_Count => 4));
      P :=
        Database.Plans.Full_Text
          (P,
           "docs_body_ft_plan",
           "database");
      PR := Database.Optimizer.Optimize (Tx, P);
      Assert
        (Database.Status.Is_Ok (PR.Status),
         "optimizer rejected full-text logical plan");
      Assert
        (Database.Execution_Plans.Contains
           (PR.Plan, Database.Execution_Plans.Full_Text_Ranked_Search),
         "full-text physical plan node missing");
      declare
         R : constant Database.Status.Result :=
           Database.Transactions.Rollback (Tx);
      begin
         Assert (Database.Status.Is_Ok (R), "read rollback failed");
      end;
      Database.Close (DB);
   end Full_Text_Optimizer_Plan_Node;

   procedure Full_Text_Query_Exposes_Rank_For_Order_By
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      Q       : Database.Queries.Query;
      Ordered : Database.Queries.Query;
      C       : Database.Queries.Cursor;
      First   : Database.Rows.Row;
   begin
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_ranked_query", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada Ada database")));
      Assert (Database.Status.Is_Ok (R), "insert first failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 2,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada database")));
      Assert (Database.Status.Is_Ok (R), "insert second failed");

      Q :=
        Database.Queries.Full_Text_Search_With_Score
          (Tx,
           "docs_body_ft_ranked_query",
           Database.Full_Text.Queries.Term ("Ada"));
      Assert
        (Database.Queries.Row_Count (Q) = 2,
         "ranked full-text query did not return rows");
      Ordered :=
        Database.Queries.Order_By (Q, 2, Database.Ordering.Descending);
      Database.Queries.Execute (Ordered, C);
      Assert (Database.Queries.Has_Element (C), "ranked query cursor empty");
      First := Database.Queries.Element (C);
      Assert
        (Database.Rows.Get (First, 0).Int = 1,
         "higher-frequency row did not sort first by rank");
      Assert
        (Database.Rows.Get (First, 2).Kind = Database.Types.Float_Value,
         "rank column is not Float_Value");

      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Full_Text_Query_Exposes_Rank_For_Order_By;

   procedure Full_Text_Query_Composes_With_Relational_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema := Doc_Schema;
      R  : Database.Status.Result;
      Q  : Database.Queries.Query;
   begin
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_query", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada database")));
      Assert (Database.Status.Is_Ok (R), "insert first failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 2,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada storage")));
      Assert (Database.Status.Is_Ok (R), "insert second failed");
      Q :=
        Database.Queries.Full_Text_Search
          (Tx, "docs_body_ft_query", Database.Full_Text.Queries.Term ("Ada"));
      Assert
        (Database.Queries.Row_Count (Q) = 2,
         "query-level full-text search did not return rows");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Full_Text_Query_Composes_With_Relational_Filter;

   procedure Full_Text_Query_Resolves_Persistent_Rows_After_Reopen
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      DB2     : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Read_Tx : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      Q       : Database.Queries.Query;
      Path    : constant Wide_Wide_String := "full_text_query_reopen_test_db";
      Path_S  : constant String := "full_text_query_reopen_test_db";
   begin
      if Ada.Directories.Exists (Path_S) then
         Ada.Directories.Delete_File (Path_S);
      end if;
      if Ada.Directories.Exists (Path_S & ".wal") then
         Ada.Directories.Delete_File (Path_S & ".wal");
      end if;
      if Ada.Directories.Exists (Path_S & ".fts") then
         Ada.Directories.Delete_File (Path_S & ".fts");
      end if;

      Database.Create (DB, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "create persistent DB failed");
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 201,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("persistent query row")));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_query_reopen", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Database.Close (DB);

      Database.Open (DB2, Path);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB2)),
         "open persistent DB failed");
      Database.Transactions.Begin_Read (DB2, Read_Tx);
      Q :=
        Database.Queries.Full_Text_Search
          (Read_Tx,
           "docs_body_ft_query_reopen",
           Database.Full_Text.Queries.Term ("query"));
      Assert
        (Database.Queries.Row_Count (Q) = 1,
         "query-level full-text search did not resolve row from persistent heap after reopen");
      R := Database.Transactions.Rollback (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read rollback failed");
      Database.Close (DB2);
   end Full_Text_Query_Resolves_Persistent_Rows_After_Reopen;

   procedure Try_Full_Text_Search_Reports_Missing_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      Q  : Database.Queries.Query;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      Database.Transactions.Begin_Read (DB, Tx);
      R :=
        Database.Queries.Try_Full_Text_Search
          (Tx, "missing_ft_index", Database.Full_Text.Queries.Term ("Ada"), Q);
      Assert
        (R.Code = Database.Status.Not_Found,
         "missing full-text index should be reported as Not_Found");
      Assert
        (Database.Queries.Row_Count (Q) = 0,
         "failed full-text query should leave an empty query result");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Try_Full_Text_Search_Reports_Missing_Index;

   procedure Close_Purges_Handle_Full_Text_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema := Doc_Schema;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_close", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");
      Assert
        (Database.Full_Text.Full_Text_Index_Count = 1,
         "full-text index missing before close");
      Database.Close (DB);
      Assert
        (Database.Full_Text.Full_Text_Index_Count = 0,
         "close did not purge handle full-text state");
   end Close_Purges_Handle_Full_Text_State;

   procedure Rollback_Reverts_Full_Text_Index_Create_And_Drop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema := Doc_Schema;
      R  : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");

      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_rollback_ddl", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      Assert
        (Database.Full_Text.Full_Text_Index_Count = 0,
         "uncommitted full-text index should not be counted as committed metadata");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback create failed");
      Assert
        (not Database.Full_Text.Exists ("docs_body_ft_rollback_ddl"),
         "rolled-back full-text index creation left visible metadata");

      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_rollback_drop", "docs", 1);
      Assert
        (Database.Status.Is_Ok (R),
         "create full-text index for drop test failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit create failed");
      Assert
        (Database.Full_Text.Exists ("docs_body_ft_rollback_drop"),
         "committed full-text index missing before drop rollback");

      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Drop_Full_Text_Index
          (Tx, "docs_body_ft_rollback_drop");
      Assert (Database.Status.Is_Ok (R), "drop full-text index failed");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback drop failed");
      Assert
        (Database.Full_Text.Exists ("docs_body_ft_rollback_drop"),
         "rolled-back full-text index drop was not restored");

      Database.Close (DB);
   end Rollback_Reverts_Full_Text_Index_Create_And_Drop;

   procedure Two_Open_Databases_Keep_Separate_Full_Text_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB1 : Database.Handle;
      DB2 : Database.Handle;
      Tx1 : Database.Transactions.Transaction;
      Tx2 : Database.Transactions.Transaction;
      S1  : Database.Schema.Table_Schema := Doc_Schema;
      S2  : Database.Schema.Table_Schema := Doc_Schema;
      R   : Database.Status.Result;
      C   : Database.Full_Text.Search_Cursor;
   begin
      Database.Open_In_Memory (DB1);
      R := Docs.Register (DB1, S1);
      Assert (Database.Status.Is_Ok (R), "register db1 failed");
      Database.Transactions.Begin_Write (DB1, Tx1);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx1, "docs_body_ft_db1", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create db1 full-text index failed");
      R :=
        Docs.Insert
          (Tx1,
           DB1,
           S1,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("alpha database")));
      Assert (Database.Status.Is_Ok (R), "insert db1 failed");
      R := Database.Transactions.Commit (Tx1);
      Assert (Database.Status.Is_Ok (R), "commit db1 failed");

      Database.Open_In_Memory (DB2);
      R := Docs.Register (DB2, S2);
      Assert (Database.Status.Is_Ok (R), "register db2 failed");
      Database.Transactions.Begin_Write (DB2, Tx2);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx2, "docs_body_ft_db2", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create db2 full-text index failed");
      R :=
        Docs.Insert
          (Tx2,
           DB2,
           S2,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("beta storage")));
      Assert (Database.Status.Is_Ok (R), "insert db2 failed");
      R := Database.Transactions.Commit (Tx2);
      Assert (Database.Status.Is_Ok (R), "commit db2 failed");

      Database.Transactions.Begin_Read (DB1, Tx1);
      C :=
        Database.Full_Text.Search
          (Tx1,
           "docs_body_ft_db1",
           "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "db1 full-text state was lost after opening db2");
      C :=
        Database.Full_Text.Search
          (Tx1,
           "docs_body_ft_db2",
           "storage");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "db2 full-text state leaked into db1");
      R := Database.Transactions.Commit (Tx1);
      Assert (Database.Status.Is_Ok (R), "commit db1 read failed");

      Database.Transactions.Begin_Read (DB2, Tx2);
      C :=
        Database.Full_Text.Search
          (Tx2,
           "docs_body_ft_db2",
           "storage");
      Assert
        (Database.Full_Text.Row_Count (C) = 1, "db2 full-text state missing");
      C :=
        Database.Full_Text.Search
          (Tx2,
           "docs_body_ft_db1",
           "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 0,
         "db1 full-text state leaked into db2");
      R := Database.Transactions.Commit (Tx2);
      Assert (Database.Status.Is_Ok (R), "commit db2 read failed");

      Database.Close (DB1);
      Database.Close (DB2);
   end Two_Open_Databases_Keep_Separate_Full_Text_State;

   procedure Near_Fuzzy_BM25_And_Snippets_Work
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      S       : Database.Schema.Table_Schema := Doc_Schema;
      R       : Database.Status.Result;
      C       : Database.Full_Text.Search_Cursor;
   begin
      Database.Open_In_Memory (DB);
      R := Docs.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Database.Full_Text.Create_Full_Text_Index
          (Tx, "docs_body_ft_advanced", "docs", 1);
      Assert (Database.Status.Is_Ok (R), "create full-text index failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada relational database engine")));
      Assert (Database.Status.Is_Ok (R), "insert first failed");
      R :=
        Docs.Insert
          (Tx,
           DB,
           S,
           (Id      => 2,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("Ada storage subsystem")));
      Assert (Database.Status.Is_Ok (R), "insert second failed");

      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_advanced",
           "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "database query returned wrong count");

      C :=
        Database.Full_Text.Search
          (Tx,
           "docs_body_ft_advanced",
           "database");
      Assert
        (Database.Full_Text.Row_Count (C) = 1,
         "database term did not match");

      Assert
        (Database.Full_Text.Ranking.BM25_Score
           (Term_Frequency          => 3,
            Document_Frequency      => 1,
            Total_Documents         => 10,
            Document_Length         => 8,
            Average_Document_Length => 8.0)
         > Database.Full_Text.Ranking.BM25_Score
             (Term_Frequency          => 1,
              Document_Frequency      => 1,
              Total_Documents         => 10,
              Document_Length         => 8,
              Average_Document_Length => 8.0),
         "BM25 score should increase with term frequency");

      declare
         Snippet : Wide_Wide_String :=
            Database.Full_Text.Snippets.Generate
               ("The Ada relational database engine stores rows.",
               Database.Full_Text.Queries.Term ("database"));
      begin
         Assert (Snippet /= "", "snippet should not be empty");
         Assert (Snippet'Length < 80, "snippet should be bounded");
      end;
      declare
         Combining_Acute : constant Wide_Wide_Character :=
           Wide_Wide_Character'Val (16#0301#);
         Snippet : constant Wide_Wide_String :=
           Database.Full_Text.Snippets.Generate
             ("Cafe" & Combining_Acute & " database",
              Database.Full_Text.Queries.Term ("Cafe"));
      begin
         Assert
           (Snippet = "[Cafe" & Combining_Acute & "] database",
            "snippet split a combining-mark cluster");
      end;
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
   end Near_Fuzzy_BM25_And_Snippets_Work;

   procedure Full_Text_Compression_And_Native_Page_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P         : Database.Full_Text.Postings.Posting;
      V         : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Decoded   : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Positions : Database.Full_Text.Postings.Position_Vectors.Vector;
      Encoded   : Database.Full_Text.Compression.Byte_Vectors.Vector;
      Dec_Pos   : Database.Full_Text.Postings.Position_Vectors.Vector;
      Page      : Database.Storage.Pages.Page;
      Term      : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      R         : Database.Status.Result;
   begin
      Positions.Append (1);
      Positions.Append (3);
      Positions.Append (10);
      Encoded := Database.Full_Text.Compression.Encode_Positions (Positions);
      Dec_Pos := Database.Full_Text.Compression.Decode_Positions (Encoded);
      Assert (Natural (Dec_Pos.Length) = 3, "decoded position count wrong");
      Assert
        (Dec_Pos.Element (0) = 1
         and then Dec_Pos.Element (1) = 3
         and then Dec_Pos.Element (2) = 10,
         "gap-encoded positions did not roundtrip");
      Assert
        (Natural (Encoded.Length) < 8,
         "position varint encoding is unexpectedly large");

      P.Ref.Table_Id := 7;
      P.Ref.Row_Id := 11;
      P.Ref.Row_Key :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("INTEGER_VALUE: 11;");
      P.Ref.Column_Id := 1;
      P.Frequency := 3;
      P.Positions := Positions;
      V.Append (P);

      Page :=
        Database.Full_Text.Storage.Build_Posting_Page
          (Database.Storage.Pages.Page_Id (42), "database", V);
      R := Database.Full_Text.Storage.Parse_Posting_Page (Page, Term, Decoded);
      Assert
        (Database.Status.Is_Ok (R),
         "native full-text posting page failed to parse");
      Assert
        (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Term)
         = "database",
         "posting page term changed");
      Assert
        (Natural (Decoded.Length) = 1, "posting page posting count changed");
      Assert
        (Decoded.Element (0).Ref.Table_Id = 7,
         "posting page table id changed");
      Assert
        (Decoded.Element (0).Positions.Element (2) = 10,
         "posting page positions changed");
   end Full_Text_Compression_And_Native_Page_Roundtrip;

   procedure Tokenizer_Stop_Words_And_Posting_Skips_Work
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Config : Database.Full_Text.Tokenizers.Tokenizer_Config :=
        Database.Full_Text.Tokenizers.Default_Config;
      Tokens : Database.Full_Text.Tokenizers.Token_Vectors.Vector;
      Left   : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Right  : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Hits   : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Skips  : Database.Full_Text.Postings.Skip_Entry_Vectors.Vector;
      P      : Database.Full_Text.Postings.Posting;
   begin
      Config.Drop_Builtin_Stop_Words := True;
      Config.Minimum_Token_Length := 3;
      Tokens :=
        Database.Full_Text.Tokenizers.Tokenize
          ("the Ada database is in the engine", Config);
      Assert
        (Natural (Tokens.Length) = 3,
         "stop-word/min-length tokenizer returned wrong count");
      Assert
        (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String
           (Tokens.Element (0).Text)
         = "Ada",
         "first retained token wrong");
      Assert
        (Tokens.Element (0).Position = 1,
         "filtered tokenizer must preserve original token positions");
      Config.Minimum_Token_Length := 1;
      Config.Builtin_Stop_Words := Database.Full_Text.Tokenizers.Danish_Stop_Words;
      Tokens :=
        Database.Full_Text.Tokenizers.Tokenize
          ("det Ada indeks er hurtigt", Config);
      Assert
        (Natural (Tokens.Length) = 3,
         "Danish stop-word profile returned wrong count");
      Assert
        (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String
           (Tokens.Element (0).Text)
         = "Ada",
         "Danish stop-word profile retained wrong first token");

      for I in 1 .. 40 loop
         P :=
           (Ref        =>
              (Table_Id  => 1,
               Row_Id    => I,
               Row_Key   =>
                 Ada
                   .Strings
                   .Wide_Wide_Unbounded
                   .Null_Unbounded_Wide_Wide_String,
               Column_Id => 1),
            Frequency  => 1,
            Positions  =>
              Database.Full_Text.Postings.Position_Vectors.Empty_Vector,
            Created_By => 0,
            Created_At => 0,
            Deleted_By => 0,
            Deleted_At => 0);
         Database.Full_Text.Postings.Add_Position (P, I);
         Left.Append (P);
         if I mod 2 = 0 then
            Right.Append (P);
         end if;
      end loop;

      Skips := Database.Full_Text.Postings.Build_Skip_Table (Left, 8);
      Assert (Natural (Skips.Length) > 0, "posting skip table was not built");
      Hits :=
        Database.Full_Text.Postings.Intersect_With_Skips (Left, Right, 8);
      Assert
        (Natural (Hits.Length) = 20,
         "skip intersection returned wrong hit count");
      Assert
        (Hits.Element (0).Ref.Row_Id = 2, "skip intersection first hit wrong");
   end Tokenizer_Stop_Words_And_Posting_Skips_Work;

   procedure Full_Text_Segments_Merge_And_Compact_Work
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S1       : Database.Full_Text.Segments.Segment :=
        Database.Full_Text.Segments.Create (1);
      S2       : Database.Full_Text.Segments.Segment :=
        Database.Full_Text.Segments.Create (2);
      Merged   : Database.Full_Text.Segments.Segment;
      Segments : Database.Full_Text.Segments.Segment_Vectors.Vector;
      P        : Database.Full_Text.Postings.Posting;
      Hits     : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      P.Ref.Table_Id := 1;
      P.Ref.Row_Id := 1;
      P.Ref.Column_Id := 1;
      P.Frequency := 1;
      Database.Full_Text.Postings.Add_Position (P, 0);
      Database.Full_Text.Segments.Add_Posting (S1, "ada", P);

      P.Ref.Row_Id := 2;
      P.Frequency := 2;
      Database.Full_Text.Postings.Add_Position (P, 3);
      Database.Full_Text.Segments.Add_Posting (S2, "ada", P);
      Database.Full_Text.Segments.Seal (S1);

      Merged := Database.Full_Text.Segments.Merge (S1, S2, 3);
      Hits := Database.Full_Text.Segments.Lookup (Merged, "ada");
      Assert
        (Natural (Hits.Length) = 2,
         "merged segment should contain both postings");
      Assert
        (Merged.Metadata.State = Database.Full_Text.Segments.Sealed_Segment,
         "merged segment should be sealed");

      P.Deleted_At := 10;
      Database.Full_Text.Segments.Add_Posting (S2, "obsolete", P);
      Segments.Append (S1);
      Segments.Append (S2);
      Merged := Database.Full_Text.Segments.Compact (Segments, 4);
      Hits := Database.Full_Text.Segments.Lookup (Merged, "obsolete");
      Assert
        (Natural (Hits.Length) = 0,
         "compaction should omit obsolete postings");
      Assert
        (Database.Full_Text.Segments.Segment_Count (Segments) = 2,
         "active segment count wrong");
   end Full_Text_Segments_Merge_And_Compact_Work;

   procedure Full_Text_Segment_Compaction_Policy_Applies
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Segments  : Database.Full_Text.Segments.Segment_Vectors.Vector;
      Next_Id   : Database.Full_Text.Segments.Segment_Id := 10;
      Compacted : Boolean := False;
      Policy    : constant Database.Full_Text.Segments.Segment_Compaction_Policy :=
        (Max_Active_Segments       => 2,
         Minimum_Obsolete_Postings => 1,
         Minimum_Obsolete_Percent  => 20);
      P         : Database.Full_Text.Postings.Posting;
   begin
      P.Ref.Table_Id := 1;
      P.Ref.Column_Id := 1;
      P.Frequency := 1;
      Database.Full_Text.Postings.Add_Position (P, 0);

      for I in 1 .. 3 loop
         declare
            S : Database.Full_Text.Segments.Segment :=
              Database.Full_Text.Segments.Create
                (Database.Full_Text.Segments.Segment_Id (I));
         begin
            P.Ref.Row_Id := I;
            Database.Full_Text.Segments.Add_Posting (S, "ada", P);
            Database.Full_Text.Segments.Seal (S);
            Segments.Append (S);
         end;
      end loop;

      Assert
        (Database.Full_Text.Segments.Needs_Compaction (Segments, Policy),
         "segment policy should request compaction");
      Database.Full_Text.Segments.Compact_With_Policy
        (Segments, Next_Id, Compacted, Policy);
      Assert (Compacted, "segment policy did not compact");
      Assert
        (Database.Full_Text.Segments.Segment_Count (Segments) = 1,
         "segment policy should replace active segments with one segment");
      Assert
        (Segments.Element (0).Metadata.Id = 10,
         "compacted segment id should use next id");
      Assert
        (Next_Id = 11,
         "next segment id should advance after compaction");
      Assert
        (Database.Full_Text.Segments.Posting_Count (Segments) = 3,
         "segment policy should preserve live postings");
   end Full_Text_Segment_Compaction_Policy_Applies;

   procedure Full_Text_Index_Compaction_Rebuilds_Document_Stats
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      IX      : Database.Full_Text.Indexes.Full_Text_Index :=
        Database.Full_Text.Indexes.Create ("compact", Doc_Schema, 1);
      TE      : Database.Full_Text.Indexes.Term_Entry;
      Live    : Database.Full_Text.Postings.Posting;
      Deleted : Database.Full_Text.Postings.Posting;
      Removed : Natural;
   begin
      Live.Ref := (Table_Id => 1,
                   Row_Id => 1,
                   Row_Key =>
                     Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                       ("1"),
                   Column_Id => 1);
      Live.Frequency := 1;
      Database.Full_Text.Postings.Add_Position (Live, 0);

      Deleted := Live;
      Deleted.Ref.Row_Id := 2;
      Deleted.Ref.Row_Key :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("2");
      Deleted.Deleted_By := Database.Versioning.Transaction_Id (901);
      Deleted.Deleted_At := Database.Versioning.Commit_Version (20);
      Database.MVCC.Mark_Committed
        (Deleted.Deleted_By, Deleted.Deleted_At);

      TE.Term :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("ada");
      TE.Postings.Append (Live);
      TE.Postings.Append (Deleted);
      IX.Terms.Append (TE);
      IX.Deleted_Posting_Count := 1;
      Database.Full_Text.Indexes.Recompute_Document_Statistics_From_Postings
        (IX);

      Removed := Database.Full_Text.Indexes.Compact_Reclaimable_Postings (IX);
      Assert (Removed = 1, "index compaction removed wrong posting count");
      Assert
        (Database.Full_Text.Indexes.Posting_Count (IX) = 1,
         "index compaction should keep only live postings");
      Assert
        (Database.Full_Text.Indexes.Document_Count (IX) = 1,
         "index compaction should rebuild live document statistics");
      Assert
        (IX.Deleted_Posting_Count = 0,
         "index compaction should refresh deleted posting count");
   end Full_Text_Index_Compaction_Rebuilds_Document_Stats;

   procedure Full_Text_Document_Statistics_Drive_Ranking
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      IX   : Database.Full_Text.Indexes.Full_Text_Index :=
        Database.Full_Text.Indexes.Create ("stats", Doc_Schema, 1);
      Row1 : Database.Rows.Row;
      Row2 : Database.Rows.Row;
   begin
      Row1 :=
        To_Row
          ((Id      => 1,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("ada database database")));
      Row2 :=
        To_Row
          ((Id      => 2,
            Content =>
              Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
                ("ada")));

      Database.Full_Text.Indexes.Index_Row_Committed (IX, 1, "1", Row1);
      Database.Full_Text.Indexes.Index_Row_Committed (IX, 2, "2", Row2);

      Assert
        (Database.Full_Text.Indexes.Document_Count (IX) = 2,
         "document count should track live rows");
      Assert
        (Database.Full_Text.Indexes.Document_Length (IX, "1") = 3,
         "document length for first row wrong");
      Assert
        (Database.Full_Text.Indexes.Document_Length (IX, "2") = 1,
         "document length for second row wrong");
      Assert
        (Database.Full_Text.Indexes.Average_Document_Length (IX) = 2,
         "average document length wrong");
      Assert
        (Database.Full_Text.Indexes.Document_Frequency (IX, "database") = 1,
         "document frequency should count documents, not postings");
      Assert
        (Database.Full_Text.Indexes.Document_Frequency (IX, "ada") = 2,
         "shared term document frequency wrong");
   end Full_Text_Document_Statistics_Drive_Ranking;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Tokenizer_Tracks_Positions'Access, "tokenizer tracks positions");
      Register_Routine
        (T,
         Normalization_Is_Conservative'Access,
         "normalization is conservative");
      Register_Routine
        (T,
         Configured_Stemmed_Search'Access,
         "configured stemmed search");
      Register_Routine
        (T,
         Index_Rejects_Non_Text_Column'Access,
         "index rejects non-text column");
      Register_Routine
        (T, Search_Term_And_Boolean_Queries'Access, "term and boolean search");
      Register_Routine
        (T,
         Delete_Update_Phrase_And_Rollback'Access,
         "delete update phrase and rollback visibility");
      Register_Routine
        (T,
         Rollback_Hides_Uncommitted_Postings'Access,
         "rollback hides uncommitted postings");
      Register_Routine
        (T,
         Save_And_Load_Preserves_Full_Text_Index'Access,
         "save and load preserves full-text index");
      Register_Routine
        (T,
         Delete_Does_Not_Shift_Full_Text_Row_References'Access,
         "delete does not shift full-text row references");
      Register_Routine
        (T,
         Open_Rebuilds_Full_Text_From_Definitions_When_Sidecar_Missing'Access,
         "open rebuilds full-text from definitions when sidecar missing");
      Register_Routine
        (T,
         Full_Text_Optimizer_Plan_Node'Access,
         "full-text optimizer plan node");
      Register_Routine
        (T,
         Full_Text_Query_Composes_With_Relational_Filter'Access,
         "full-text query composes with relational filter");
      Register_Routine
        (T,
         Full_Text_Query_Exposes_Rank_For_Order_By'Access,
         "full-text query exposes rank for order by");
      Register_Routine
        (T,
         Full_Text_Query_Resolves_Persistent_Rows_After_Reopen'Access,
         "full-text query resolves persistent rows after reopen");
      Register_Routine
        (T,
         Try_Full_Text_Search_Reports_Missing_Index'Access,
         "try full-text query reports missing index");
      Register_Routine
        (T,
         Close_Purges_Handle_Full_Text_State'Access,
         "close purges handle full-text state");
      Register_Routine
        (T,
         Rollback_Reverts_Full_Text_Index_Create_And_Drop'Access,
         "rollback reverts full-text index create and drop");
      Register_Routine
        (T,
         Two_Open_Databases_Keep_Separate_Full_Text_State'Access,
         "two open databases keep separate full-text state");
      Register_Routine
        (T,
         Near_Fuzzy_BM25_And_Snippets_Work'Access,
         "near fuzzy bm25 and snippets work");
      Register_Routine
        (T,
         Full_Text_Compression_And_Native_Page_Roundtrip'Access,
         "full-text compression and native page roundtrip");
      Register_Routine
        (T,
         Tokenizer_Stop_Words_And_Posting_Skips_Work'Access,
         "tokenizer stop words and posting skips work");
      Register_Routine
        (T,
         Full_Text_Segments_Merge_And_Compact_Work'Access,
         "full-text segments merge and compact work");
      Register_Routine
        (T,
         Full_Text_Segment_Compaction_Policy_Applies'Access,
         "full-text segment compaction policy applies");
      Register_Routine
        (T,
         Full_Text_Index_Compaction_Rebuilds_Document_Stats'Access,
         "full-text index compaction rebuilds document stats");
      Register_Routine
        (T,
         Full_Text_Document_Statistics_Drive_Ranking'Access,
         "full-text document statistics drive ranking");
   end Register_Tests;
end Full_Text_Tests;
