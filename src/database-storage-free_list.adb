package body Database.Storage.Free_List is
   use type Database.Storage.Pages.Page_Kind;
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
         A.Scanned := False;
         A.Free_Pages.Clear;
      end;
   end Initialize_From_File;

   function Reserve
     (A    : in out Allocator;
      F    : in out Database.Storage.File_IO.File_Handle;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result is
      Existing : Database.Storage.Pages.Page;
      R        : Database.Status.Result;
   begin
      --  Reading every page on every allocation made allocation cost grow with the file, so the free pages are
      --  collected once.
      if not A.Scanned then
         A.Scanned := True;
         for I in 2 .. Database.Storage.File_IO.Page_Count (F) - 1 loop
            R := Database.Storage.File_IO.Read_Raw_Page (F, Database.Storage.Pages.Page_Id (I), Existing);
            if Database.Status.Is_Ok (R)
              and then Database.Storage.Pages.Get_Kind (Existing) = Database.Storage.Pages.Free_Page
            then
               A.Free_Pages.Append (Database.Storage.Pages.Page_Id (I));
            end if;
         end loop;
      end if;
      --  A page found free may since have been used, for example by a transaction that rolled back, so it is
      --  checked again before it is reused.
      while not A.Free_Pages.Is_Empty loop
         declare
            Id : constant Database.Storage.Pages.Page_Id := A.Free_Pages.Last_Element;
         begin
            A.Free_Pages.Delete_Last;
            R := Database.Storage.File_IO.Read_Raw_Page (F, Id, Existing);
            if Database.Status.Is_Ok (R)
              and then Database.Storage.Pages.Get_Kind (Existing) = Database.Storage.Pages.Free_Page
            then
               Database.Storage.Pages.Initialize (Page, Id, Kind);
               return Database.Status.Success;
            end if;
         end;
      end loop;

      Database.Storage.Pages.Initialize (Page, A.Next_Page, Kind);
      A.Next_Page := A.Next_Page + 1;
      return Database.Status.Success;
   end Reserve;

   function Allocate
     (A    : in out Allocator;
      F    : in out Database.Storage.File_IO.File_Handle;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result
   is
      R : constant Database.Status.Result := Reserve (A, F, Kind, Page);
   begin
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Database.Storage.File_IO.Write_Page (F, Page);
   end Allocate;

   function Release
     (A  : in out Allocator;
      Id : Database.Storage.Pages.Page_Id) return Database.Status.Result is
   begin
      --  Before the first scan the page is found by the scan itself.
      if A.Scanned then
         A.Free_Pages.Append (Id);
      end if;
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
