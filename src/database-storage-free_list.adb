with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Status;
package body Database.Storage.Free_List is
   use type Database.Storage.Pages.Page_Kind;
   use type Database.Storage.Pages.Page_Id;
   procedure Initialize_From_File
     (A : in out Allocator;
      F : in out Database.Storage.File_IO.File_Handle) is
   begin
      declare
         Count : constant Natural := Database.Storage.File_IO.Page_Count (F);
      begin
         if Count < 2 then
            A.Next_Page := 2;
         else
            A.Next_Page := Database.Storage.Pages.Page_Id (Count);
         end if;
      end;
   end Initialize_From_File;

   function Allocate
     (A    : in out Allocator;
      F    : in out Database.Storage.File_IO.File_Handle;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result is
      Existing : Database.Storage.Pages.Page;
      R        : Database.Status.Result;
      Count    : constant Natural := Database.Storage.File_IO.Page_Count (F);
   begin
      if Count > 2 then
         for I in 2 .. Count - 1 loop
            R := Database.Storage.File_IO.Read_Raw_Page
              (F, Database.Storage.Pages.Page_Id (I), Existing);
            if Database.Status.Is_Ok (R)
              and then Database.Storage.Pages.Get_Kind (Existing) = Database.Storage.Pages.Free_Page
            then
               Database.Storage.Pages.Initialize
                 (Page, Database.Storage.Pages.Page_Id (I), Kind);
               return Database.Storage.File_IO.Write_Page (F, Page);
            end if;
         end loop;
      end if;

      Database.Storage.Pages.Initialize (Page, A.Next_Page, Kind);
      A.Next_Page := A.Next_Page + 1;
      return Database.Storage.File_IO.Write_Page (F, Page);
   end Allocate;

   function Release
     (A  : in out Allocator;
      Id : Database.Storage.Pages.Page_Id) return Database.Status.Result is
      pragma Unreferenced (A, Id);
   begin
      return Database.Status.Success;
   end Release;

   function Validate_Free_List
     (A : Allocator;
      F : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result is
      pragma Unreferenced (A);
      P : Database.Storage.Pages.Page;
      R : Database.Status.Result;
      Count : constant Natural := Database.Storage.File_IO.Page_Count (F);
   begin
      if Count = 0 then
         return Database.Status.Failure (Database.Status.Corrupt_File, "empty database file");
      end if;
      for I in 0 .. Count - 1 loop
         R := Database.Storage.File_IO.Read_Raw_Page (F, Database.Storage.Pages.Page_Id (I), P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_Free_List;
end Database.Storage.Free_List;
