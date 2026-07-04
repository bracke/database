with AUnit.Assertions;

with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Aggregate_Functions;
with Database.Collations;
with Database.Expressions;
with Database.Extension_Metadata;
with Database.Extensions;
with Database.Full_Text.Ranking; use Database.Full_Text.Ranking;
with Database.Full_Text.Tokenizers;
with Database.Functions;
with Database.Rows; use Database.Rows;
with Database.Schema;
with Database.Status; use Database.Status;
with Database.Types;
with Database.Validation_Hooks;
with Database.Values;

package body Extension_Tests is
   use AUnit.Assertions;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Database.Types.Value_Kind;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("extensions");
   end Name;

   function Trimmed_Lower
     (Arguments : Database.Values.Value_Vector) return Database.Values.Value
   is
      S : Wide_Wide_String := To_Wide_Wide_String (Arguments.Element (0).Text);
   begin
      for I in S'Range loop
         if S (I) in 'A' .. 'Z' then
            S (I) :=
              Wide_Wide_Character'Val (Wide_Wide_Character'Pos (S (I)) + 32);
         end if;
      end loop;
      return Database.Values.From_Text (S);
   end Trimmed_Lower;

   procedure Init_Sum
     (State : in out Database.Aggregate_Functions.Aggregate_State) is
   begin
      State.Values.Clear;
      State.Values.Append (Database.Values.From_Integer (0));
   end Init_Sum;

   procedure Step_Sum
     (State     : in out Database.Aggregate_Functions.Aggregate_State;
      Arguments : Database.Values.Value_Vector;
      Result    : out Database.Status.Result)
   is
      Current : Integer := State.Values.Element (0).Int;
   begin
      Current := Current + Arguments.Element (0).Int;
      State.Values.Replace_Element (0, Database.Values.From_Integer (Current));
      Result := Database.Status.Success;
   end Step_Sum;

   function Finish_Sum
     (State : Database.Aggregate_Functions.Aggregate_State)
      return Database.Values.Value is
   begin
      return State.Values.Element (0);
   end Finish_Sum;

   function Reverse_Collation (Left, Right : Wide_Wide_String) return Integer
   is
   begin
      if Left = Right then
         return 0;
      elsif Left > Right then
         return -1;
      else
         return 1;
      end if;
   end Reverse_Collation;

   function Pair_Tokenizer
     (Text : Wide_Wide_String)
      return Database.Full_Text.Tokenizers.Token_Vectors.Vector
   is
      V : Database.Full_Text.Tokenizers.Token_Vectors.Vector;
   begin
      if Text'Length >= 2 then
         V.Append
           (Database.Full_Text.Tokenizers.Token'(
            Text         =>
               To_Unbounded_Wide_Wide_String
                 (Text (Text'First .. Text'First + 1)),
             Position     => 0,
             Start_Offset => 0,
             End_Offset   => 2));
      end if;
      return V;
   end Pair_Tokenizer;

   function Linear_Rank
     (Context : Database.Full_Text.Ranking.Ranking_Context)
      return Database.Full_Text.Ranking.Score is
   begin
      return
        Database.Full_Text.Ranking.Score
          (Context.Term_Frequency + Context.Matched_Terms);
   end Linear_Rank;

   function Reject_Negative
     (Schema : Database.Schema.Table_Schema; Row : Database.Rows.Row)
      return Database.Status.Result
   is
      pragma Unreferenced (Schema);
   begin
      if Database.Rows.Get (Row, 0).Int < 0 then
         return
           Database.Status.Failure
             (Database.Status.Constraint_Error,
              "negative value rejected by validation hook");
      end if;
      return Database.Status.Success;
   end Reject_Negative;

   procedure Scalar_Functions_And_Expressions
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB    : Database.Handle;
      R     : Database.Status.Result;
      Args  : Database.Values.Value_Vector;
      V     : Database.Values.Value;
      Exprs : Database.Expressions.Expression_Vectors.Vector;
      S     : Database.Schema.Table_Schema;
      Row   : Database.Rows.Row;
   begin
      Database.Open_In_Memory (DB);
      R :=
        Database.Functions.Register_Function
          (DB,
           (Argument_Count   => 1,
            Name             => To_Unbounded_Wide_Wide_String ("lower_custom"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("core_text"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("core_text_1"),
            Deterministic    => True,
            Nullable_Result  => False,
            Result_Type      => Database.Types.Text_Value,
            Argument_Types   => [1 => Database.Types.Text_Value],
            Index_Compatible => True,
            Monotonic        => False,
            Estimated_Cost   => 1),
           Trimmed_Lower'Access);
      Assert (Database.Status.Is_Ok (R), "scalar function registered");
      Args.Append (Database.Values.From_Text ("ABC"));
      R := Database.Functions.Evaluate ("lower_custom", Args, V);
      Assert (Database.Status.Is_Ok (R), "scalar function evaluates");
      Assert (To_Wide_Wide_String (V.Text) = "abc", "scalar function result");
      Exprs.Append
        (Database.Expressions.Literal (Database.Values.From_Text ("ADA")));
      R :=
        Database.Expressions.Evaluate
          (Database.Expressions.Registered_Function_Call
             ("lower_custom", Exprs),
           S,
           Row,
           V);
      Assert
        (Database.Status.Is_Ok (R),
         "registered function expression evaluates");
      Assert
        (To_Wide_Wide_String (V.Text) = "ada",
         "registered function expression result");
   end Scalar_Functions_And_Expressions;

   procedure Aggregates_Collations_Tokenizers_Ranking
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB     : Database.Handle;
      R      : Database.Status.Result;
      Values : Database.Values.Value_Vector;
      V      : Database.Values.Value;
      Cmp    : Integer;
      Tokens : Database.Full_Text.Tokenizers.Token_Vectors.Vector;
      Config : Database.Full_Text.Tokenizers.Tokenizer_Config :=
        Database.Full_Text.Tokenizers.Default_Config;
      Score  : Database.Full_Text.Ranking.Score;
   begin
      Database.Open_In_Memory (DB);
      R :=
        Database.Aggregate_Functions.Register_Aggregate
          (DB,
           (Name             => To_Unbounded_Wide_Wide_String ("sum_custom"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("math"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("math_1"),
            Argument_Count   => 1,
            Result_Type      => Database.Types.Integer_Value,
            Deterministic    => True,
            Estimated_Cost   => 1),
           (Initialize => Init_Sum'Access,
            Step       => Step_Sum'Access,
            Finalize   => Finish_Sum'Access));
      Assert (Database.Status.Is_Ok (R), "aggregate registered");
      Values.Append (Database.Values.From_Integer (2));
      Values.Append (Database.Values.From_Integer (3));
      R := Database.Aggregate_Functions.Evaluate ("sum_custom", Values, V);
      Assert
        (Database.Status.Is_Ok (R) and then V.Int = 5, "aggregate computes");
      R :=
        Database.Collations.Register_Collation
          (DB,
           (Name             => To_Unbounded_Wide_Wide_String ("reverse"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("sort"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("sort_1"),
            Deterministic    => True,
            Index_Compatible => True),
           Reverse_Collation'Access);
      Assert (Database.Status.Is_Ok (R), "collation registered");
      R := Database.Collations.Compare ("reverse", "b", "a", Cmp);
      Assert
        (Database.Status.Is_Ok (R) and then Cmp < 0,
         "custom collation orders text");
      R :=
        Database.Full_Text.Tokenizers.Register_Tokenizer
          (DB,
           (Name             => To_Unbounded_Wide_Wide_String ("pairs"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("ft"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("ft_1"),
            Deterministic    => True),
           Pair_Tokenizer'Access);
      Assert (Database.Status.Is_Ok (R), "tokenizer registered");
      Config.Kind := Database.Full_Text.Tokenizers.Custom_Tokenizer;
      Config.Custom_Name := To_Unbounded_Wide_Wide_String ("pairs");
      Tokens := Database.Full_Text.Tokenizers.Tokenize ("abcd", Config);
      Assert
        (Natural (Tokens.Length) = 1
         and then To_Wide_Wide_String (Tokens.Element (0).Text) = "ab",
         "custom tokenizer used");
      R :=
        Database.Full_Text.Ranking.Register_Ranking_Function
          (DB,
           (Name             => To_Unbounded_Wide_Wide_String ("linear"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("rank"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("rank_1"),
            Deterministic    => True),
           Linear_Rank'Access);
      Assert (Database.Status.Is_Ok (R), "ranking registered");
      R :=
        Database.Full_Text.Ranking.Score_With
          ("linear",
           (Term_Frequency => 2, Matched_Terms => 3, Document_Length => 0),
           Score);
      Assert
        (Database.Status.Is_Ok (R) and then Score = 5.0,
         "custom ranking scores");
   end Aggregates_Collations_Tokenizers_Ranking;

   procedure Validation_And_Dependency_Checks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB  : Database.Handle;
      R   : Database.Status.Result;
      Row : Database.Rows.Row;
      S   : Database.Schema.Table_Schema;
      Dep : Database.Extension_Metadata.Dependency;
   begin
      Database.Open_In_Memory (DB);
      R :=
        Database.Validation_Hooks.Register_Validation_Hook
          (DB,
           (Name             =>
              To_Unbounded_Wide_Wide_String ("reject_negative"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("rules"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("rules_1"),
            Deterministic    => True),
           Reject_Negative'Access);
      Assert (Database.Status.Is_Ok (R), "validation hook registered");
      Database.Rows.Append (Row, Database.Values.From_Integer (-1));
      R := Database.Validation_Hooks.Validate ("reject_negative", S, Row);
      Assert
        (R.Code = Database.Status.Constraint_Error,
         "validation hook rejects row");
      Dep.Object_Name := To_Unbounded_Wide_Wide_String ("missing_function");
      Dep.Object_Kind := Database.Extension_Metadata.Scalar_Function_Object;
      Dep.Required_Version := 1;
      Dep.Compatibility_Id := To_Unbounded_Wide_Wide_String ("missing_1");
      R := Database.Extensions.Add_Dependency (DB, Dep);
      Assert (Database.Status.Is_Ok (R), "scalar dependency recorded");
      R := Database.Extensions.Validate_Dependencies;
      Assert
        (R.Code = Database.Status.Missing_Extension,
         "missing scalar dependency detected");

      Database.Extensions.Clear;
      R :=
        Database.Validation_Hooks.Register_Validation_Hook
          (DB,
           (Name             =>
              To_Unbounded_Wide_Wide_String ("reject_negative"),
            Extension_Name   => To_Unbounded_Wide_Wide_String ("rules"),
            Version          => 1,
            Compatibility_Id => To_Unbounded_Wide_Wide_String ("rules_1"),
            Deterministic    => True),
           Reject_Negative'Access);
      Assert
        (Database.Status.Is_Ok (R),
         "validation hook re-registered after clear");
      Dep.Object_Name := To_Unbounded_Wide_Wide_String ("reject_negative");
      Dep.Object_Kind := Database.Extension_Metadata.Validation_Hook_Object;
      Dep.Required_Version := 1;
      Dep.Compatibility_Id := To_Unbounded_Wide_Wide_String ("rules_1");
      R := Database.Extensions.Add_Dependency (DB, Dep);
      Assert (Database.Status.Is_Ok (R), "validation dependency recorded");
      R := Database.Extensions.Validate_Dependencies;
      Assert
        (Database.Status.Is_Ok (R), "validation hook dependency validated");

      Database.Extensions.Clear;
      Assert
        (not Database.Validation_Hooks.Exists ("reject_negative"),
         "clear removes validation hooks");
      Assert
        (not Database.Functions.Exists ("lower_custom"),
         "clear removes scalar functions");
   end Validation_And_Dependency_Checks;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Scalar_Functions_And_Expressions'Access,
         "scalar functions and expressions");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Aggregates_Collations_Tokenizers_Ranking'Access,
         "aggregates collations tokenizers ranking");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Validation_And_Dependency_Checks'Access,
         "validation and dependency checks");
   end Register_Tests;
end Extension_Tests;
