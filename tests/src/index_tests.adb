with AUnit.Assertions;

with Database; use Database;
with Database.Indexes; use Database.Indexes;
with Database.Status; use Database.Status;
with Database.Types;
with Database.Values;

package body Index_Tests is
   use AUnit.Assertions;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("primary key indexes");
   end Name;

   procedure Key_Comparison (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      O : Database.Indexes.Ordering;
      R : Database.Status.Result;
   begin
      R :=
        Database.Indexes.Compare
          (Database.Values.From_Integer (1),
           Database.Values.From_Integer (2),
           O);
      Assert
        (Database.Status.Is_Ok (R) and then O = Database.Indexes.Less,
         "integer comparison failed");
      R :=
        Database.Indexes.Compare
          (Database.Values.From_Decimal ((Coefficient => 10, Scale => 1)),
           Database.Values.From_Decimal ((Coefficient => 100, Scale => 2)),
           O);
      Assert
        (Database.Status.Is_Ok (R) and then O = Database.Indexes.Equal,
         "decimal scale normalization failed");
      R :=
        Database.Indexes.Compare
          (Database.Values.From_Text ("abc"),
           Database.Values.From_Text ("abd"),
           O);
      Assert
        (Database.Status.Is_Ok (R) and then O = Database.Indexes.Less,
         "text comparison failed");
   end Key_Comparison;

   procedure Unsupported_Keys (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Database.Status.Result;
      B : Database.Values.Byte_Vectors.Vector;
   begin
      R := Database.Indexes.Validate_Key (Database.Values.Null_Value);
      Assert (not Database.Status.Is_Ok (R), "null primary key accepted");
      R := Database.Indexes.Validate_Key (Database.Values.From_Blob (B));
      Assert
        (R.Code = Database.Status.Unsupported_Key_Type,
         "blob primary key accepted");
      Assert
        (not Database.Indexes.Supports_Key (Database.Types.Blob_Value),
         "blob key reported supported");
   end Unsupported_Keys;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Key_Comparison'Access, "typed key comparison");
      Register_Routine
        (T, Unsupported_Keys'Access, "unsupported primary key kinds rejected");
   end Register_Tests;
end Index_Tests;
