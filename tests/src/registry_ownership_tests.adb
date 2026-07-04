with Ada.Containers;
with AUnit.Assertions;

with Ada.Strings.Wide_Wide_Unbounded;
with Database;
with Database.Catalog;
with Database.Schema;
with Database.Status;
with Database.Types;
with Database.Rows;
with Database.Extensions;
with Database.Functions;
with Database.Aggregate_Functions;
with Database.Collations;
with Database.Full_Text.Tokenizers;
with Database.Full_Text.Ranking; use Database.Full_Text.Ranking;
with Database.Validation_Hooks;
with Database.Values;

package body Registry_Ownership_Tests is
   use AUnit.Assertions;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("per-handle registry ownership");
   end Name;

   procedure Build_Schema
     (Name : Wide_Wide_String; S : in out Database.Schema.Table_Schema) is
   begin
      S.Name := To_Unbounded_Wide_Wide_String (Name);
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
   end Build_Schema;

   procedure Catalog_State_Is_Per_Handle
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB1, DB2      : Database.Handle;
      S1, S2, Found : Database.Schema.Table_Schema;
      R             : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB1);
      Database.Open_In_Memory (DB2);

      Build_Schema ("registry_one", S1);
      R := Database.Catalog.Register (DB1, S1);
      Assert (Database.Status.Is_Ok (R), "register in first handle failed");

      Build_Schema ("registry_two", S2);
      R := Database.Catalog.Register (DB2, S2);
      Assert (Database.Status.Is_Ok (R), "register in second handle failed");

      Database.Catalog.Select_Database (Database.Catalog_State_Key (DB1));
      R := Database.Catalog.Find_By_Name ("registry_one", Found);
      Assert (Database.Status.Is_Ok (R), "first handle lost its table");
      R := Database.Catalog.Find_By_Name ("registry_two", Found);
      Assert
        (not Database.Status.Is_Ok (R),
         "second handle table leaked into first handle catalog");

      Database.Catalog.Select_Database (Database.Catalog_State_Key (DB2));
      R := Database.Catalog.Find_By_Name ("registry_two", Found);
      Assert (Database.Status.Is_Ok (R), "second handle lost its table");
      R := Database.Catalog.Find_By_Name ("registry_one", Found);
      Assert
        (not Database.Status.Is_Ok (R),
         "first handle table leaked into second handle catalog");

      Database.Close (DB1);
      Database.Catalog.Select_Database (Database.Catalog_State_Key (DB2));
      R := Database.Catalog.Find_By_Name ("registry_two", Found);
      Assert
        (Database.Status.Is_Ok (R),
         "closing first handle disturbed second handle catalog");
      Database.Close (DB2);
   end Catalog_State_Is_Per_Handle;

   procedure Extension_State_Is_Per_Handle
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB1, DB2 : Database.Handle;
      E1, E2   : Database.Extensions.Extension_Definition;
      R        : Database.Status.Result;
   begin
      Database.Open_In_Memory (DB1);
      Database.Open_In_Memory (DB2);

      E1.Name := To_Unbounded_Wide_Wide_String ("extension_one");
      E1.Compatibility_Id := To_Unbounded_Wide_Wide_String ("one");
      R := Database.Extensions.Register_Extension (DB1, E1);
      Assert (Database.Status.Is_Ok (R), "register first extension failed");

      E2.Name := To_Unbounded_Wide_Wide_String ("extension_two");
      E2.Compatibility_Id := To_Unbounded_Wide_Wide_String ("two");
      R := Database.Extensions.Register_Extension (DB2, E2);
      Assert (Database.Status.Is_Ok (R), "register second extension failed");

      Database.Extensions.Select_Database (Database.Catalog_State_Key (DB1));
      Assert
        (Natural (Database.Extensions.Registered_Extensions.Length) = 1,
         "first handle extension count wrong");
      Assert
        (To_Wide_Wide_String
           (Database.Extensions.Registered_Extensions.Element (0).Name)
         = "extension_one",
         "first handle extension registry polluted");

      Database.Extensions.Select_Database (Database.Catalog_State_Key (DB2));
      Assert
        (Natural (Database.Extensions.Registered_Extensions.Length) = 1,
         "second handle extension count wrong");
      Assert
        (To_Wide_Wide_String
           (Database.Extensions.Registered_Extensions.Element (0).Name)
         = "extension_two",
         "second handle extension registry polluted");

      Database.Close (DB1);
      Database.Extensions.Select_Database (Database.Catalog_State_Key (DB2));
      Assert
        (Natural (Database.Extensions.Registered_Extensions.Length) = 1,
         "closing first handle disturbed second extension registry");
      Database.Close (DB2);
   end Extension_State_Is_Per_Handle;

   function Identity_Int
     (Arguments : Database.Values.Value_Vector) return Database.Values.Value is
   begin
      if Arguments.Length = 0 then
         return Database.Values.From_Integer (0);
      end if;
      return Arguments.Element (0);
   end Identity_Int;

   function Other_Int
     (Arguments : Database.Values.Value_Vector) return Database.Values.Value
   is
      pragma Unreferenced (Arguments);
   begin
      return Database.Values.From_Integer (999);
   end Other_Int;

   function Reverse_Cmp (Left, Right : Wide_Wide_String) return Integer is
   begin
      if Left = Right then
         return 0;
      elsif Left > Right then
         return -1;
      else
         return 1;
      end if;
   end Reverse_Cmp;

   procedure Init_Count
     (State : in out Database.Aggregate_Functions.Aggregate_State) is
   begin
      State.Values.Clear;
   end Init_Count;

   procedure Step_Count
     (State     : in out Database.Aggregate_Functions.Aggregate_State;
      Arguments : Database.Values.Value_Vector;
      Result    : out Database.Status.Result) is
   begin
      pragma Unreferenced (Arguments);
      State.Values.Append (Database.Values.From_Integer (1));
      Result := Database.Status.Success;
   end Step_Count;

   function Finish_Count
     (State : Database.Aggregate_Functions.Aggregate_State)
      return Database.Values.Value is
   begin
      return Database.Values.From_Integer (Natural (State.Values.Length));
   end Finish_Count;

   function Single_Token
     (Text : Wide_Wide_String)
      return Database.Full_Text.Tokenizers.Token_Vectors.Vector
   is
      V : Database.Full_Text.Tokenizers.Token_Vectors.Vector;
   begin
      V.Append
        (Database.Full_Text.Tokenizers.Token'(Text         => To_Unbounded_Wide_Wide_String (Text),
          Position     => 0,
          Start_Offset => 0,
          End_Offset   => Text'Length));
      return V;
   end Single_Token;

   function Rank_One
     (Context : Database.Full_Text.Ranking.Ranking_Context)
      return Database.Full_Text.Ranking.Score
   is
      pragma Unreferenced (Context);
   begin
      return 1.0;
   end Rank_One;

   function Accept_Row
     (Schema : Database.Schema.Table_Schema; Row : Database.Rows.Row)
      return Database.Status.Result
   is
      pragma Unreferenced (Schema, Row);
   begin
      return Database.Status.Success;
   end Accept_Row;

   procedure Callable_Registries_Are_Per_Handle
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB1, DB2     : Database.Handle;
      R            : Database.Status.Result;
      Args         : Database.Values.Value_Vector;
      V            : Database.Values.Value;
      Cmp          : Integer;
      Config       : Database.Full_Text.Tokenizers.Tokenizer_Config :=
        Database.Full_Text.Tokenizers.Default_Config;
      Tokens       : Database.Full_Text.Tokenizers.Token_Vectors.Vector;
      Score        : Database.Full_Text.Ranking.Score;
      Empty_Row    : Database.Rows.Row;
      Empty_Schema : Database.Schema.Table_Schema;
   begin
      Database.Open_In_Memory (DB1);
      Database.Open_In_Memory (DB2);

      R :=
        Database.Functions.Register_Function
          (DB1,
           (Argument_Count   => 1,
            Name             => To_Unbounded_Wide_Wide_String ("only_db1"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Deterministic    => True,
            Nullable_Result  => False,
            Result_Type      => Database.Types.Integer_Value,
            Argument_Types   => [1 => Database.Types.Integer_Value],
            Index_Compatible => True,
            Monotonic        => False,
            Estimated_Cost   => 1),
           Identity_Int'Access);
      Assert (Database.Status.Is_Ok (R), "DB1 scalar registration failed");

      Args.Append (Database.Values.From_Integer (7));
      Database.Functions.Select_Database (Database.Catalog_State_Key (DB1));
      R := Database.Functions.Evaluate ("only_db1", Args, V);
      Assert
        (Database.Status.Is_Ok (R) and then V.Int = 7,
         "DB1 scalar not visible to DB1");
      Database.Functions.Select_Database (Database.Catalog_State_Key (DB2));
      R := Database.Functions.Evaluate ("only_db1", Args, V);
      Assert (not Database.Status.Is_Ok (R), "DB1 scalar leaked into DB2");

      R :=
        Database.Functions.Register_Function
          (DB2,
           (Argument_Count   => 1,
            Name             => To_Unbounded_Wide_Wide_String ("only_db2"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Deterministic    => True,
            Nullable_Result  => False,
            Result_Type      => Database.Types.Integer_Value,
            Argument_Types   => [1 => Database.Types.Integer_Value],
            Index_Compatible => True,
            Monotonic        => False,
            Estimated_Cost   => 1),
           Other_Int'Access);
      Assert (Database.Status.Is_Ok (R), "DB2 scalar registration failed");
      Database.Functions.Select_Database (Database.Catalog_State_Key (DB1));
      R := Database.Functions.Evaluate ("only_db2", Args, V);
      Assert (not Database.Status.Is_Ok (R), "DB2 scalar leaked into DB1");

      R :=
        Database.Aggregate_Functions.Register_Aggregate
          (DB1,
           (Name             => To_Unbounded_Wide_Wide_String ("db1_count"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Argument_Count   => 1,
            Result_Type      => Database.Types.Integer_Value,
            Deterministic    => True,
            Estimated_Cost   => 1),
           (Initialize => Init_Count'Access,
            Step       => Step_Count'Access,
            Finalize   => Finish_Count'Access));
      Assert (Database.Status.Is_Ok (R), "DB1 aggregate registration failed");
      Database.Aggregate_Functions.Select_Database
        (Database.Catalog_State_Key (DB1));
      R := Database.Aggregate_Functions.Evaluate ("db1_count", Args, V);
      Assert
        (Database.Status.Is_Ok (R) and then V.Int = 1,
         "DB1 aggregate not visible to DB1");
      Database.Aggregate_Functions.Select_Database
        (Database.Catalog_State_Key (DB2));
      R := Database.Aggregate_Functions.Evaluate ("db1_count", Args, V);
      Assert (not Database.Status.Is_Ok (R), "DB1 aggregate leaked into DB2");

      R :=
        Database.Collations.Register_Collation
          (DB1,
           (Name             => To_Unbounded_Wide_Wide_String ("db1_reverse"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Deterministic    => True,
            Index_Compatible => True),
           Reverse_Cmp'Access);
      Assert (Database.Status.Is_Ok (R), "DB1 collation registration failed");
      Database.Collations.Select_Database (Database.Catalog_State_Key (DB1));
      R := Database.Collations.Compare ("db1_reverse", "b", "a", Cmp);
      Assert
        (Database.Status.Is_Ok (R) and then Cmp < 0,
         "DB1 collation not visible to DB1");
      Database.Collations.Select_Database (Database.Catalog_State_Key (DB2));
      R := Database.Collations.Compare ("db1_reverse", "b", "a", Cmp);
      Assert (not Database.Status.Is_Ok (R), "DB1 collation leaked into DB2");

      R :=
        Database.Full_Text.Tokenizers.Register_Tokenizer
          (DB1,
           (Name             =>
              To_Unbounded_Wide_Wide_String ("db1_tokenizer"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Deterministic    => True),
           Single_Token'Access);
      Assert (Database.Status.Is_Ok (R), "DB1 tokenizer registration failed");
      Config.Kind := Database.Full_Text.Tokenizers.Custom_Tokenizer;
      Config.Custom_Name := To_Unbounded_Wide_Wide_String ("db1_tokenizer");
      Database.Full_Text.Tokenizers.Select_Database
        (Database.Catalog_State_Key (DB1));
      Tokens := Database.Full_Text.Tokenizers.Tokenize ("abc", Config);
      Assert (Natural (Tokens.Length) = 1, "DB1 tokenizer not visible to DB1");
      Database.Full_Text.Tokenizers.Select_Database
        (Database.Catalog_State_Key (DB2));
      Tokens := Database.Full_Text.Tokenizers.Tokenize ("abc", Config);
      Assert (Natural (Tokens.Length) = 0, "DB1 tokenizer leaked into DB2");

      R :=
        Database.Full_Text.Ranking.Register_Ranking_Function
          (DB1,
           (Name             => To_Unbounded_Wide_Wide_String ("db1_rank"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Deterministic    => True),
           Rank_One'Access);
      Assert (Database.Status.Is_Ok (R), "DB1 ranker registration failed");
      Database.Full_Text.Ranking.Select_Database
        (Database.Catalog_State_Key (DB1));
      R :=
        Database.Full_Text.Ranking.Score_With
          ("db1_rank",
           (Term_Frequency => 1, Matched_Terms => 1, Document_Length => 1),
           Score);
      Assert
        (Database.Status.Is_Ok (R) and then Score = 1.0,
         "DB1 ranker not visible to DB1");
      Database.Full_Text.Ranking.Select_Database
        (Database.Catalog_State_Key (DB2));
      R :=
        Database.Full_Text.Ranking.Score_With
          ("db1_rank",
           (Term_Frequency => 1, Matched_Terms => 1, Document_Length => 1),
           Score);
      Assert (not Database.Status.Is_Ok (R), "DB1 ranker leaked into DB2");

      R :=
        Database.Validation_Hooks.Register_Validation_Hook
          (DB1,
           (Name             => To_Unbounded_Wide_Wide_String ("db1_hook"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("isolation"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("isolation_1"),
            Deterministic    => True),
           Accept_Row'Access);
      Assert
        (Database.Status.Is_Ok (R), "DB1 validation hook registration failed");
      Database.Validation_Hooks.Select_Database
        (Database.Catalog_State_Key (DB1));
      R :=
        Database.Validation_Hooks.Validate
          ("db1_hook", Empty_Schema, Empty_Row);
      Assert
        (Database.Status.Is_Ok (R), "DB1 validation hook not visible to DB1");
      Database.Validation_Hooks.Select_Database
        (Database.Catalog_State_Key (DB2));
      R :=
        Database.Validation_Hooks.Validate
          ("db1_hook", Empty_Schema, Empty_Row);
      Assert
        (not Database.Status.Is_Ok (R), "DB1 validation hook leaked into DB2");

      Database.Close (DB1);
      Database.Functions.Select_Database (Database.Catalog_State_Key (DB2));
      R := Database.Functions.Evaluate ("only_db2", Args, V);
      Assert
        (Database.Status.Is_Ok (R) and then V.Int = 999,
         "closing DB1 disturbed DB2 callable registry");
      Database.Close (DB2);
   end Callable_Registries_Are_Per_Handle;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Catalog_State_Is_Per_Handle'Access,
         "catalog registry is owned per database handle");
      Register_Routine
        (T,
         Extension_State_Is_Per_Handle'Access,
         "extension registry is owned per database handle");
      Register_Routine
        (T,
         Callable_Registries_Are_Per_Handle'Access,
         "callable registries are owned per database handle");
   end Register_Tests;
end Registry_Ownership_Tests;
