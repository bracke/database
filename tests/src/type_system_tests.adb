with AUnit.Assertions;

with Ada.Strings.Wide_Wide_Unbounded;
with Database; use Database;
with Database.Constraints;
with Database.Date_Time;
with Database.Expressions;
with Database.Ordering;
with Database.Rows;
with Database.Schema;
with Database.Status; use Database.Status;
with Database.Storage.Pages;
with Database.Storage.Record_Format;
with Database.Type_Metadata;
with Database.Types;
with Database.UUIDs;
with Database.Values;

package body Type_System_Tests is
   use AUnit.Assertions;
   use Ada.Strings.Wide_Wide_Unbounded;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("type system");
   end Name;

   procedure Date_Time_UUID_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S      : Database.Schema.Table_Schema;
      R1, R2 : Database.Rows.Row;
      Enc    : Database.Storage.Record_Format.Byte_Vector;
      Res    : Database.Status.Result;
      U      : Database.UUIDs.UUID;
   begin
      Assert
        (Database.Status.Is_Ok
           (Database.UUIDs.Parse_UUID
              ("00112233-4455-6677-8899-aabbccddeeff", U)),
         "uuid parses");
      Database.Schema.Add_Column (S, "d", Database.Types.Date_Value, False);
      Database.Schema.Add_Column (S, "t", Database.Types.Time_Value, False);
      Database.Schema.Add_Column
        (S, "dt", Database.Types.Date_Time_Value, False);
      Database.Schema.Add_Column
        (S, "du", Database.Types.Duration_Value, False);
      Database.Schema.Add_Column (S, "uuid", Database.Types.UUID_Value, False);
      Database.Rows.Append
        (R1,
         Database.Values.From_Date ((Year => 2026, Month => 5, Day => 10)));
      Database.Rows.Append
        (R1,
         Database.Values.From_Time
           ((Hour => 20, Minute => 30, Second => 1, Nanosecond => 2)));
      Database.Rows.Append
        (R1,
         Database.Values.From_Date_Time
           ((Date_Part => (Year => 2026, Month => 5, Day => 10),
             Time_Part =>
               (Hour => 20, Minute => 30, Second => 1, Nanosecond => 2))));
      Database.Rows.Append
        (R1,
         Database.Values.From_Duration ((Seconds => 90, Nanoseconds => 5)));
      Database.Rows.Append (R1, Database.Values.From_UUID (U));
      Res := Database.Storage.Record_Format.Serialize (S, R1, Enc);
      Assert (Database.Status.Is_Ok (Res), "new types serialize");
      Assert (Enc.Last > 0, "serialized record must not be empty");
      declare
         D : Database.Storage.Pages.Byte_Array (0 .. Enc.Last - 1);
      begin
         for I in D'Range loop
            D (I) := Enc.Data (I);
         end loop;
         Res := Database.Storage.Record_Format.Deserialize (S, D, R2);
      end;
      Assert (Database.Status.Is_Ok (Res), "new types deserialize");
      for I in 0 .. 4 loop
         Assert
           (Database.Values.Equal
              (Database.Rows.Get (R1, I), Database.Rows.Get (R2, I)),
            "new value round trip failed");
      end loop;
      Assert
        (Database.UUIDs.UUID_To_String (U)
         = "00112233-4455-6677-8899-aabbccddeeff",
         "uuid canonical format");
   end Date_Time_UUID_Round_Trip;

   procedure Metadata_Validation (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S   : Database.Schema.Table_Schema;
      Row : Database.Rows.Row;
      R   : Database.Status.Result;
      E   : Database.Type_Metadata.Enum_Descriptor;
   begin
      Database.Schema.Add_Column
        (S, "amount", Database.Types.Decimal_Value, False);
      S.Columns.Reference (0).Type_Info :=
        Database.Types.Decimal_Descriptor (5, 2);
      Database.Rows.Append
        (Row,
         Database.Values.From_Decimal ((Coefficient => 12345, Scale => 2)));
      R := Database.Constraints.Validate_Row (S, Row);
      Assert (Database.Status.Is_Ok (R), "decimal precision accepted");
      Row.Values.Replace_Element
        (0,
         Database.Values.From_Decimal ((Coefficient => 123456, Scale => 2)));
      R := Database.Constraints.Validate_Row (S, Row);
      Assert
        (R.Code = Database.Status.Decimal_Overflow,
         "decimal overflow rejected");

      E.Name := To_Unbounded_Wide_Wide_String ("state");
      E.Literals.Append
        (Database.Type_Metadata.Enum_Literal'(Name => To_Unbounded_Wide_Wide_String ("Open"), Ordinal => 0));
      E.Literals.Append
        (Database.Type_Metadata.Enum_Literal'(Name => To_Unbounded_Wide_Wide_String ("Closed"), Ordinal => 1));
      Assert
        (Database.Status.Is_Ok (Database.Type_Metadata.Validate_Enum (E)),
         "enum metadata valid");
      Assert
        (Database.Type_Metadata.Contains_Literal (E, "Closed"),
         "enum literal found");
   end Metadata_Validation;

   procedure Expressions_And_Ordering
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expr : Database.Expressions.Expression;
      V    : Database.Values.Value;
      R    : Database.Status.Result;
      S    : Database.Schema.Table_Schema;
      Row  : Database.Rows.Row;
   begin
      Expr :=
        Database.Expressions.Binary
          (Database.Expressions.Add_Expr,
           Database.Expressions.Literal
             (Database.Values.From_Date_Time
                ((Date_Part => (Year => 2026, Month => 5, Day => 10),
                  Time_Part =>
                    (Hour => 1, Minute => 0, Second => 0, Nanosecond => 0)))),
           Database.Expressions.Literal
             (Database.Values.From_Duration
                ((Seconds => 3600, Nanoseconds => 0))));
      R := Database.Expressions.Evaluate (Expr, S, Row, V);
      Assert (Database.Status.Is_Ok (R), "date_time plus duration evaluates");
      Assert (V.Date_Time.Time_Part.Hour = 2, "duration arithmetic result");
      Assert
        (Database.Ordering.Compare
           (Database.Values.From_Date ((Year => 2025, Month => 1, Day => 1)),
            Database.Values.From_Date ((Year => 2026, Month => 1, Day => 1)))
         < 0,
         "date ordering stable");
   end Expressions_And_Ordering;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Date_Time_UUID_Round_Trip'Access, "date time uuid round trip");
      Register_Routine (T, Metadata_Validation'Access, "metadata validation");
      Register_Routine
        (T, Expressions_And_Ordering'Access, "typed expressions and ordering");
   end Register_Tests;
end Type_System_Tests;
