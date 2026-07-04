with AUnit.Assertions;

with Database.Storage.Free_List_Manager;

package body Free_List_Manager_Tests is
   use AUnit.Assertions;
   use type Database.Storage.Free_List_Manager.Operation_Status;
   use type Database.Storage.Free_List_Manager.Validation_Status;
   use type Database.Storage.Free_List_Manager.Page_Id_Type;

   procedure Test_Clear_And_Validate
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Add_Keeps_Sorted_Order
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Duplicate_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Reserved_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Rejects_Out_Of_Range_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Allocate_Returns_Free_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Remove_Free_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Detects_Corrupt_Duplicate
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Detects_Corrupt_Unsorted
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("SPARK-friendly free-list management");
   end Name;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Clear_And_Validate'Access,
         "clear creates valid empty free-list");
      Register_Routine
        (T,
         Test_Add_Keeps_Sorted_Order'Access,
         "add keeps sorted unique order");
      Register_Routine
        (T, Test_Rejects_Duplicate_Page'Access, "duplicate page rejected");
      Register_Routine
        (T, Test_Rejects_Reserved_Page'Access, "reserved page rejected");
      Register_Routine
        (T,
         Test_Rejects_Out_Of_Range_Page'Access,
         "out-of-range page rejected");
      Register_Routine
        (T,
         Test_Allocate_Returns_Free_Page'Access,
         "allocate removes a free page");
      Register_Routine
        (T, Test_Remove_Free_Page'Access, "remove deletes a free page");
      Register_Routine
        (T,
         Test_Detects_Corrupt_Duplicate'Access,
         "duplicate corruption detected");
      Register_Routine
        (T,
         Test_Detects_Corrupt_Unsorted'Access,
         "unsorted corruption detected");
   end Register_Tests;

   procedure Test_Clear_And_Validate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List : Database.Storage.Free_List_Manager.Free_List;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Assert
        (Database.Storage.Free_List_Manager.Free_Count (List) = 0,
         "clear must set count to zero");
      Assert
        (Database.Storage.Free_List_Manager.Validate (List, 2, 100)
         = Database.Storage.Free_List_Manager.Valid,
         "empty list must validate");
   end Test_Clear_And_Validate;

   procedure Test_Add_Keeps_Sorted_Order
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 9, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK, "add 9");
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 3, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK, "add 3");
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 7, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK, "add 7");

      Assert (List.Count = 3, "count should be three");
      Assert
        (List.Pages (1) = 3 and then List.Pages (2) = 7 and then List.Pages (3) = 9,
         "pages should be sorted");
      Assert
        (Database.Storage.Free_List_Manager.Is_Sorted_Unique (List),
         "list should be sorted and unique");
   end Test_Add_Keeps_Sorted_Order;

   procedure Test_Rejects_Duplicate_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 5, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK,
         "first add");
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 5, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Page_Already_Free,
         "duplicate add must be rejected");
   end Test_Rejects_Duplicate_Page;

   procedure Test_Rejects_Reserved_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 1, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Invalid_Page_Id,
         "reserved page must be rejected");
   end Test_Rejects_Reserved_Page;

   procedure Test_Rejects_Out_Of_Range_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 101, 2, 100, Status);
      Assert
        (Status = Database.Storage.Free_List_Manager.Invalid_Page_Id,
         "out-of-range page must be rejected");
   end Test_Rejects_Out_Of_Range_Page;

   procedure Test_Allocate_Returns_Free_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
      Page   : Database.Storage.Free_List_Manager.Page_Id_Type;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 3, 2, 100, Status);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 9, 2, 100, Status);

      Database.Storage.Free_List_Manager.Allocate_Free_Page
        (List, 2, 100, Page, Status);

      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK,
         "allocate should succeed");
      Assert
        (Page = 9,
         "allocator returns highest sorted page id for deterministic reuse");
      Assert (List.Count = 1, "allocate removes page from list");
      Assert
        (not Database.Storage.Free_List_Manager.Contains (List, 9),
         "allocated page no longer free");
   end Test_Allocate_Returns_Free_Page;

   procedure Test_Remove_Free_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List   : Database.Storage.Free_List_Manager.Free_List;
      Status : Database.Storage.Free_List_Manager.Operation_Status;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 3, 2, 100, Status);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 7, 2, 100, Status);
      Database.Storage.Free_List_Manager.Add_Free_Page
        (List, 9, 2, 100, Status);

      Database.Storage.Free_List_Manager.Remove_Free_Page
        (List, 7, 2, 100, Status);

      Assert
        (Status = Database.Storage.Free_List_Manager.Operation_OK,
         "remove should succeed");
      Assert (List.Count = 2, "remove decreases count");
      Assert
        (List.Pages (1) = 3 and then List.Pages (2) = 9,
         "remaining pages stay sorted");
   end Test_Remove_Free_Page;

   procedure Test_Detects_Corrupt_Duplicate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List : Database.Storage.Free_List_Manager.Free_List;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      List.Count := 2;
      List.Pages (1) := 5;
      List.Pages (2) := 5;

      Assert
        (Database.Storage.Free_List_Manager.Validate (List, 2, 100)
         = Database.Storage.Free_List_Manager.Contains_Duplicate,
         "duplicate free-list entry must be detected");
   end Test_Detects_Corrupt_Duplicate;

   procedure Test_Detects_Corrupt_Unsorted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      List : Database.Storage.Free_List_Manager.Free_List;
   begin
      Database.Storage.Free_List_Manager.Clear (List);
      List.Count := 2;
      List.Pages (1) := 9;
      List.Pages (2) := 5;

      Assert
        (Database.Storage.Free_List_Manager.Validate (List, 2, 100)
         = Database.Storage.Free_List_Manager.Not_Sorted,
         "unsorted free-list entry must be detected");
   end Test_Detects_Corrupt_Unsorted;

end Free_List_Manager_Tests;
