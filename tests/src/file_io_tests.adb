with AUnit.Assertions;
with Ada.Directories;
with Database; use Database;
with Database.Metrics;
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

   --  A handle reads each page from the file once per transaction; its own writes update the cache.
   procedure Read_Only_Page_Cache
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path    : constant Wide_Wide_String := "test_page_cache.database";
      Fixture : Database.Handle;
      F       : Database.Storage.File_IO.File_Handle;
      P, Q    : Database.Storage.Pages.Page;
      R       : Database.Status.Result;

      function Reads return Natural is (Database.Metrics.Snapshot_Metrics.Page_Reads);

      procedure Read (Into : out Database.Storage.Pages.Page) is
      begin
         R := Database.Storage.File_IO.Read_Page (F, 0, Database.Storage.Pages.Header_Page, Into);
         Assert (Database.Status.Is_Ok (R), "header page read failed");
      end Read;

      procedure Remove (Name : String) is
      begin
         if Ada.Directories.Exists (Name) then
            Ada.Directories.Delete_File (Name);
         end if;
      end Remove;

      procedure Remove is
      begin
         Remove ("test_page_cache.database");
         Remove ("test_page_cache.database.fts");
      end Remove;
   begin
      Remove;
      Database.Create (Fixture, Path);
      Assert (Database.Last_Operation_Succeeded (Fixture), "fixture create failed");
      Database.Close (Fixture);
      R := Database.Storage.File_IO.Open_Read_Only (F, Path);
      Assert (Database.Status.Is_Ok (R), "read-only open failed");
      Database.Storage.File_IO.Invalidate_Cache (F);
      Database.Metrics.Reset_Metrics;
      Read (P);
      Read (Q);
      Assert (Reads = 1, "a cached page is read from the file once");
      Assert (Database.Metrics.Snapshot_Metrics.Cache_Hits = 1, "the second read hits the cache");
      Assert (P.Buffer = Q.Buffer, "a cached page equals the page read from the file");
      R := Database.Storage.File_IO.Read_Page (F, 0, Database.Storage.Pages.Table_Heap_Page, Q);
      Assert (not Database.Status.Is_Ok (R), "a cached page is still checked for its kind");
      Database.Storage.File_IO.Invalidate_Cache (F);
      Read (Q);
      Assert (Reads = 2, "an invalidated page is read again");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "read-only close failed");
      R := Database.Storage.File_IO.Open (F, Path);
      Assert (Database.Status.Is_Ok (R), "read-write open failed");
      --  A read-write handle caches too, and its own writes keep the cache equal to the file.
      Database.Storage.Pages.Initialize (P, 7, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload (P, [0 .. 3 => 16#5A#]);
      R := Database.Storage.File_IO.Write_Page (F, P);
      Assert (Database.Status.Is_Ok (R), "page write failed");
      Database.Metrics.Reset_Metrics;
      R := Database.Storage.File_IO.Read_Page (F, 7, Database.Storage.Pages.Table_Heap_Page, Q);
      Assert (Database.Status.Is_Ok (R) and then Q.Buffer = P.Buffer, "a written page reads back as written");
      Assert (Reads = 0, "from the cache the write updated");
      Database.Storage.File_IO.Invalidate_Cache (F);
      R := Database.Storage.File_IO.Read_Page (F, 7, Database.Storage.Pages.Table_Heap_Page, Q);
      Assert (Database.Status.Is_Ok (R) and then Q.Buffer = P.Buffer and then Reads = 1,
              "and the file holds the same page");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "read-write close failed");
      Remove;
   end Read_Only_Page_Cache;

   --  The checksum covers every byte except its own four, and a page validated earlier may skip it.
   procedure Page_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P : Database.Storage.Pages.Page;
      Payload : Database.Byte_Array (0 .. 999);
   begin
      for I in Payload'Range loop
         Payload (I) := Database.Byte ((I * 37) mod 256);
      end loop;
      Database.Storage.Pages.Initialize (P, 3, Database.Storage.Pages.Table_Heap_Page);
      --  Set_Payload stores the bytes and refreshes the checksum.
      Database.Storage.Pages.Set_Payload (P, Payload);
      Assert (Database.Status.Is_Ok (Database.Storage.Pages.Validate (P, 3, Table_Heap_Page)),
              "a refreshed checksum validates");
      P.Buffer (Page_Size - 1) := P.Buffer (Page_Size - 1) + 1;
      Assert (not Database.Status.Is_Ok (Database.Storage.Pages.Validate (P, 3, Table_Heap_Page)),
              "a changed payload byte fails the checksum");
      Assert (Database.Status.Is_Ok
                (Database.Storage.Pages.Validate (P, 3, Table_Heap_Page, Verify_Checksum => False)),
              "a page validated earlier may skip the checksum");
   end Page_Checksum;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Create_Open_Read_Write'Access,
         "create/open/write/read/flush/close");
      Register_Routine (T, Read_Only_Page_Cache'Access, "handles cache pages per transaction");
      Register_Routine (T, Page_Checksum'Access, "page checksum covers every other byte");
   end Register_Tests;
end File_IO_Tests;
