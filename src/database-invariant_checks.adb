with Database.Metrics;
with Database.Status;
with Database.Storage.Pages;
with Database.Storage.Free_List;
with Database.Storage.Table_Heap;
with Database.Storage.File_IO;
with Database.Backup_Format;
with Database.Indexes.BTree;
with Database.WAL;
with Database.Versioning;
with Database.MVCC;
with Database.Catalog;
with Database.Constraints;
with Database.Rows;
with Database.Foreign_Keys;
with Database.Schema;
with Database.Indexes;
with Database.Full_Text;
with Database.Full_Text.Indexes;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Invariant_Checks is
   use type Database.Full_Text.Indexes.Full_Text_Index_Id;
   use type Database.Storage.Pages.Page_Id;
   use type Database.Storage.Pages.Page_Kind;
   use type Database.Log_Sequence.Log_Sequence_Number;
   use type Database.Versioning.Commit_Version;
   function Pass (Items : Natural := 0) return Check_Report is
   begin
      return (Result => Database.Status.Success, Checked_Items => Items, Failed_Items => 0);
   end Pass;

   function Fail (Kind : Check_Kind; Message : Wide_Wide_String) return Check_Report is
      pragma Unreferenced (Kind);
   begin
      Database.Metrics.Increment_Invariant_Failures;
      return
        (Result => Database.Status.Failure (Database.Status.Invariant_Failure, Message),
         Checked_Items => 1,
         Failed_Items => 1);
   end Fail;

   function Validate_Sorted_Keys (Keys : Integer_Array) return Check_Report is
   begin
      if Keys'Length <= 1 then
         return Pass (Keys'Length);
      end if;
      for I in Keys'First + 1 .. Keys'Last loop
         pragma Loop_Invariant (I in Keys'First + 1 .. Keys'Last);
         if Keys (I - 1) > Keys (I) then
            Database.Metrics.Increment_Invariant_Failures;
            return
              (Result        =>
                 Database.Status.Failure
                   (Database.Status.Invariant_Failure,
                    "B+ tree keys are not sorted"),
               Checked_Items => Keys'Length,
               Failed_Items  => 1);
         end if;
      end loop;
      return Pass (Keys'Length);
   end Validate_Sorted_Keys;

   function Validate_LSN_Order
     (Previous : Database.Log_Sequence.Log_Sequence_Number;
      Current  : Database.Log_Sequence.Log_Sequence_Number) return Check_Report is
   begin
      if Current < Previous then
         return Fail (WAL_LSN_Order, "WAL LSN ordering regressed");
      end if;
      return Pass (2);
   end Validate_LSN_Order;

   function Validate_LSN_Sequence (Items : LSN_Array) return Check_Report is
   begin
      if Items'Length <= 1 then
         return Pass (Items'Length);
      end if;
      for I in Items'First + 1 .. Items'Last loop
         if Items (I) < Items (I - 1) then
            return Fail (WAL_LSN_Order, "WAL LSN sequence is not monotonic");
         end if;
      end loop;
      return Pass (Items'Length);
   end Validate_LSN_Sequence;

   function Validate_WAL_File (Database_Path : Wide_Wide_String) return Check_Report is
      R : constant Database.Status.Result := Database.WAL.Validate (Database_Path);
   begin
      if Database.Status.Is_Ok (R) then
         return Pass (1);
      end if;
      return
        (Result => Database.Status.Failure
           (Database.Status.Corruption_Detected,
            "WAL invariant parser rejected invalid or non-monotonic WAL"),
         Checked_Items => 1,
         Failed_Items  => 1);
   end Validate_WAL_File;

   function Validate_Page_Header (Page : Database.Storage.Pages.Page) return Check_Report is
      Used : constant Natural := Database.Storage.Pages.Used (Page);
   begin
      if Database.Storage.Pages.Get_Id (Page) = Database.Storage.Pages.Invalid_Page_Id
        and then Database.Storage.Pages.Get_Kind (Page) /= Database.Storage.Pages.Header_Page
      then
         return Fail (Page_Header, "page id is invalid");
      end if;
      if Used > Database.Storage.Pages.Payload_Capacity then
         return Fail (Page_Header, "page used bytes exceed payload capacity");
      end if;
      return Pass (1);
   end Validate_Page_Header;

   function Validate_Linked_Page_Chain
     (F             : in out Database.Storage.File_IO.File_Handle;
      Start         : Database.Storage.Pages.Page_Id;
      Expected_Kind : Database.Storage.Pages.Page_Kind) return Check_Report is
      Count  : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Page   : Database.Storage.Pages.Page;
      R      : Database.Status.Result;
      Seen   : Page_Id_Array (1 .. (if Count = 0 then 1 else Count)) :=
        (others => Database.Storage.Pages.Invalid_Page_Id);
      Used   : Natural := 0;
      Current : Database.Storage.Pages.Page_Id := Start;
   begin
      if Start = Database.Storage.Pages.Invalid_Page_Id then
         return Pass (0);
      end if;
      if Natural (Start) >= Count then
         return Fail (Page_Chain, "linked page chain starts outside file");
      end if;

      while Current /= Database.Storage.Pages.Invalid_Page_Id loop
         if Natural (Current) >= Count then
            return Fail (Page_Chain, "linked page chain references page outside file");
         end if;

         for I in 1 .. Used loop
            if Seen (I) = Current then
               return Fail (Page_Chain, "linked page chain contains a cycle");
            end if;
         end loop;

         R := Database.Storage.File_IO.Read_Page (F, Current, Expected_Kind, Page);
         if not Database.Status.Is_Ok (R) then
            return
              (Result => Database.Status.Failure
                 (Database.Status.Corruption_Detected,
                  "linked page chain contains unreadable or wrong-kind page"),
               Checked_Items => Used + 1,
               Failed_Items  => 1);
         end if;

         Used := Used + 1;
         Seen (Used) := Current;
         Current := Database.Storage.Pages.Get_Next (Page);
      end loop;

      return Pass (Used);
   end Validate_Linked_Page_Chain;

   function Validate_Page_Link_Graph
     (F : in out Database.Storage.File_IO.File_Handle) return Check_Report is
      Count : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Page  : Database.Storage.Pages.Page;
      R     : Database.Status.Result;
      Next  : Database.Storage.Pages.Page_Id;
      Report : Check_Report := Pass (0);
   begin
      if Count < 2 then
         return Fail (Page_Header, "database file is missing required header/catalog pages");
      end if;

      --  Reserved pages must keep their structural roles.  This catches file
      --  truncation or page-kind corruption before higher-level traversal runs.
      R := Database.Storage.File_IO.Read_Page (F, 0, Database.Storage.Pages.Header_Page, Page);
      if not Database.Status.Is_Ok (R) then
         return Fail (Page_Header, "database header page is invalid");
      end if;
      Report := Combine (Report, Pass (1));

      R := Database.Storage.File_IO.Read_Page (F, 1, Database.Storage.Pages.Catalog_Page, Page);
      if not Database.Status.Is_Ok (R) then
         return Fail (Catalog_Metadata, "database catalog page is invalid");
      end if;
      Report := Combine (Report, Pass (1));

      for I in 0 .. Count - 1 loop
         R := Database.Storage.File_IO.Read_Raw_Page
           (F, Database.Storage.Pages.Page_Id (I), Page);
         if not Database.Status.Is_Ok (R) then
            return
              (Result => Database.Status.Failure
                 (Database.Status.Corruption_Detected,
                  "page-link graph traversal found unreadable page"),
               Checked_Items => Report.Checked_Items + 1,
               Failed_Items  => 1);
         end if;

         Next := Database.Storage.Pages.Get_Next (Page);
         if Next /= Database.Storage.Pages.Invalid_Page_Id then
            if Natural (Next) >= Count then
               return Fail (Page_Chain, "page next pointer references outside file");
            end if;
            if Next = Database.Storage.Pages.Get_Id (Page) then
               return Fail (Page_Chain, "page next pointer references itself");
            end if;
         end if;

         --  Follow every non-empty next chain with the concrete page kind as
         --  the expected kind.  This turns link checks from local header checks
         --  into real graph traversal with cycle detection.
         if Next /= Database.Storage.Pages.Invalid_Page_Id then
            declare
               Chain : constant Check_Report  :=
                 Validate_Linked_Page_Chain
                   (F, Database.Storage.Pages.Get_Id (Page), Database.Storage.Pages.Get_Kind (Page));
            begin
               Report := Combine (Report, Chain);
               if not Database.Status.Is_Ok (Report.Result) then
                  return Report;
               end if;
            end;
         else
            Report := Combine (Report, Pass (1));
         end if;
      end loop;

      return Report;
   end Validate_Page_Link_Graph;

   function Validate_Page_File
     (F : in out Database.Storage.File_IO.File_Handle) return Check_Report is
      Count : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Page  : Database.Storage.Pages.Page;
      R     : Database.Status.Result;
      Seen  : Page_Id_Array (1 .. (if Count = 0 then 1 else Count));
      Used  : Natural := 0;
      Report : Check_Report := Pass (0);
   begin
      if Count = 0 then
         return Fail (Page_Header, "database file contains no pages");
      end if;

      for I in 0 .. Count - 1 loop
         R := Database.Storage.File_IO.Read_Raw_Page
           (F, Database.Storage.Pages.Page_Id (I), Page);
         if not Database.Status.Is_Ok (R) then
            return
              (Result => Database.Status.Failure
                 (Database.Status.Corruption_Detected,
                  "page file traversal rejected corrupt or unreadable page"),
               Checked_Items => I,
               Failed_Items  => 1);
         end if;

         declare
            H : constant Check_Report := Validate_Page_Header (Page);
         begin
            Report := Combine (Report, H);
            if not Database.Status.Is_Ok (Report.Result) then
               return Report;
            end if;
         end;

         if Database.Storage.Pages.Get_Id (Page) /= Database.Storage.Pages.Page_Id (I) then
            return Fail (Page_Header, "page id does not match physical slot");
         end if;

         if Database.Storage.Pages.Get_Next (Page) /= Database.Storage.Pages.Invalid_Page_Id
           and then Natural (Database.Storage.Pages.Get_Next (Page)) >= Count
         then
            return Fail (Page_Chain, "page next pointer references outside file");
         end if;

         Used := Used + 1;
         Seen (Used) := Database.Storage.Pages.Get_Id (Page);
         for J in 1 .. Used - 1 loop
            if Seen (J) = Seen (Used) then
               return Fail (Page_Chain, "page file contains duplicate page id");
            end if;
         end loop;
      end loop;

      Report := Combine (Report, Validate_Page_Link_Graph (F));
      if not Database.Status.Is_Ok (Report.Result) then
         return Report;
      end if;

      return (Result => Database.Status.Success, Checked_Items => Report.Checked_Items, Failed_Items => 0);
   end Validate_Page_File;

   function Validate_Page_Chain (Pages : Page_Id_Array) return Check_Report is
   begin
      for I in Pages'Range loop
         if Pages (I) = Database.Storage.Pages.Invalid_Page_Id then
            return Fail (Page_Chain, "page chain contains invalid page id");
         end if;
         for J in Pages'First .. I - 1 loop
            if Pages (J) = Pages (I) then
               return Fail (Page_Chain, "page chain contains a cycle or duplicate page reference");
            end if;
         end loop;
      end loop;
      return Pass (Pages'Length);
   end Validate_Page_Chain;

   function Validate_Free_List_Links (Pages : Page_Id_Array) return Check_Report is
   begin
      for I in Pages'Range loop
         if Pages (I) <= 1 or else Pages (I) = Database.Storage.Pages.Invalid_Page_Id then
            return Fail (Free_List_Links, "free-list contains reserved or invalid page id");
         end if;
         for J in Pages'First .. I - 1 loop
            if Pages (J) = Pages (I) then
               return Fail (Free_List_Links, "free-list contains duplicate page id");
            end if;
         end loop;
      end loop;
      return Pass (Pages'Length);
   end Validate_Free_List_Links;

   function Validate_BTree_Links (Links : BTree_Link_Array) return Check_Report is
   begin
      for I in Links'Range loop
         if Links (I).Parent = Database.Storage.Pages.Invalid_Page_Id
           or else Links (I).Child = Database.Storage.Pages.Invalid_Page_Id
           or else Links (I).Parent = Links (I).Child
         then
            return Fail (BTree_Parent_Child_Links, "B+ tree parent/child link is invalid");
         end if;
      end loop;
      return Pass (Links'Length);
   end Validate_BTree_Links;

   function Validate_BTree
     (F    : in out Database.Storage.File_IO.File_Handle;
      Root : Database.Storage.Pages.Page_Id) return Check_Report is
      R : constant Database.Status.Result := Database.Indexes.BTree.Validate (F, Root);
   begin
      if Database.Status.Is_Ok (R) then
         return Pass (1);
      end if;
      return
        (Result => Database.Status.Failure
           (Database.Status.Invariant_Failure,
            "B+ tree native traversal failed"),
         Checked_Items => 1,
         Failed_Items  => 1);
   end Validate_BTree;

   function Validate_Table_Heap_Deep
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema) return Check_Report is
      R : Database.Status.Result;
      C : Database.Storage.Table_Heap.Heap_Cursor;
      Rows_Checked : Natural := 0;
      Report : Check_Report := Pass (0);
   begin
      if First_Page = Database.Storage.Pages.Invalid_Page_Id then
         return Pass (0);
      end if;

      R := Database.Storage.Table_Heap.Validate_Table_Heap (F, First_Page, Schema);
      if not Database.Status.Is_Ok (R) then
         return
           (Result => Database.Status.Failure
              (Database.Status.Invariant_Failure,
               "deep heap traversal rejected page chain, row slots, or row payloads"),
            Checked_Items => 1,
            Failed_Items  => 1);
      end if;
      Report := Combine (Report, Pass (1));

      R := Database.Storage.Table_Heap.Scan_First (F, First_Page, Schema, C);
      if not Database.Status.Is_Ok (R) then
         return
           (Result => Database.Status.Failure
              (Database.Status.Invariant_Failure,
               "deep heap traversal could not start row scan"),
            Checked_Items => Report.Checked_Items + 1,
            Failed_Items  => 1);
      end if;

      while C.Has_Row loop
         declare
            Row_Check : constant Database.Status.Result  :=
              Database.Constraints.Validate_Row (Schema, C.Row);
         begin
            if not Database.Status.Is_Ok (Row_Check) then
               return
                 (Result => Database.Status.Failure
                    (Database.Status.Invariant_Failure,
                     "deep heap traversal found row/schema violation"),
                  Checked_Items => Report.Checked_Items + Rows_Checked + 1,
                  Failed_Items  => 1);
            end if;
         end;

         if C.Current_Page = Database.Storage.Pages.Invalid_Page_Id then
            return Fail (Table_Heap_Traversal, "deep heap traversal produced invalid row page reference");
         end if;
         if C.Slot_Offset >= Database.Storage.Pages.Payload_Capacity then
            return Fail (Table_Heap_Traversal, "deep heap traversal produced out-of-range slot reference");
         end if;

         Rows_Checked := Rows_Checked + 1;
         R := Database.Storage.Table_Heap.Scan_Next (F, Schema, C);
         if not Database.Status.Is_Ok (R) then
            return
              (Result => Database.Status.Failure
                 (Database.Status.Invariant_Failure,
                  "deep heap traversal failed while advancing row scan"),
               Checked_Items => Report.Checked_Items + Rows_Checked,
               Failed_Items  => 1);
         end if;
      end loop;

      return Pass (Report.Checked_Items + Rows_Checked);
   end Validate_Table_Heap_Deep;

   function Validate_Free_Page_Set
     (F : in out Database.Storage.File_IO.File_Handle) return Check_Report is
      Count  : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Page   : Database.Storage.Pages.Page;
      R      : Database.Status.Result;
      Free_Count : Natural := 0;
      Report : Check_Report := Pass (0);
   begin
      if Count = 0 then
         return Fail (Free_Page_Set, "free-page traversal requires a non-empty file");
      end if;

      for I in 0 .. Count - 1 loop
         R := Database.Storage.File_IO.Read_Raw_Page
           (F, Database.Storage.Pages.Page_Id (I), Page);
         if not Database.Status.Is_Ok (R) then
            return
              (Result => Database.Status.Failure
                 (Database.Status.Corruption_Detected,
                  "free-page traversal found unreadable page"),
               Checked_Items => Report.Checked_Items + 1,
               Failed_Items  => 1);
         end if;

         if Database.Storage.Pages.Get_Kind (Page) = Database.Storage.Pages.Free_Page then
            if I < 2 then
               return Fail (Free_Page_Set, "reserved page is marked free");
            end if;
            if Database.Storage.Pages.Get_Id (Page) /= Database.Storage.Pages.Page_Id (I) then
               return Fail (Free_Page_Set, "free page id does not match physical slot");
            end if;
            if Database.Storage.Pages.Used (Page) /= 0 then
               return Fail (Free_Page_Set, "free page contains live payload bytes");
            end if;
            if Database.Storage.Pages.Get_Next (Page) /= Database.Storage.Pages.Invalid_Page_Id
              and then Natural (Database.Storage.Pages.Get_Next (Page)) >= Count
            then
               return Fail (Free_Page_Set, "free page next link points outside file");
            end if;
            Free_Count := Free_Count + 1;
         end if;
         Report := Combine (Report, Pass (1));
      end loop;

      --  Also run the allocator's native free-list validator to keep this
      --  traversal aligned with allocation state reconstructed from the file.
      declare
         A : Database.Storage.Free_List.Allocator;
      begin
         Database.Storage.Free_List.Initialize_From_File (A, F);
         R := Database.Storage.Free_List.Validate_Free_List (A, F);
         if not Database.Status.Is_Ok (R) then
            return
              (Result => Database.Status.Failure
                 (Database.Status.Invariant_Failure,
                  "allocator free-list traversal failed"),
               Checked_Items => Report.Checked_Items + Free_Count,
               Failed_Items  => 1);
         end if;
      end;

      return Pass (Report.Checked_Items + Free_Count);
   end Validate_Free_Page_Set;

   function Validate_MVCC_Chain (Versions : Version_Node_Array) return Check_Report is
   begin
      for I in Versions'Range loop
         if Versions (I).Transaction = 0 then
            return Fail (MVCC_Version_Chain, "MVCC version has no transaction owner");
         end if;
         if Versions (I).End_Version /= Database.Versioning.No_Version
           and then Versions (I).End_Version < Versions (I).Begin_Version
         then
            return Fail (MVCC_Version_Chain, "MVCC version ends before it begins");
         end if;
         if I > Versions'First
           and then Versions (I).Begin_Version < Versions (I - 1).Begin_Version
         then
            return Fail (MVCC_Version_Chain, "MVCC version chain is not ordered by begin version");
         end if;
      end loop;
      return Pass (Versions'Length);
   end Validate_MVCC_Chain;

   function Validate_Active_Snapshot
     (Snapshot : Database.Versioning.Commit_Version) return Check_Report is
   begin
      if Database.MVCC.Has_Active_Snapshot
        and then Snapshot < Database.MVCC.Oldest_Active_Snapshot
      then
         return Fail (Snapshot_References, "snapshot reference is older than active MVCC horizon");
      end if;
      return Pass (1);
   end Validate_Active_Snapshot;

   function Validate_Index_References (Refs : Index_Reference_Array) return Check_Report is
   begin
      for I in Refs'Range loop
         if Refs (I).Index_Page = Database.Storage.Pages.Invalid_Page_Id
           or else Refs (I).Heap_Page = Database.Storage.Pages.Invalid_Page_Id
         then
            return Fail (Index_References, "index entry references an invalid page");
         end if;
      end loop;
      return Pass (Refs'Length);
   end Validate_Index_References;

   function Validate_Backup_Manifest
     (Backup_Path : Wide_Wide_String;
      Manifest    : Database.Backup_Format.Manifest) return Check_Report is
      R : constant Database.Status.Result  :=
        Database.Backup_Format.Validate_Manifest (Backup_Path, Manifest);
   begin
      if not Database.Status.Is_Ok (R) then
         return Fail (Backup_Manifest, "backup manifest failed validation");
      end if;
      return Pass (1);
   end Validate_Backup_Manifest;

   function Validate_Import_Header
     (Magic : Wide_Wide_String;
      Version : Natural) return Check_Report is
   begin
      if Magic /= "DATABASE_LOGICAL_EXPORT_20" and then Magic /= "DATABASE_LOGICAL_EXPORT_26" then
         return Fail (Import_Structure, "logical import magic is invalid");
      end if;
      if Version /= 20 and then Version /= 26 then
         return Fail (Import_Structure, "logical import version is unsupported");
      end if;
      return Pass (2);
   end Validate_Import_Header;

   function Validate_Encryption_Metadata
     (Format_Version : Natural;
      Key_Id         : Natural;
      Authenticated  : Boolean) return Check_Report is
   begin
      if Format_Version = 0 then
         return Fail (Encryption_Metadata, "encryption metadata format version is invalid");
      end if;
      if Key_Id = 0 then
         return Fail (Encryption_Metadata, "encryption metadata key id is invalid");
      end if;
      if not Authenticated then
         return Fail (Encryption_Metadata, "encryption metadata authentication failed");
      end if;
      return Pass (3);
   end Validate_Encryption_Metadata;

   function Validate_Database
     (DB : in out Database.Handle) return Check_Report is
      use Ada.Strings.Wide_Wide_Unbounded;
      Report : Check_Report := Pass (0);
      R      : Database.Status.Result;
   begin
      if not Database.Is_Open (DB) then
         return
           (Result => Database.Status.Failure
              (Database.Status.Not_Open, "database invariant check requires an open handle"),
            Checked_Items => 1,
            Failed_Items  => 1);
      end if;

      --  Durable physical structures.
      if Database.Backend (DB) = Database.Persistent_Backend then
         Report := Combine (Report, Validate_Page_File (DB.File));
         if not Database.Status.Is_Ok (Report.Result) then
            return Report;
         end if;

         Report := Combine (Report, Validate_Free_Page_Set (DB.File));
         if not Database.Status.Is_Ok (Report.Result) then
            return Report;
         end if;

         declare
            W : constant Check_Report := Validate_WAL_File (Database.Storage.File_IO.Path (DB.File));
         begin
            --  A missing/empty WAL is acceptable for a cleanly closed database;
            --  a corrupt WAL is not.  Validate_WAL_File reports corruption as a
            --  failed invariant and is therefore folded into the engine report.
            if not Database.Status.Is_Ok (W.Result)
              and then W.Result.Code /= Database.Status.Corruption_Detected
            then
               Report := Combine (Report, W);
            elsif not Database.Status.Is_Ok (W.Result) then
               return W;
            else
               Report := Combine (Report, W);
            end if;
         end;
      end if;

      --  Catalog tables and index metadata.
      if Database.Catalog.Table_Count > 0 then
      for T in 0 .. Database.Catalog.Table_Count - 1 loop
         declare
            S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (T);
            Seen_Primary : Natural := 0;
         begin
            if S.Table_Id = 0 or else Length (S.Name) = 0 then
               return Fail (Catalog_Metadata, "catalog table has invalid identity metadata");
            end if;
            if Database.Schema.Column_Count (S) = 0 then
               return Fail (Catalog_Metadata, "catalog table has no columns");
            end if;
            Report := Combine (Report, Pass (1));

            if Database.Schema.Column_Count (S) > 0 then
            for C in 0 .. Database.Schema.Column_Count (S) - 1 loop
               declare
                  Col : constant Database.Schema.Column := S.Columns.Element (C);
               begin
                  if Length (Col.Name) = 0 then
                     return Fail (Catalog_Metadata, "catalog column has invalid identity metadata");
                  end if;
                  if Col.Primary_Key then
                     Seen_Primary := Seen_Primary + 1;
                  end if;
                  if C > 0 then
                     for D in 0 .. C - 1 loop
                        if S.Columns.Element (D).Id = Col.Id then
                           return Fail (Catalog_Metadata, "catalog column ids are not unique");
                        end if;
                     end loop;
                  end if;
                  Report := Combine (Report, Pass (1));
               end;
            end loop;
            end if;

            if Seen_Primary /= Database.Schema.Primary_Key_Column_Count (S) then
               return Fail (Catalog_Metadata, "primary-key column metadata is inconsistent");
            end if;

            if Database.Backend (DB) = Database.Persistent_Backend
              and then S.Heap_First_Page /= 0
            then
               Report := Combine
                 (Report,
                  Validate_Linked_Page_Chain
                    (DB.File,
                     Database.Storage.Pages.Page_Id (S.Heap_First_Page),
                     Database.Storage.Pages.Table_Heap_Page));
               if not Database.Status.Is_Ok (Report.Result) then
                  return Report;
               end if;

               Report := Combine
                 (Report,
                  Validate_Table_Heap_Deep
                    (DB.File,
                     Database.Storage.Pages.Page_Id (S.Heap_First_Page),
                     S));
               if not Database.Status.Is_Ok (Report.Result) then
                  return Report;
               end if;
            end if;

            declare
               Rows : constant Database.Foreign_Keys.Row_Vectors.Vector  :=
                 Database.Catalog.Rows_For_Table (S.Table_Id);
            begin
               for Row of Rows loop
                  R := Database.Constraints.Validate_Row (S, Row);
                  if not Database.Status.Is_Ok (R) then
                     return
                       (Result => Database.Status.Failure
                          (Database.Status.Invariant_Failure,
                           "catalog row registry contains a row that violates its schema"),
                        Checked_Items => Report.Checked_Items + 1,
                        Failed_Items  => 1);
                  end if;
                  Report := Combine (Report, Pass (1));
               end loop;
            end;

            for IX of S.Indexes loop
               R := Database.Indexes.Validate_Index_Metadata (IX);
               if not Database.Status.Is_Ok (R) then
                  return
                    (Result => Database.Status.Failure
                       (Database.Status.Invariant_Failure, "catalog index metadata is invalid"),
                     Checked_Items => Report.Checked_Items + 1,
                     Failed_Items  => 1);
               end if;
               Report := Combine (Report, Pass (1));
               if Database.Backend (DB) = Database.Persistent_Backend
                 and then IX.Root_Page /= Database.Storage.Pages.Invalid_Page_Id
               then
                  Report := Combine (Report, Validate_BTree (DB.File, IX.Root_Page));
                  if not Database.Status.Is_Ok (Report.Result) then
                     return Report;
                  end if;
               end if;
            end loop;
         end;
      end loop;
      end if;

      --  Full-text metadata and posting structures reachable from the catalog.
      declare
         Defs : constant Database.Full_Text.Indexes.Metadata_Vectors.Vector  :=
           Database.Catalog.Full_Text_Index_Definitions;
      begin
         for FT of Defs loop
            if FT.Id = 0 or else FT.Table_Id = 0 or else FT.Column_Id = 0
              or else Length (FT.Name) = 0
            then
               return Fail (Catalog_Metadata, "full-text index metadata is invalid");
            end if;
            R := Database.Full_Text.Check_Index (To_Wide_Wide_String (FT.Name));
            if not Database.Status.Is_Ok (R)
              and then R.Code /= Database.Status.Not_Found
            then
               return
                 (Result => Database.Status.Failure
                    (Database.Status.Invariant_Failure, "full-text index check failed"),
                  Checked_Items => Report.Checked_Items + 1,
                  Failed_Items  => 1);
            end if;
            Report := Combine (Report, Pass (1));
         end loop;
      end;

      --  MVCC snapshot horizon and encryption metadata.
      Report := Combine  (Report,
        Validate_Active_Snapshot (Database.Versioning.Commit_Version (Database.Commit_Version (DB))));
      if not Database.Status.Is_Ok (Report.Result) then
         return Report;
      end if;

      if DB.Encryption_Enabled then
         Report := Combine
           (Report,
            Validate_Encryption_Metadata
              (DB.Encryption_Format_Version,
               Natural (DB.Encryption_Key_Id),
               DB.WAL_Encryption_Enabled));
      end if;

      return Report;
   end Validate_Database;

   function Combine (Left, Right : Check_Report) return Check_Report is
   begin
      if not Database.Status.Is_Ok (Left.Result) then
         return
           (Result => Left.Result,
            Checked_Items => Left.Checked_Items + Right.Checked_Items,
            Failed_Items => Left.Failed_Items + Right.Failed_Items);
      elsif not Database.Status.Is_Ok (Right.Result) then
         return
           (Result => Right.Result,
            Checked_Items => Left.Checked_Items + Right.Checked_Items,
            Failed_Items => Left.Failed_Items + Right.Failed_Items);
      else
         return Pass (Left.Checked_Items + Right.Checked_Items);
      end if;
   end Combine;
end Database.Invariant_Checks;
