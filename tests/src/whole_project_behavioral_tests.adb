with AUnit.Assertions;
with Interfaces; use Interfaces;
with Database.Status;
with Database.Checksums;
with Database.WAL.Frame_Parser;
with Database.Storage.Page_Parser;
with Database.Storage.Record_Serializer;
with Database.Storage.Free_List_Manager;
with Database.Indexes.BTree_Invariants;

package body Whole_Project_Behavioral_Tests is
   use AUnit.Assertions;
   procedure Test_Checksum_Tamper_Rejection
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_WAL_Frame_Parser_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Page_Parser_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Record_Serializer_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Free_List_Manager_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_BTree_Invariant_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return
        AUnit.Format ("whole-project behavioral support and hardening tests");
   end Name;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Checksum_Tamper_Rejection'Access,
         "checksums accept original data and reject tamper");
      Register_Routine
        (T,
         Test_WAL_Frame_Parser_Behavior'Access,
         "WAL frame parser rejects malformed durable frames");
      Register_Routine
        (T,
         Test_Page_Parser_Behavior'Access,
         "page parser rejects malformed durable pages");
      Register_Routine
        (T,
         Test_Record_Serializer_Behavior'Access,
         "record serializer builds and rejects invalid spans");
      Register_Routine
        (T,
         Test_Free_List_Manager_Behavior'Access,
         "free-list manager preserves sorted unique page ids");
      Register_Routine
        (T,
         Test_BTree_Invariant_Behavior'Access,
         "B+ tree invariant checker rejects structural faults");
   end Register_Tests;

   procedure Test_Checksum_Tamper_Rejection
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.Checksums.Word_32;
      Original : constant Database.Checksums.Byte_Array (0 .. 3) :=
        [1, 2, 3, 4];
      Tampered : constant Database.Checksums.Byte_Array (0 .. 3) :=
        [1, 2, 3, 5];
      Sum      : constant Database.Checksums.Word_32 :=
        Database.Checksums.Page_Checksum (42, Original);
   begin
      Assert
        (Database.Checksums.Verify_Page_Checksum (42, Original, Sum),
         "original page-bound checksum must verify");
      Assert
        (not Database.Checksums.Verify_Page_Checksum (42, Tampered, Sum),
         "tampered page payload must not verify");
      Assert
        (not Database.Checksums.Verify_Page_Checksum (43, Original, Sum),
         "same payload on different page id must not verify");
   end Test_Checksum_Tamper_Rejection;

   procedure Put_U32_WAL
     (Data  : in out Database.WAL.Frame_Parser.Byte_Array;
      First : Natural;
      Value : Database.WAL.Frame_Parser.Word_32)
   is
      use type Database.WAL.Frame_Parser.Word_32;
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
   end Put_U32_WAL;

   procedure Test_WAL_Frame_Parser_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.WAL.Frame_Parser.Parse_Status;
      Data        : Database.WAL.Frame_Parser.Byte_Array (0 .. 33) :=
        [others => 0];
      Header      : Database.WAL.Frame_Parser.Frame_Header;
      Status      : Database.WAL.Frame_Parser.Parse_Status;
      Payload_Sum : Database.WAL.Frame_Parser.Word_32;
      Header_Sum  : Database.WAL.Frame_Parser.Word_32;
      Payload     : constant Database.WAL.Frame_Parser.Byte_Array (32 .. 33) :=
        [32 => 10, 33 => 20];
   begin
      Database.WAL.Frame_Parser.Validate_Frame (Data, 0, Header, Status);
      Assert
        (Status = Database.WAL.Frame_Parser.Invalid_Magic,
         "zero-filled WAL frame must reject invalid magic");

      Data (0) := Database.WAL.Frame_Parser.Magic_0;
      Data (1) := Database.WAL.Frame_Parser.Magic_1;
      Data (2) := Database.WAL.Frame_Parser.Magic_2;
      Data (3) := Database.WAL.Frame_Parser.Magic_3;
      Data (4) := Database.WAL.Frame_Parser.Current_Format_Version;
      Data (5) := 1;
      Put_U32_WAL (Data, 8, 9);
      Put_U32_WAL (Data, 12, 8);
      Put_U32_WAL (Data, 16, 7);
      Put_U32_WAL (Data, 20, 2);
      Data (32) := Payload (32);
      Data (33) := Payload (33);
      Payload_Sum := Database.WAL.Frame_Parser.Payload_Checksum (7, Payload);
      Put_U32_WAL (Data, 24, Payload_Sum);
      Header_Sum := Database.WAL.Frame_Parser.Build_Header_Checksum (Data, 9);
      Put_U32_WAL (Data, 28, Header_Sum);

      Database.WAL.Frame_Parser.Validate_Frame (Data, 8, Header, Status);
      Assert
        (Status = Database.WAL.Frame_Parser.Parse_OK,
         "well-formed WAL frame must validate");

      Data (33) := Data (33) + 1;
      Database.WAL.Frame_Parser.Validate_Frame (Data, 8, Header, Status);
      Assert
        (Status = Database.WAL.Frame_Parser.Payload_Checksum_Mismatch,
         "payload tamper must be rejected");
   end Test_WAL_Frame_Parser_Behavior;

   procedure Put_U32_Page
     (Data  : in out Database.Storage.Page_Parser.Byte_Array;
      First : Natural;
      Value : Database.Storage.Page_Parser.Word_32)
   is
      use type Database.Storage.Page_Parser.Word_32;
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
   end Put_U32_Page;

   procedure Test_Page_Parser_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.Storage.Page_Parser.Parse_Status;
      Data        : Database.Storage.Page_Parser.Byte_Array (0 .. 37) :=
        [others => 0];
      Header      : Database.Storage.Page_Parser.Page_Header;
      Status      : Database.Storage.Page_Parser.Parse_Status;
      Payload     :
        constant Database.Storage.Page_Parser.Byte_Array (36 .. 37) :=
          [36 => 1, 37 => 2];
      Payload_Sum : Database.Storage.Page_Parser.Word_32;
      Header_Sum  : Database.Storage.Page_Parser.Word_32;
   begin
      Database.Storage.Page_Parser.Validate_Page (Data, 0, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Invalid_Magic,
         "zero-filled page must reject invalid magic");

      Data (0) := Database.Storage.Page_Parser.Magic_0;
      Data (1) := Database.Storage.Page_Parser.Magic_1;
      Data (2) := Database.Storage.Page_Parser.Magic_2;
      Data (3) := Database.Storage.Page_Parser.Magic_3;
      Data (4) := Database.Storage.Page_Parser.Current_Format_Version;
      Data (5) := 3;
      Put_U32_Page (Data, 8, 5);
      Put_U32_Page (Data, 12, 0);
      Put_U32_Page (Data, 16, 0);
      Put_U32_Page (Data, 20, 2);
      Put_U32_Page (Data, 24, 12);
      Data (36) := Payload (36);
      Data (37) := Payload (37);
      Payload_Sum :=
        Database.Storage.Page_Parser.Payload_Checksum (5, Payload);
      Put_U32_Page (Data, 28, Payload_Sum);
      Header_Sum :=
        Database.Storage.Page_Parser.Build_Header_Checksum (Data, 5);
      Put_U32_Page (Data, 32, Header_Sum);

      Database.Storage.Page_Parser.Validate_Page (Data, 10, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Parse_OK,
         "well-formed page must validate");

      Data (12) := 5;
      Database.Storage.Page_Parser.Validate_Page (Data, 10, Header, Status);
      Assert
        (Status = Database.Storage.Page_Parser.Invalid_Linkage,
         "self-linking page must be rejected before acceptance");
   end Test_Page_Parser_Behavior;

   procedure Test_Record_Serializer_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.Storage.Record_Serializer.Parse_Status;
      Payload     :
        constant Database.Storage.Record_Serializer.Byte_Array (0 .. 2) :=
          [1, 2, 3];
      Good_Fields :
        constant Database.Storage.Record_Serializer.Field_Span_Array
                   (0 .. 1) :=
          [(Offset => 0, Length => 1), (Offset => 1, Length => 2)];
      Bad_Fields  :
        constant Database.Storage.Record_Serializer.Field_Span_Array
                   (0 .. 1) :=
          [(Offset => 2, Length => 1), (Offset => 1, Length => 1)];
      Output      : Database.Storage.Record_Serializer.Byte_Array (0 .. 64) :=
        [others => 0];
      Header      : Database.Storage.Record_Serializer.Record_Header;
      Status      : Database.Storage.Record_Serializer.Parse_Status;
   begin
      Database.Storage.Record_Serializer.Build_Record
        (Payload, Good_Fields, Output, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Parse_OK,
         "valid field spans must build");

      Database.Storage.Record_Serializer.Validate_Record (Output, Header, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Parse_OK,
         "built record must validate");

      Database.Storage.Record_Serializer.Build_Record
        (Payload, Bad_Fields, Output, Status);
      Assert
        (Status = Database.Storage.Record_Serializer.Field_Order_Violation,
         "out-of-order field spans must reject");
   end Test_Record_Serializer_Behavior;

   procedure Test_Free_List_Manager_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.Storage.Free_List_Manager.Operation_Status;
      use type Database.Storage.Free_List_Manager.Validation_Status;
      use type Database.Storage.Free_List_Manager.Page_Id_Type;
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
      Page   : Database.Storage.Free_List_Manager.Page_Id_Type;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 8, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK,
         "adding page 8 must succeed");
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 4, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK,
         "adding page 4 must succeed");

      Assert
        (List.Pages (1) = 4 and then List.Pages (2) = 8,
         "free-list must maintain sorted order");
      Assert
        (Database.Storage.Free_List_Manager.Validate (List, 2, 100)
         = Database.Storage.Free_List_Manager.Valid,
         "free-list must validate after inserts");

      Database.Storage.Free_List_Manager.Allocate_Free_Page
        (List, 2, 100, Page, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK,
         "allocation from non-empty free-list must succeed");
      Assert (Page = 8, "deterministic allocation returns highest free page");
   end Test_Free_List_Manager_Behavior;

   procedure Test_BTree_Invariant_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Database.Indexes.BTree_Invariants.Validation_Status;
      Tree : Database.Indexes.BTree_Invariants.Tree_Descriptor :=
        (Root_Page_Id => 1, Node_Count => 1, Nodes => [others => <>]);
   begin
      Tree.Nodes (1).Page_Id := 1;
      Tree.Nodes (1).Kind := Database.Indexes.BTree_Invariants.Leaf_Node;
      Tree.Nodes (1).Depth := 0;
      Tree.Nodes (1).Key_Count := 2;
      Tree.Nodes (1).Keys (1) := 10;
      Tree.Nodes (1).Keys (2) := 20;

      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Valid,
         "single-leaf tree must validate");

      Tree.Nodes (1).Keys (1) := 30;
      Assert
        (Database.Indexes.BTree_Invariants.Validate_Tree (Tree)
         = Database.Indexes.BTree_Invariants.Keys_Not_Strictly_Sorted,
         "unsorted leaf keys must reject");
   end Test_BTree_Invariant_Behavior;

end Whole_Project_Behavioral_Tests;
