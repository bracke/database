--  Persistent page-file creation, opening, reading, writing, flushing, and truncation.
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Streams.Stream_IO;
with Database.Status;
with Database.Storage.Pages;
with Database.Keys;

   --  Public nested package `Database.Storage.File_IO`.
package Database.Storage.File_IO is
   --  Public type `File_Handle`.
   subtype File_Handle is Database.File_Handle;

   --  Public operation `Create`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create (F : in out File_Handle; Path : Wide_Wide_String) return Database.Status.Result;
   --  Public operation `Open`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Status result describing whether the operation succeeded.
   function Open (F : in out File_Handle; Path : Wide_Wide_String) return Database.Status.Result;

   --  Create/open a page file whose ordinary page reads and writes are
   --  authenticated encrypted page artifacts. The raw database file remains
   --  a sparse compatibility carrier;
   --  page contents are loaded from the
   --  encrypted page artifacts and fail closed on tampering.
   --  @param F f argument supplied to the operation.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Key key value used to identify the row or object.
   --  @return Status result describing whether the operation succeeded.
   function Create_Encrypted
     (F    : in out File_Handle;
      Path : Wide_Wide_String;
      Key  : Database.Keys.Encryption_Key) return Database.Status.Result;

   --  Return open encrypted for the supplied database state or arguments.
   --  @param F f argument supplied to the operation.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @param Key key value used to identify the row or object.
   --  @return Status result describing whether the operation succeeded.
   function Open_Encrypted
     (F    : in out File_Handle;
      Path : Wide_Wide_String;
      Key  : Database.Keys.Encryption_Key) return Database.Status.Result;

   --  Perform enable encryption for the supplied database state or arguments.
   --  @param F f argument supplied to the operation.
   --  @param Key key value used to identify the row or object.
   procedure Enable_Encryption
     (F   : in out File_Handle;
      Key : Database.Keys.Encryption_Key);

   --  Encrypt all pages already present in the carrier file into authenticated
   --  sidecar artifacts, then leave the handle in encrypted mode.
   function Encrypt_Existing_Pages
     (F   : in out File_Handle;
      Key : Database.Keys.Encryption_Key) return Database.Status.Result;

   --  Perform disable encryption for the supplied database state or arguments.
   --  @param F f argument supplied to the operation.
   procedure Disable_Encryption (F : in out File_Handle);
   --  Public operation `Is_Open`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Open (F : File_Handle) return Boolean;
   --  Public operation `Path`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @return Result produced by the function.
   function Path (F : File_Handle) return Wide_Wide_String;
   --  Public operation `Close`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @return Result produced by the function.
   function Close (F : in out File_Handle) return Database.Status.Result;
   --  Public operation `Flush`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param F f argument supplied to the operation.
   --  @return Result produced by the function.
   function Flush (F : in out File_Handle) return Database.Status.Result;
   --  Public operation `Read_Page`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param Id id argument supplied to the operation.
   --  @param Kind kind selector controlling the operation.
   --  @param Page page argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_Page
     (F    : in out File_Handle;
      Id   : Database.Storage.Pages.Page_Id;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result;
   --  Public operation `Read_Raw_Page`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param Id id argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_Raw_Page
     (F    : in out File_Handle;
      Id   : Database.Storage.Pages.Page_Id;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result;
   --  Public operation `Write_Page`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @return Result produced by the function.
   function Write_Page
     (F    : in out File_Handle;
      Page : Database.Storage.Pages.Page) return Database.Status.Result;
   --  Public operation `Page_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param F f argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Page_Count (F : in out File_Handle) return Natural;
   --  Public operation `Truncate_To_Page_Count`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param F f argument supplied to the operation.
   --  @param Count count argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Truncate_To_Page_Count
     (F     : in out File_Handle;
      Count : Natural) return Database.Status.Result;
   --  Public operation `File_Exists`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function File_Exists (Path : Wide_Wide_String) return Boolean;
   --  Public operation `Delete_File`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Status result describing whether the operation succeeded.
   function Delete_File (Path : Wide_Wide_String) return Database.Status.Result;

end Database.Storage.File_IO;
