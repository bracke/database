with AUnit.Assertions;
with Ada.Directories;
with Database; use Database;
with Database.Status; use Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages; use Database.Storage.Pages;

package body File_IO_Tests is
   use AUnit.Assertions;
   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("file io");
   end Name;

   procedure Create_Open_Read_Write
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      F    : Database.Storage.File_IO.File_Handle;
      P, Q : Database.Storage.Pages.Page;
      R    : Database.Status.Result;
      Path : constant Wide_Wide_String := "test_file_io.database";
   begin
      R := Database.Storage.File_IO.Create (F, Path);
      Assert (Database.Status.Is_Ok (R), "create failed");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.Storage.File_IO.Write_Page (F, P);
      Assert (Database.Status.Is_Ok (R), "write page failed");
      R :=
        Database.Storage.File_IO.Read_Page
          (F, 2, Database.Storage.Pages.Table_Heap_Page, Q);
      Assert (Database.Status.Is_Ok (R), "read page failed");
      Assert (Database.Storage.Pages.Get_Id (Q) = 2, "read page id mismatch");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "close failed");
      R := Database.Storage.File_IO.Open (F, Path);
      Assert (Database.Status.Is_Ok (R), "open failed");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "close after open failed");
      if Ada.Directories.Exists ("test_file_io.database") then
         Ada.Directories.Delete_File ("test_file_io.database");
      end if;
   end Create_Open_Read_Write;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Create_Open_Read_Write'Access,
         "create/open/write/read/flush/close");
   end Register_Tests;
end File_IO_Tests;
