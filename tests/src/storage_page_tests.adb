with AUnit.Assertions;

with Database.Status;
with Database.Storage.Pages;

package body Storage_Page_Tests is
   use AUnit.Assertions;
   use Database.Storage.Pages;
   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("storage pages");
   end Name;

   procedure Validate_Page (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      P : Page;
      R : Database.Status.Result;
   begin
      Initialize (P, 7, Table_Heap_Page);
      R := Validate (P, 7, Table_Heap_Page);
      Assert (Database.Status.Is_Ok (R), "valid page rejected");
      R := Validate (P, 8, Table_Heap_Page);
      Assert (not Database.Status.Is_Ok (R), "wrong id accepted");
      R := Validate (P, 7, Catalog_Page);
      Assert (not Database.Status.Is_Ok (R), "wrong kind accepted");
      declare D : Byte_Array (0 .. 2) := (1, 2, 3); begin
         Set_Payload (P, D); Assert (Used (P) = 3, "used payload length not set");
      end;
   end Validate_Page;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Validate_Page'Access, "page validation and bounds");
   end Register_Tests;
end Storage_Page_Tests;
