--  Persistent free-page allocator and validation support.
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Status;

   --  Public nested package `Database.Storage.Free_List`.
package Database.Storage.Free_List is
   --  Public type `Allocator`.
   subtype Allocator is Database.Allocator;

   --  Public operation `Initialize_From_File`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param A a argument supplied to the operation.
   --  @param F f argument supplied to the operation.
   procedure Initialize_From_File
     (A : in out Allocator;
      F : in out Database.Storage.File_IO.File_Handle);

   --  Reserve a page and write it directly to the file, for allocations outside a transaction such as a table
   --  registration's heap. Inside a transaction use Database.Transactions.Allocate_Page, which a rollback undoes.
   --  @param A allocator of the database.
   --  @param F database file.
   --  @param Kind page kind of the new page.
   --  @param Page the written empty page.
   --  @return Status result describing whether the operation succeeded.
   function Allocate
     (A    : in out Allocator;
      F    : in out Database.Storage.File_IO.File_Handle;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result;

   --  Choose the page the next allocation uses, a free page or the next page past the end of the file, without
   --  writing it, so a transaction can write it and keep the free page as its before-image.
   --  @param A allocator of the database.
   --  @param F database file.
   --  @param Kind page kind of the new page.
   --  @param Page empty page of Kind for the chosen page id.
   --  @return Status result describing whether the operation succeeded.
   function Reserve
     (A    : in out Allocator;
      F    : in out Database.Storage.File_IO.File_Handle;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result;

   --  Remember a page the caller has rewritten as a free page, so the next allocation can reuse it. Each reuse checks
   --  the page again, so a release undone by a rollback is harmless.
   --  @param A allocator of the database.
   --  @param Id released page.
   --  @return Status result describing whether the operation succeeded.
   function Release
     (A  : in out Allocator;
      Id : Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Public operation `Validate_Free_List`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param A a argument supplied to the operation.
   --  @param F f argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Free_List
     (A : Allocator;
      F : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result;
end Database.Storage.Free_List;
