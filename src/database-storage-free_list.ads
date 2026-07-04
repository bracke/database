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

   --  Public operation `Allocate`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param A a argument supplied to the operation.
   --  @param F f argument supplied to the operation.
   --  @param Kind kind selector controlling the operation.
   --  @param Page page argument supplied to the operation.
   --  @return Result produced by the function.
   function Allocate
     (A    : in out Allocator;
      F    : in out Database.Storage.File_IO.File_Handle;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result;

   --  Public operation `Release`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param A a argument supplied to the operation.
   --  @param Id id argument supplied to the operation.
   --  @return Result produced by the function.
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
