with AUnit.Assertions;
with Database;
with Database.Keys;
with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Encrypted_Persistence;
with Database.Queries;
with Database.Values;
with Database.Rows;

package body Whole_Project_Integration_Tests is
   use AUnit.Assertions;
   use type Database.Storage.Pages.Page_Id;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("whole-project integrations");
   end Name;

   procedure Encrypted_File_IO_Pages_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "whole_project_encrypted_pages.db";
      Key  : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("whole-project", Database.Keys.Default_Salt);
      F    : Database.Storage.File_IO.File_Handle;
      P    : Database.Storage.Pages.Page;
      Back : Database.Storage.Pages.Page;
      R    : Database.Status.Result;
   begin
      R := Database.Storage.File_IO.Create_Encrypted (F, Path, Key);
      Assert
        (Database.Status.Is_Ok (R), "encrypted page file create succeeds");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      Database.Storage.Pages.Set_Payload
        (P,
         Database.Storage.Pages.Byte_Array'(0 => 1, 1 => 2, 2 => 3, 3 => 4));
      R := Database.Storage.File_IO.Write_Page (F, P);
      Assert (Database.Status.Is_Ok (R), "encrypted page write succeeds");
      R :=
        Database.Storage.File_IO.Read_Page
          (F, 2, Database.Storage.Pages.Table_Heap_Page, Back);
      Assert (Database.Status.Is_Ok (R), "encrypted page read succeeds");
      Assert
        (Database.Storage.Pages.Get_Id (Back) = 2,
         "encrypted page id survives");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "encrypted file closes");
   end Encrypted_File_IO_Pages_Round_Trip;

   procedure Persistent_Query_Image_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty_Q : constant Database.Queries.Query := Database.Queries.Empty;
      Q1      : Database.Queries.Query := Database.Queries.Empty;
      Q2      : Database.Queries.Query;
      R1      : Database.Rows.Row;
      R2      : Database.Rows.Row;
      Rows    : Database.Queries.Row_Vectors.Vector;
      Status  : Database.Status.Result;
   begin
      Status :=
        Database.Queries.From_Persistent_Image
          (Database.Queries.Persistent_Image (Empty_Q), Q2);
      Assert
        (Database.Status.Is_Ok (Status),
         "persistent empty query image restores");
      Assert
        (Database.Queries.Row_Count (Q2) = 0,
         "empty query body remains empty");

      Database.Rows.Append (R1, Database.Values.From_Integer (42));
      Database.Rows.Append
        (R1, Database.Values.From_Text ("durable view body åβ🙂"));
      Database.Rows.Append (R1, Database.Values.From_Boolean (True));
      Database.Rows.Append (R2, Database.Values.Null_Value);
      Database.Rows.Append (R2, Database.Values.From_Long_Integer (-99));
      Database.Queries.Append (Q1, R1);
      Database.Queries.Append (Q1, R2);

      Status :=
        Database.Queries.From_Persistent_Image
          (Database.Queries.Persistent_Image (Q1), Q2);
      Assert
        (Database.Status.Is_Ok (Status),
         "persistent non-empty query image restores");
      Assert
        (Database.Queries.Row_Count (Q2) = 2,
         "query row count survives durable image");
      Rows := Database.Queries.Rows (Q2);
      Assert
        (Database.Rows.Column_Count (Rows.Element (0)) = 3,
         "first query row columns survive");
      Assert
        (Database.Rows.Column_Count (Rows.Element (1)) = 2,
         "second query row columns survive");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Rows.Element (0), 0),
            Database.Values.From_Integer (42)),
         "integer value survives");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Rows.Element (0), 1),
            Database.Values.From_Text ("durable view body åβ🙂")),
         "Unicode text value survives");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Rows.Element (1), 1),
            Database.Values.From_Long_Integer (-99)),
         "long integer value survives");
   end Persistent_Query_Image_Round_Trips;

   procedure Encrypted_Page_Tamper_Fails_Closed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant Wide_Wide_String := "whole_project_tamper_pages.db";
      Key  : constant Database.Keys.Encryption_Key :=
        Database.Keys.Derive_Key ("whole-project", Database.Keys.Default_Salt);
      F    : Database.Storage.File_IO.File_Handle;
      P    : Database.Storage.Pages.Page;
      Back : Database.Storage.Pages.Page;
      R    : Database.Status.Result;
   begin
      R := Database.Storage.File_IO.Create_Encrypted (F, Path, Key);
      Assert
        (Database.Status.Is_Ok (R), "encrypted page file create succeeds");
      Database.Storage.Pages.Initialize
        (P, 2, Database.Storage.Pages.Table_Heap_Page);
      R := Database.Storage.File_IO.Write_Page (F, P);
      Assert (Database.Status.Is_Ok (R), "encrypted page write succeeds");
      R := Database.Storage.File_IO.Close (F);
      Assert (Database.Status.Is_Ok (R), "encrypted file closes");
      R :=
        Database.Encrypted_Persistence.Tamper_Byte
          (Path & ".page" & Natural'Wide_Wide_Image (2) & ".enc", 96);
      Assert (Database.Status.Is_Ok (R), "encrypted page artifact tampered");
      R := Database.Storage.File_IO.Open_Encrypted (F, Path, Key);
      Assert (Database.Status.Is_Ok (R), "encrypted page file reopens");
      R :=
        Database.Storage.File_IO.Read_Page
          (F, 2, Database.Storage.Pages.Table_Heap_Page, Back);
      Assert
        (not Database.Status.Is_Ok (R), "tampered encrypted page is rejected");
      R := Database.Storage.File_IO.Close (F);
      Assert
        (Database.Status.Is_Ok (R), "encrypted file closes after tamper test");
   end Encrypted_Page_Tamper_Fails_Closed;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Encrypted_File_IO_Pages_Round_Trip'Access,
         "encrypted File_IO pages round trip");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Persistent_Query_Image_Round_Trips'Access,
         "persistent query image round trip");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Encrypted_Page_Tamper_Fails_Closed'Access,
         "encrypted File_IO page tamper fails closed");
   end Register_Tests;
end Whole_Project_Integration_Tests;
