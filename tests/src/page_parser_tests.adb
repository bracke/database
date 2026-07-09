with AUnit.Assertions;
with Interfaces; use Interfaces;
with Database.Storage.Page_Parser;

package body Page_Parser_Tests is
   use AUnit.Assertions;
   use type Database.Storage.Page_Parser.Parse_Status;
   use type Database.Storage.Page_Parser.Page_Kind;
   use type Database.Storage.Page_Parser.Word_32;

   procedure Put_U32_LE
     (Data  : in out Database.Storage.Page_Parser.Byte_Array;
      First : Natural;
      Value : Database.Storage.Page_Parser.Word_32) is
   begin
      Data (First) :=
        Database.Storage.Page_Parser.Byte (Value and 16#0000_00FF#);
      Data (First + 1) :=
        Database.Storage.Page_Parser.Byte
          ((Value / 16#0000_0100#) and 16#0000_00FF#);
      Data (First + 2) :=
        Database.Storage.Page_Parser.Byte
          ((Value / 16#0001_0000#) and 16#0000_00FF#);
      Data (First + 3) :=
        Database.Storage.Page_Parser.Byte
          ((Value / 16#0100_0000#) and 16#0000_00FF#);
   end Put_U32_LE;

   procedure Build_Page
     (Data          : in out Database.Storage.Page_Parser.Byte_Array;
      Kind          : Database.Storage.Page_Parser.Byte;
      Page_Id       : Database.Storage.Page_Parser.Word_32;
      Previous_Page : Database.Storage.Page_Parser.Word_32;
      Next_Page     : Database.Storage.Page_Parser.Word_32;
      Page_LSN      : Database.Storage.Page_Parser.Word_32;
      Payload_First : Natural)
   is
      Used_Length : constant Database.Storage.Page_Parser.Word_32 :=
        Database.Storage.Page_Parser.Word_32
          (Data'Length - Database.Storage.Page_Parser.Header_Length);
      Payload_Sum : Database.Storage.Page_Parser.Word_32;
      Header_Sum  : Database.Storage.Page_Parser.Word_32;
   begin
      Data (0) := Database.Storage.Page_Parser.Magic_0;
      Data (1) := Database.Storage.Page_Parser.Magic_1;
      Data (2) := Database.Storage.Page_Parser.Magic_2;
      Data (3) := Database.Storage.Page_Parser.Magic_3;
      Data (4) := Database.Storage.Page_Parser.Current_Format_Version;
      Data (5) := Kind;
      Data (6) := 0;
      Data (7) := 0;
      Put_U32_LE (Data, 8, Page_Id);
      Put_U32_LE (Data, 12, Previous_Page);
      Put_U32_LE (Data, 16, Next_Page);
      Put_U32_LE (Data, 20, Used_Length);
      Put_U32_LE (Data, 24, Page_LSN);

      declare
         Payload : constant Database.Storage.Page_Parser.Byte_Array :=
           Data (Payload_First .. Data'Last);
      begin
         Payload_Sum :=
           Database.Storage.Page_Parser.Payload_Checksum (Page_Id, Payload);
      end;

      Put_U32_LE (Data, 28, Payload_Sum);
      Header_Sum :=
        Database.Storage.Page_Parser.Build_Header_Checksum (Data, Page_Id);
      Put_U32_LE (Data, 32, Header_Sum);
   end Build_Page;

   procedure Test_Valid_Page (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Short_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Bad_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Zero_Page_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Self_Link
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Stale_LSN
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Header_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Payload_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("SPARK-friendly durable page parser");
   end Name;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Valid_Page'Access, "valid page parses");
      Register_Routine
        (T, Test_Rejects_Short_Page'Access, "short page rejected");
      Register_Routine
        (T, Test_Rejects_Bad_Magic'Access, "bad page magic rejected");
      Register_Routine
        (T, Test_Rejects_Zero_Page_Id'Access, "zero page id rejected");
      Register_Routine
        (T, Test_Rejects_Self_Link'Access, "self page linkage rejected");
      Register_Routine
        (T, Test_Rejects_Stale_LSN'Access, "stale page LSN rejected");
      Register_Routine
        (T, Test_Rejects_Header_Tamper'Access, "page header tamper rejected");
      Register_Routine
        (T,
         Test_Rejects_Payload_Tamper'Access,
         "page payload tamper rejected");
   end Register_Tests;

   procedure Test_Valid_Page (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Data (37) := 2;
      Data (38) := 3;
      Data (39) := 4;
      Build_Page (Data, 3, 7, 6, 8, 10, 36);

      Database.Storage.Page_Parser.Validate_Page (Data, 5, Header, Status);

      Assert
        (Status = Database.Storage.Page_Parser.Parse_OK,
         "valid page should parse");
      Assert
        (Header.Kind = Database.Storage.Page_Parser.Heap_Page,
         "kind should decode");
      Assert (Header.Page_Id = 7, "page id should decode");
      Assert (Header.Used_Length = 4, "used length should decode");
   end Test_Valid_Page;

   procedure Test_Rejects_Short_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : constant Database.Storage.Page_Parser.Byte_Array (0 .. 5) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Page_Too_Short,
         "short page must be rejected");
   end Test_Rejects_Short_Page;

   procedure Test_Rejects_Bad_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Build_Page (Data, 3, 7, 0, 0, 10, 36);
      Data (0) := 0;

      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Invalid_Magic,
         "bad magic must be rejected");
   end Test_Rejects_Bad_Magic;

   procedure Test_Rejects_Zero_Page_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Build_Page (Data, 3, 0, 0, 0, 10, 36);

      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Invalid_Page_Id,
         "zero page id must be rejected");
   end Test_Rejects_Zero_Page_Id;

   procedure Test_Rejects_Self_Link
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Build_Page (Data, 3, 7, 7, 0, 10, 36);

      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Invalid_Linkage,
         "self link must be rejected");
   end Test_Rejects_Self_Link;

   procedure Test_Rejects_Stale_LSN
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Build_Page (Data, 3, 7, 0, 0, 10, 36);

      Database.Storage.Page_Parser.Validate_Page (Data, 11, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Page_LSN_Order_Violation,
         "stale page LSN must be rejected");
   end Test_Rejects_Stale_LSN;

   procedure Test_Rejects_Header_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Build_Page (Data, 3, 7, 0, 0, 10, 36);
      Data (16) := Data (16) + 1;

      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Header_Checksum_Mismatch,
         "header mutation must be rejected");
   end Test_Rejects_Header_Tamper;

   procedure Test_Rejects_Payload_Tamper
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Database.Storage.Page_Parser.Byte_Array (0 .. 39) :=
        [others => 0];
      Header : Database.Storage.Page_Parser.Page_Header;
      Status : Database.Storage.Page_Parser.Parse_Status;
   begin
      Data (36) := 1;
      Build_Page (Data, 3, 7, 0, 0, 10, 36);
      Data (36) := Data (36) + 1;

      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Payload_Checksum_Mismatch,
         "payload mutation must be rejected");
   end Test_Rejects_Payload_Tamper;

end Page_Parser_Tests;
