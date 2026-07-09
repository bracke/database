with AUnit.Assertions;

with Database.Storage.Record_Serializer;

package body Record_Serializer_Tests is
   use AUnit.Assertions;
   use type Database.Storage.Record_Serializer.Parse_Status;

   procedure Test_Build_And_Parse_Record (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Bad_Magic (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Reserved_Bytes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Truncated_Directory (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Field_Out_Of_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Field_Order_Violation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Small_Output_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("SPARK-friendly record serialization");
   end Name;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Build_And_Parse_Record'Access, "build and parse deterministic record");
      Register_Routine (T, Test_Rejects_Bad_Magic'Access, "bad record magic rejected");
      Register_Routine (T, Test_Rejects_Reserved_Bytes'Access, "reserved record bytes rejected");
      Register_Routine (T, Test_Rejects_Truncated_Directory'Access, "truncated directory rejected");
      Register_Routine (T, Test_Rejects_Field_Out_Of_Bounds'Access, "field bounds rejected");
      Register_Routine (T, Test_Rejects_Field_Order_Violation'Access, "field order rejected");
      Register_Routine (T, Test_Rejects_Small_Output_Buffer'Access, "small output buffer rejected");
   end Register_Tests;

   procedure Test_Build_And_Parse_Record (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Database.Storage.Record_Serializer.Byte_Array (0 .. 5) :=
        (10, 20, 30, 40, 50, 60);
      Fields : constant Database.Storage.Record_Serializer.Field_Span_Array (0 .. 1) :=
        ((Offset => 0, Length => 2),
         (Offset => 2, Length => 4));
      Output : Database.Storage.Record_Serializer.Byte_Array
        (0 .. Database.Storage.Record_Serializer.Encoded_Length (2, 6) - 1) :=
        (others => 0);
      Header : Database.Storage.Record_Serializer.Record_Header;
      Span   : Database.Storage.Record_Serializer.Field_Span;
      Status : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Build_Record
        (Payload, Fields, Output, Status);
      Assert (Status = Database.Storage.Record_Serializer.Parse_OK,
              "record build should succeed");

      Database.Storage.Record_Serializer.Validate_Record (Output, Header, Status);
      Assert (Status = Database.Storage.Record_Serializer.Parse_OK,
              "record parse should succeed");
      Assert (Header.Field_Count = 2,
              "field count should round trip");
      Assert (Header.Payload_Length = 6,
              "payload length should round trip");

      Database.Storage.Record_Serializer.Read_Field_Span
        (Output, Header, 1, Span, Status);
      Assert (Status = Database.Storage.Record_Serializer.Parse_OK,
              "field span should be readable");
      Assert (Span.Offset = 2 and then Span.Length = 4,
              "field span should round trip");
   end Test_Build_And_Parse_Record;

   procedure Test_Rejects_Bad_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data   : Database.Storage.Record_Serializer.Byte_Array (0 .. 11) := (others => 0);
      Header : Database.Storage.Record_Serializer.Record_Header;
      Status : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Validate_Record (Data, Header, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Invalid_Magic,
         "bad magic must be rejected");
   end Test_Rejects_Bad_Magic;

   procedure Test_Rejects_Reserved_Bytes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Database.Storage.Record_Serializer.Byte_Array (0 .. 0) := (0 => 0);
      Fields  : constant Database.Storage.Record_Serializer.Field_Span_Array (0 .. 0) :=
        (0 => (Offset => 0, Length => 0));
      Output  : Database.Storage.Record_Serializer.Byte_Array
        (0 .. Database.Storage.Record_Serializer.Encoded_Length (1, 1) - 1) :=
        (others => 0);
      Header  : Database.Storage.Record_Serializer.Record_Header;
      Status  : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Build_Record
        (Payload, Fields, Output, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Parse_OK,
         "build should succeed");
      Output (6) := 1;
      Database.Storage.Record_Serializer.Validate_Record (Output, Header, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Invalid_Reserved_Bytes,
         "reserved bytes must be zero");
   end Test_Rejects_Reserved_Bytes;

   procedure Test_Rejects_Truncated_Directory (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data   : Database.Storage.Record_Serializer.Byte_Array (0 .. 13) := (others => 0);
      Header : Database.Storage.Record_Serializer.Record_Header;
      Status : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Data (0) := Database.Storage.Record_Serializer.Magic_0;
      Data (1) := Database.Storage.Record_Serializer.Magic_1;
      Data (2) := Database.Storage.Record_Serializer.Magic_2;
      Data (3) := Database.Storage.Record_Serializer.Magic_3;
      Data (4) := Database.Storage.Record_Serializer.Current_Format_Version;
      Data (5) := 1;
      Database.Storage.Record_Serializer.Validate_Record (Data, Header, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Directory_Out_Of_Bounds,
         "truncated directory must be rejected");
   end Test_Rejects_Truncated_Directory;

   procedure Test_Rejects_Field_Out_Of_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Database.Storage.Record_Serializer.Byte_Array (0 .. 2) := (1, 2, 3);
      Fields  : constant Database.Storage.Record_Serializer.Field_Span_Array (0 .. 0) :=
        (0 => (Offset => 2, Length => 2));
      Output  : Database.Storage.Record_Serializer.Byte_Array (0 .. 31) := (others => 0);
      Status  : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Build_Record
        (Payload, Fields, Output, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Field_Out_Of_Bounds,
         "field beyond payload must be rejected");
   end Test_Rejects_Field_Out_Of_Bounds;

   procedure Test_Rejects_Field_Order_Violation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Database.Storage.Record_Serializer.Byte_Array (0 .. 5) :=
        (1, 2, 3, 4, 5, 6);
      Fields  : constant Database.Storage.Record_Serializer.Field_Span_Array (0 .. 1) :=
        ((Offset => 3, Length => 2),
         (Offset => 2, Length => 2));
      Output  : Database.Storage.Record_Serializer.Byte_Array (0 .. 64) := (others => 0);
      Status  : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Build_Record
        (Payload, Fields, Output, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Field_Order_Violation,
         "overlapping/out-of-order fields must be rejected");
   end Test_Rejects_Field_Order_Violation;

   procedure Test_Rejects_Small_Output_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Database.Storage.Record_Serializer.Byte_Array (0 .. 5) :=
        (1, 2, 3, 4, 5, 6);
      Fields  : constant Database.Storage.Record_Serializer.Field_Span_Array (0 .. 0) :=
        (0 => (Offset => 0, Length => 6));
      Output  : Database.Storage.Record_Serializer.Byte_Array (0 .. 5) := (others => 0);
      Status  : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Build_Record
        (Payload, Fields, Output, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Output_Buffer_Too_Small,
         "undersized output buffer must be rejected");
   end Test_Rejects_Small_Output_Buffer;

end Record_Serializer_Tests;
