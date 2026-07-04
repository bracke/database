--  Fixed-size page representation and page serialization helpers.
with Ada.Streams;
with Database.Status;
with Database.Log_Sequence;

   --  Public nested package `Database.Storage.Pages`.
package Database.Storage.Pages is
   --  Page_Size is a public constant used by this package.
   Page_Size : constant := 4096;
   --  Public type `Page_Id`.
   subtype Page_Id is Database.Page_Id;
   --  Invalid_Page_Id is a public constant used by this package.
   Invalid_Page_Id : constant Page_Id := 0;

   --  Public type `Page_Kind`.
   type Page_Kind is
     (Header_Page,
      Catalog_Page,
      Table_Heap_Page,
      Free_Page,
      BTree_Internal_Page,
      BTree_Leaf_Page,
      Full_Text_Dictionary_Page,
      Full_Text_Posting_Page);
   --  Public type `Byte`.
   subtype Byte is Database.Byte;
   --  Public type `Byte_Array`.
   subtype Byte_Array is Database.Byte_Array;
   --  Public type `Page_Buffer`.
   subtype Page_Buffer is Byte_Array (0 .. Page_Size - 1);

   --  Header_Size is a public constant used by this package.
   Header_Size : constant := 40;
   --  Payload_Capacity is a public constant used by this package.
   Payload_Capacity : constant := Page_Size - Header_Size;

   --  Public type `Page`.
   type Page is record
      Buffer : Page_Buffer := (others => 0);
   end record;

   --  Public operation `Initialize`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @param Id id argument supplied to the operation.
   --  @param Kind kind selector controlling the operation.
   --  @param Next next argument supplied to the operation.
   procedure Initialize
     (P    : out Page;
      Id   : Page_Id;
      Kind : Page_Kind;
      Next : Page_Id := Invalid_Page_Id);

   --  Public operation `Validate`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @param Expected_Id expected id argument supplied to the operation.
   --  @param Expected_Kind expected kind argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate
     (P             : Page;
      Expected_Id   : Page_Id;
      Expected_Kind : Page_Kind) return Database.Status.Result;

   --  Public operation `Get_Id`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param P p argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Get_Id (P : Page) return Page_Id;
   --  Public operation `Get_Kind`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Get_Kind (P : Page) return Page_Kind;
   --  Public operation `Get_Next`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Get_Next (P : Page) return Page_Id;
   --  Public operation `Set_Next`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @param Next next argument supplied to the operation.
   procedure Set_Next (P : in out Page; Next : Page_Id);
   --  Public operation `Used`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Used (P : Page) return Natural;
   --  Public operation `Set_Used`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @param Used used argument supplied to the operation.
   procedure Set_Used (P : in out Page; Used : Natural);
   --  Return the last WAL LSN applied to this page.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Last_LSN (P : Page) return Database.Log_Sequence.Log_Sequence_Number;
   --  Set the last WAL LSN applied to this page.
   --  @param P p argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   procedure Set_Last_LSN
     (P   : in out Page;
      LSN : Database.Log_Sequence.Log_Sequence_Number);
   --  Public operation `Payload`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Payload (P : Page) return Byte_Array;
   --  Public operation `Set_Payload`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @param Data byte data processed by the operation.
   procedure Set_Payload (P : in out Page; Data : Byte_Array);

   --  Public operation `To_Stream`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function To_Stream (P : Page) return Ada.Streams.Stream_Element_Array;
   --  Public operation `From_Stream`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param S s argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Stream (S : Ada.Streams.Stream_Element_Array) return Page;
end Database.Storage.Pages;
