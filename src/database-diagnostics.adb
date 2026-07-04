with Database.Catalog;
with Database.Full_Text;
with Database.Rows;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Storage.Table_Heap;
with Database.Transactions;

package body Database.Diagnostics is

   function Page_Count
     (Tx : in out Database.Transactions.Transaction) return Natural is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
   begin
      if DB = null or else Database.Backend (DB.all) /= Database.Persistent_Backend then
         return 0;
      end if;
      return Database.Storage.File_IO.Page_Count (DB.File);
   end Page_Count;

   function Free_Page_Count
     (Tx : in out Database.Transactions.Transaction) return Natural is
      pragma Unreferenced (Tx);
   begin
      return 0;
   end Free_Page_Count;

   function Database_Size
     (Tx : in out Database.Transactions.Transaction) return Natural is
      pragma Unreferenced (Tx);
   begin
      return 0;
   end Database_Size;

   function Table_Row_Count
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Natural is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      C  : Database.Storage.Table_Heap.Heap_Cursor;
      R  : Database.Status.Result;
      Count : Natural := 0;
   begin
      if DB = null then
         return 0;
      end if;
      if Database.Backend (DB.all) = Database.Persistent_Backend then
         R := Database.Storage.Table_Heap.Scan_First
           (Tx,
            DB.File,
            Database.Storage.Pages.Page_Id (Schema.Heap_First_Page),
            Schema,
            C);
         while Database.Status.Is_Ok (R) and then C.Has_Row loop
            Count := Count + 1;
            R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Schema, C);
         end loop;
         return Count;
      else
         return Natural (Database.Catalog.Rows_For_Table (Schema.Table_Id).Length);
      end if;
   end Table_Row_Count;

   function Table_Page_Count
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Natural is
      pragma Unreferenced (Tx, Schema);
   begin
      return 0;
   end Table_Page_Count;

   function Index_Page_Count
     (Tx    : in out Database.Transactions.Transaction;
      Index : Database.Indexes.Index_Metadata) return Natural is
      pragma Unreferenced (Tx, Index);
   begin
      return 0;
   end Index_Page_Count;

   function Index_Depth
     (Tx    : in out Database.Transactions.Transaction;
      Index : Database.Indexes.Index_Metadata) return Natural is
      pragma Unreferenced (Tx, Index);
   begin
      return 0;
   end Index_Depth;

   function Full_Text_Index_Count return Natural is
   begin
      return Database.Full_Text.Full_Text_Index_Count;
   end Full_Text_Index_Count;

   function Full_Text_Term_Count
     (Name : Wide_Wide_String) return Natural is
   begin
      return Database.Full_Text.Term_Count (Name);
   end Full_Text_Term_Count;

   function Full_Text_Posting_Count
     (Name : Wide_Wide_String) return Natural is
   begin
      return Database.Full_Text.Posting_Count (Name);
   end Full_Text_Posting_Count;

   function Full_Text_Obsolete_Posting_Count
     (Name : Wide_Wide_String) return Natural is
   begin
      return Database.Full_Text.Obsolete_Posting_Count (Name);
   end Full_Text_Obsolete_Posting_Count;

   function Encryption_Enabled
     (DB : Database.Handle) return Boolean is
   begin
      return DB.Encryption_Enabled;
   end Encryption_Enabled;

   function Encryption_Format_Version
     (DB : Database.Handle) return Natural is
   begin
      if DB.Encryption_Enabled then
         return DB.Encryption_Format_Version;
      else
         return 0;
      end if;
   end Encryption_Format_Version;

   function WAL_Encryption_Enabled
     (DB : Database.Handle) return Boolean is
   begin
      return DB.WAL_Encryption_Enabled;
   end WAL_Encryption_Enabled;

end Database.Diagnostics;
