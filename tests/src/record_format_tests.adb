with AUnit.Assertions;

with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Record_Format;
with Database.Types;
with Database.Values;
with Database.Storage.Pages;

package body Record_Format_Tests is
   use AUnit.Assertions;
   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("record format");
   end Name;

   procedure Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      S      : Database.Schema.Table_Schema;
      R1, R2 : Database.Rows.Row;
      Enc    : Database.Storage.Record_Format.Byte_Vector;
      Res    : Database.Status.Result;
      Blob   : Database.Values.Byte_Vectors.Vector;
   begin
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column
        (S, "active", Database.Types.Boolean_Value, False);
      Database.Schema.Add_Column
        (S, "amount", Database.Types.Decimal_Value, False);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (S, "blob", Database.Types.Blob_Value, False);
      Blob.Append (16#C0#);
      Blob.Append (16#FF#);
      Blob.Append (16#EE#);
      Database.Rows.Append (R1, Database.Values.From_Integer (1));
      Database.Rows.Append (R1, Database.Values.From_Boolean (True));
      Database.Rows.Append
        (R1,
         Database.Values.From_Decimal ((Coefficient => 12345, Scale => 2)));
      Database.Rows.Append (R1, Database.Values.From_Text ("Grüße 😀"));
      Database.Rows.Append (R1, Database.Values.From_Blob (Blob));
      Res := Database.Storage.Record_Format.Serialize (S, R1, Enc);
      Assert (Database.Status.Is_Ok (Res), "serialize failed");
      Assert (Enc.Last > 0, "serialized record must not be empty");
      declare
         D : Database.Storage.Pages.Byte_Array (0 .. Enc.Last - 1);
      begin
         for I in D'Range loop
            D (I) := Enc.Data (I);
         end loop;
         Res := Database.Storage.Record_Format.Deserialize (S, D, R2);
      end;
      Assert (Database.Status.Is_Ok (Res), "deserialize failed");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (R1, 2), Database.Rows.Get (R2, 2)),
         "decimal exactness lost");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (R1, 3), Database.Rows.Get (R2, 3)),
         "unicode text round trip failed");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (R1, 4), Database.Rows.Get (R2, 4)),
         "blob round trip failed");
   end Round_Trip;

   procedure Malformed_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S   : Database.Schema.Table_Schema;
      R   : Database.Rows.Row;
      D   : Database.Storage.Pages.Byte_Array (0 .. 1) := (0, 1);
      Res : Database.Status.Result;
   begin
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Res := Database.Storage.Record_Format.Deserialize (S, D, R);
      Assert (not Database.Status.Is_Ok (Res), "truncated record accepted");
   end Malformed_Rejected;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Round_Trip'Access, "all supported values round trip");
      Register_Routine
        (T, Malformed_Rejected'Access, "malformed record rejected");
   end Register_Tests;
end Record_Format_Tests;
