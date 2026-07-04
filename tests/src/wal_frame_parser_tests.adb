with AUnit.Assertions;
with Interfaces; use Interfaces;
with Database.WAL.Frame_Parser;

package body WAL_Frame_Parser_Tests is
   use AUnit.Assertions;
   use type Database.WAL.Frame_Parser.Parse_Status;
   use type Database.WAL.Frame_Parser.Frame_Kind;
   use type Database.WAL.Frame_Parser.Word_32;

   procedure Put_U32_LE
     (Data  : in out Database.WAL.Frame_Parser.Byte_Array;
      First : Natural;
      Value : Database.WAL.Frame_Parser.Word_32) is
   begin
      Data (First) := Database.WAL.Frame_Parser.Byte (Value and 16#0000_00FF#);
      Data (First + 1) :=
        Database.WAL.Frame_Parser.Byte
          ((Value / 16#0000_0100#) and 16#0000_00FF#);
      Data (First + 2) :=
        Database.WAL.Frame_Parser.Byte
          ((Value / 16#0001_0000#) and 16#0000_00FF#);
      Data (First + 3) :=
        Database.WAL.Frame_Parser.Byte
          ((Value / 16#0100_0000#) and 16#0000_00FF#);
   end Put_U32_LE;

   procedure Build_Frame
     (Data          : in out Database.WAL.Frame_Parser.Byte_Array;
      Kind          : Database.WAL.Frame_Parser.Byte;
      Seq           : Database.WAL.Frame_Parser.Word_32;
      Previous      : Database.WAL.Frame_Parser.Word_32;
      Page_Id       : Database.WAL.Frame_Parser.Word_32;
      Payload_First : Natural)
   is
      Payload_Length : constant Database.WAL.Frame_Parser.Word_32 :=
        Database.WAL.Frame_Parser.Word_32
          (Data'Length - Database.WAL.Frame_Parser.Header_Length);
      Payload_Sum    : Database.WAL.Frame_Parser.Word_32;
      Header_Sum     : Database.WAL.Frame_Parser.Word_32;
   begin
      Data (0) := Database.WAL.Frame_Parser.Magic_0;
      Data (1) := Database.WAL.Frame_Parser.Magic_1;
      Data (2) := Database.WAL.Frame_Parser.Magic_2;
      Data (3) := Database.WAL.Frame_Parser.Magic_3;
      Data (4) := Database.WAL.Frame_Parser.Current_Format_Version;
      Data (5) := Kind;
      Data (6) := 0;
      Data (7) := 0;
      Put_U32_LE (Data, 8, Seq);
      Put_U32_LE (Data, 12, Previous);
      Put_U32_LE (Data, 16, Page_Id);
      Put_U32_LE (Data, 20, Payload_Length);

      declare
         Payload : constant Database.WAL.Frame_Parser.Byte_Array :=
           Data (Payload_First .. Data'Last);
      begin
         Payload_Sum :=
           Database.WAL.Frame_Parser.Payload_Checksum (Page_Id, Payload);
      end;

      Put_U32_LE (Data, 24, Payload_Sum);
      Header_Sum :=
        Database.WAL.Frame_Parser.Build_Header_Checksum (Data, Seq);
      Put_U32_LE (Data, 28, Header_Sum);
   end Build_Frame;

   procedure Test_Valid_Frame (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Short_Frame
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Bad_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_LSN_Order_Violation
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Header_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Payload_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("SPARK-friendly WAL frame parser");
   end Name;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Valid_Frame'Access, "valid WAL frame parses");
      Register_Routine
        (T, Test_Rejects_Short_Frame'Access, "short WAL frame rejected");
      Register_Routine
        (T, Test_Rejects_Bad_Magic'Access, "bad WAL magic rejected");
      Register_Routine
        (T,
         Test_Rejects_LSN_Order_Violation'Access,
         "LSN ordering violation rejected");
      Register_Routine
        (T, Test_Rejects_Header_Tamper'Access, "header tamper rejected");
      Register_Routine
        (T, Test_Rejects_Payload_Tamper'Access, "payload tamper rejected");
   end Register_Tests;

   procedure Test_Valid_Frame (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data   : Database.WAL.Frame_Parser.Byte_Array (0 .. 35) := [others => 0];
      Header : Database.WAL.Frame_Parser.Frame_Header;
      Status : Database.WAL.Frame_Parser.Parse_Status;
   begin
      Data (32) := 10;
      Data (33) := 20;
      Data (34) := 30;
      Data (35) := 40;
      Build_Frame (Data, 1, 5, 4, 9, 32);

      Status := Database.WAL.Frame_Parser.Validate_Frame (Data, 4, Header);

      Assert
        (Status = Database.WAL.Frame_Parser.Parse_OK,
         "valid frame should parse");
      Assert
        (Header.Kind = Database.WAL.Frame_Parser.Page_Image,
         "kind should decode");
      Assert (Header.Sequence = 5, "sequence should decode");
      Assert (Header.Payload_Length = 4, "payload length should decode");
   end Test_Valid_Frame;

   procedure Test_Rejects_Short_Frame
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.WAL.Frame_Parser.Byte_Array (0 .. 4) := [others => 0];
      Header : Database.WAL.Frame_Parser.Frame_Header;
   begin
      Assert
        (Database.WAL.Frame_Parser.Validate_Frame (Data, 0, Header)
         = Database.WAL.Frame_Parser.Frame_Too_Short,
         "short frame must be rejected");
   end Test_Rejects_Short_Frame;

   procedure Test_Rejects_Bad_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.WAL.Frame_Parser.Byte_Array (0 .. 35) := [others => 0];
      Header : Database.WAL.Frame_Parser.Frame_Header;
   begin
      Data (32) := 1;
      Build_Frame (Data, 1, 1, 0, 1, 32);
      Data (0) := 0;

      Assert
        (Database.WAL.Frame_Parser.Validate_Frame (Data, 0, Header)
         = Database.WAL.Frame_Parser.Invalid_Magic,
         "bad magic must be rejected");
   end Test_Rejects_Bad_Magic;

   procedure Test_Rejects_LSN_Order_Violation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.WAL.Frame_Parser.Byte_Array (0 .. 35) := [others => 0];
      Header : Database.WAL.Frame_Parser.Frame_Header;
   begin
      Data (32) := 1;
      Build_Frame (Data, 1, 3, 2, 1, 32);

      Assert
        (Database.WAL.Frame_Parser.Validate_Frame (Data, 99, Header)
         = Database.WAL.Frame_Parser.LSN_Order_Violation,
         "unexpected previous LSN must be rejected");
   end Test_Rejects_LSN_Order_Violation;

   procedure Test_Rejects_Header_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.WAL.Frame_Parser.Byte_Array (0 .. 35) := [others => 0];
      Header : Database.WAL.Frame_Parser.Frame_Header;
   begin
      Data (32) := 1;
      Build_Frame (Data, 1, 3, 2, 1, 32);
      Data (16) := Data (16) + 1;

      Assert
        (Database.WAL.Frame_Parser.Validate_Frame (Data, 2, Header)
         = Database.WAL.Frame_Parser.Header_Checksum_Mismatch,
         "header mutation must be rejected");
   end Test_Rejects_Header_Tamper;

   procedure Test_Rejects_Payload_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.WAL.Frame_Parser.Byte_Array (0 .. 35) := [others => 0];
      Header : Database.WAL.Frame_Parser.Frame_Header;
   begin
      Data (32) := 1;
      Build_Frame (Data, 1, 3, 2, 1, 32);
      Data (32) := Data (32) + Database.WAL.Frame_Parser.Byte (1);

      Assert
        (Database.WAL.Frame_Parser.Validate_Frame (Data, 2, Header)
         = Database.WAL.Frame_Parser.Payload_Checksum_Mismatch,
         "payload mutation must be rejected");
   end Test_Rejects_Payload_Tamper;

end WAL_Frame_Parser_Tests;
