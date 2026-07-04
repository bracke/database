--  Native page helpers for full-text dictionary and posting pages.
--
--  This package does not expose SQL or parser syntax.  It defines the byte
--  contract used when full-text terms/postings are stored inside ordinary
--  database pages and therefore can be WAL-framed like every other page kind.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Full_Text.Postings;
with Database.Storage.Pages;
with Database.Status;

--  Public specification for this database subsystem.
package Database.Full_Text.Storage is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Native_Format_Version is a public constant used by this package.
   Native_Format_Version : constant Natural := 1;

   --  Return build dictionary page for the supplied database state or arguments.
   --  @param Id id argument supplied to the operation.
   --  @param Term term argument supplied to the operation.
   --  @param Posting_Root posting root argument supplied to the operation.
   --  @return Result produced by the function.
   function Build_Dictionary_Page
     (Id           : Database.Storage.Pages.Page_Id;
      Term         : Wide_Wide_String;
      Posting_Root : Database.Storage.Pages.Page_Id) return Database.Storage.Pages.Page;

   --  Return parse dictionary page for the supplied database state or arguments.
   --  @param P p argument supplied to the operation.
   --  @param Term term argument supplied to the operation.
   --  @param Posting_Root posting root argument supplied to the operation.
   --  @return Result produced by the function.
   function Parse_Dictionary_Page
     (P            : Database.Storage.Pages.Page;
      Term         : out Unbounded_Wide_Wide_String;
      Posting_Root : out Database.Storage.Pages.Page_Id) return Database.Status.Result;

   --  Return build posting page for the supplied database state or arguments.
   --  @param Id id argument supplied to the operation.
   --  @param Term term argument supplied to the operation.
   --  @param Postings postings argument supplied to the operation.
   --  @param Next next argument supplied to the operation.
   --  @return Result produced by the function.
   function Build_Posting_Page
     (Id       : Database.Storage.Pages.Page_Id;
      Term     : Wide_Wide_String;
      Postings : Database.Full_Text.Postings.Posting_Vectors.Vector;
      Next     : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id)
      return Database.Storage.Pages.Page;

   --  Return parse posting page for the supplied database state or arguments.
   --  @param P p argument supplied to the operation.
   --  @param Term term argument supplied to the operation.
   --  @param Postings postings argument supplied to the operation.
   --  @return Result produced by the function.
   function Parse_Posting_Page
     (P        : Database.Storage.Pages.Page;
      Term     : out Unbounded_Wide_Wide_String;
      Postings : out Database.Full_Text.Postings.Posting_Vectors.Vector)
      return Database.Status.Result;
end Database.Full_Text.Storage;
