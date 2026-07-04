with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Catalog;
with Database.Status;
with Database.Full_Text;
with Database.Rows;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Pages;
with Database.Storage.Table_Heap;
with Database.WAL;
with Database.Backup_Format;
with Database.Invariant_Checks;
with Database.Indexes;
with Database.Indexes.BTree;
with Database.Extensions;
with Database.Values;
with Database.Types;
with Ada.Containers.Indefinite_Vectors;

package body Database.Check is
   use type Ada.Containers.Count_Type;
   use type Database.Values.Value;
   use type Database.Indexes.Ordering;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Database.Storage.Pages;
   use type Database.Types.Value_Kind;

   package Value_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Database.Values.Value);

   procedure Add_Error
     (Result  : in out Check_Result;
      Kind    : Check_Error_Kind;
      Message : Wide_Wide_String;
      Page    : Page_Id := Invalid_Page_Id) is
   begin
      Result.Success := False;
      Result.Errors.Append
        (Check_Error'(Kind    => Kind,
          Message => To_Unbounded_Wide_Wide_String (Message),
          Page    => Page));
   end Add_Error;

   procedure Merge (Into : in out Check_Result; From : Check_Result) is
   begin
      if not From.Success then
         Into.Success := False;
      end if;
      for E of From.Errors loop
         Into.Errors.Append (E);
      end loop;
   end Merge;

   function Kind_Name (R : Database.Status.Result) return Wide_Wide_String is
      pragma Unreferenced (R);
   begin
      return "validation failed";
   end Kind_Name;

   type Boolean_Array is array (Natural range <>) of Boolean;

   procedure Mark (Reachable : in out Boolean_Array; Id : Page_Id) is
   begin
      if Natural (Id) in Reachable'Range then
         Reachable (Natural (Id)) := True;
      end if;
   end Mark;

   function Check_Catalog
     (Tx : in out Database.Transactions.Transaction) return Check_Result is
      R  : Check_Result;
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
   begin
      if DB = null or else not Database.Transactions.Can_Read (Tx) then
         Add_Error (R, Internal_Error, "check requires an active transaction");
         return R;
      end if;

      declare
         Seen_Table_Names : array (0 .. Database.Catalog.Table_Count) of Unbounded_Wide_Wide_String;
         Seen_Table_Ids   : array (0 .. Database.Catalog.Table_Count) of Natural := (others => 0);
         Seen_Count       : Natural := 0;
      begin
         if Database.Catalog.Table_Count > 0 then
         for I in 0 .. Database.Catalog.Table_Count - 1 loop
            declare
               S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (I);
            begin
               if S.Table_Id = 0 then
                  Add_Error (R, Invalid_Catalog, "table has invalid id");
               end if;
               if Length (S.Name) = 0 then
                  Add_Error (R, Invalid_Catalog, "table has empty name");
               end if;
               if Seen_Count > 0 then
                  for J in 0 .. Seen_Count - 1 loop
                     if Seen_Table_Ids (J) = S.Table_Id then
                        Add_Error (R, Invalid_Catalog, "duplicate table id");
                     end if;
                     if To_Wide_Wide_String (Seen_Table_Names (J)) = To_Wide_Wide_String (S.Name) then
                        Add_Error (R, Invalid_Catalog, "duplicate table name");
                     end if;
                  end loop;
               end if;
               Seen_Table_Ids (Seen_Count) := S.Table_Id;
               Seen_Table_Names (Seen_Count) := S.Name;
               Seen_Count := Seen_Count + 1;

               declare
                  Column_Ids : array (0 .. Database.Schema.Column_Count (S)) of Natural := (others => 0);
                  Column_Count : Natural := 0;
                  PK_Count : Natural := 0;
               begin
                  for C of S.Columns loop
                     if Length (C.Name) = 0 then
                        Add_Error (R, Schema_Error, "column has empty name");
                     end if;
                     if Column_Count > 0 then
                        for K in 0 .. Column_Count - 1 loop
                           if Column_Ids (K) = C.Id then
                              Add_Error (R, Schema_Error, "duplicate column id");
                           end if;
                        end loop;
                     end if;
                     Column_Ids (Column_Count) := C.Id;
                     Column_Count := Column_Count + 1;
                     if C.Primary_Key then
                        PK_Count := PK_Count + 1;
                        if C.Nullable then
                           Add_Error (R, Schema_Error, "primary key column is nullable");
                        end if;
                     end if;
                  end loop;
                  if PK_Count > 1 then
                     Add_Error (R, Schema_Error, "more than one primary key column");
                  end if;
               end;

               for IX of S.Indexes loop
                  if IX.Table_Id /= S.Table_Id then
                     Add_Error (R, Invalid_Catalog, "index references wrong table id", IX.Root_Page);
                  end if;
                  if IX.Column_Id /= 0 and then IX.Column_Id >= Database.Schema.Next_Id (S) then
                     Add_Error (R, Invalid_Catalog, "index references unknown column", IX.Root_Page);
                  end if;
               end loop;
            end;
         end loop;
         end if;
      end;
      return R;
   exception
      when others =>
         Add_Error (R, Internal_Error, "catalog check raised unexpectedly");
         return R;
   end Check_Catalog;

   function Check_Table
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema) return Check_Result is
      R  : Check_Result;
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      SR : Database.Status.Result;
   begin
      if DB = null or else not Database.Transactions.Can_Read (Tx) then
         Add_Error (R, Internal_Error, "table check requires an active transaction");
         return R;
      end if;
      if Database.Backend (DB.all) = Database.Persistent_Backend then
         SR := Database.Storage.Table_Heap.Validate_Table_Heap
           (DB.File, Page_Id (Schema.Heap_First_Page), Schema);
         if not Database.Status.Is_Ok (SR) then
            Add_Error (R, Invalid_Row, To_Wide_Wide_String (SR.Message), Page_Id (Schema.Heap_First_Page));
         end if;

         if Schema.Heap_First_Page /= Natural (Invalid_Page_Id)
           and then Database.Schema.Primary_Key_Index (Schema) /= Natural'Last
         then
            declare
               C    : Database.Storage.Table_Heap.Heap_Cursor;
               Keys : Value_Vectors.Vector;
               Pos  : constant Natural := Database.Schema.Primary_Key_Index (Schema);
            begin
               SR := Database.Storage.Table_Heap.Scan_First
                 (Tx, DB.File, Page_Id (Schema.Heap_First_Page), Schema, C);
               if not Database.Status.Is_Ok (SR) then
                  Add_Error (R, Invalid_Row, To_Wide_Wide_String (SR.Message), Page_Id (Schema.Heap_First_Page));
               else
                  while C.Has_Row loop
                     declare
                        K : constant Database.Values.Value := Database.Rows.Get (C.Row, Pos);
                     begin
                        if K.Kind = Database.Types.Null_Value then
                           Add_Error (R, Invalid_Row, "primary key row contains null", C.Current_Page);
                        end if;
                        if Keys.Length > 0 then
                           for Existing of Keys loop
                              declare
                                 O  : Database.Indexes.Ordering;
                                 KR : constant Database.Status.Result  :=
                                   Database.Indexes.Compare (Existing, K, O);
                              begin
                                 if Database.Status.Is_Ok (KR) and then O = Database.Indexes.Equal then
                                    Add_Error (R, Duplicate_Primary_Key, "duplicate primary key in table heap",
                                      C.Current_Page);
                                 end if;
                              end;
                           end loop;
                        end if;
                        Keys.Append (K);
                     end;
                     SR := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Schema, C);
                     exit when not Database.Status.Is_Ok (SR);
                  end loop;
                  if not Database.Status.Is_Ok (SR) then
                     Add_Error (R, Invalid_Row, To_Wide_Wide_String (SR.Message), Page_Id (Schema.Heap_First_Page));
                  end if;
               end if;
            exception
               when others =>
                  Add_Error (R, Invalid_Row, "table row scan failed defensively", Page_Id (Schema.Heap_First_Page));
            end;
         end if;
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Internal_Error, "table check raised unexpectedly", Page_Id (Schema.Heap_First_Page));
         return R;
   end Check_Table;

   function Check_Index
     (Tx     : in out Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema;
      Index  : Database.Indexes.Index_Metadata) return Check_Result is
      pragma Unreferenced (Schema);
      R  : Check_Result;
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      SR : Database.Status.Result;
   begin
      if DB = null or else not Database.Transactions.Can_Read (Tx) then
         Add_Error (R, Internal_Error, "index check requires an active transaction");
         return R;
      end if;
      if Database.Backend (DB.all) = Database.Persistent_Backend and then Index.Root_Page /= Invalid_Page_Id then
         SR := Database.Indexes.Validate_Index_Metadata (Index);
         if not Database.Status.Is_Ok (SR) then
            Add_Error (R, Invalid_Index, To_Wide_Wide_String (SR.Message), Index.Root_Page);
         end if;
         SR := Database.Indexes.BTree.Validate (DB.File, Index.Root_Page);
         if not Database.Status.Is_Ok (SR) then
            Add_Error (R, Invalid_Index, To_Wide_Wide_String (SR.Message), Index.Root_Page);
         end if;
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Internal_Error, "index check raised unexpectedly", Index.Root_Page);
         return R;
   end Check_Index;

   function Check_Database
     (Tx : in out Database.Transactions.Transaction) return Check_Result is
      R  : Check_Result;
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
   begin
      if DB = null or else not Database.Transactions.Can_Read (Tx) then
         Add_Error (R, Internal_Error, "database check requires an active transaction");
         return R;
      end if;

      Merge (R, Check_Catalog (Tx));
      Merge (R, Check_Encryption_Metadata (Tx));

      if Database.Catalog.Table_Count > 0 then
         for I in 0 .. Database.Catalog.Table_Count - 1 loop
            declare
               S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (I);
            begin
               Merge (R, Check_Table (Tx, S));
               if S.Primary_Index_Root /= Natural (Invalid_Page_Id) then
                  declare
                     Pos : constant Natural := Database.Schema.Primary_Key_Index (S);
                     Col : constant Database.Schema.Column  :=
                       (if Pos = Natural'Last then S.Columns.Element (0) else S.Columns.Element (Pos));
                     PK : Database.Indexes.Index_Metadata  :=
                       (Id        => 1,
                        Table_Id  => S.Table_Id,
                        Name      => To_Unbounded_Wide_Wide_String ("primary"),
                        Kind      => Database.Indexes.Primary_Key_Index,
                        Root_Page => Page_Id (S.Primary_Index_Root),
                        Unique    => True,
                        Column_Id => Col.Id,
                        Key_Kind  => Col.Kind,
                        others    => <>);
                  begin
                     Merge (R, Check_Index (Tx, S, PK));
                  exception
                     when others =>
                        Add_Error (R, Invalid_Index, "primary index metadata is inconsistent",
                          Page_Id (S.Primary_Index_Root));
                  end;
               end if;
               for IX of S.Indexes loop
                  Merge (R, Check_Index (Tx, S, IX));
               end loop;
            end;
         end loop;
      end if;

      if Database.Backend (DB.all) = Database.Persistent_Backend then
         declare
            Count : constant Natural := Database.Storage.File_IO.Page_Count (DB.File);
            Reachable : Boolean_Array (0 .. Count) := (others => False);
            Free     : Boolean_Array (0 .. Count) := (others => False);
            P        : Page;
            SR       : Database.Status.Result;
         begin
            if Count = 0 then
               Add_Error (R, Missing_Page, "database file has no header page");
               return R;
            end if;
            SR := Database.Storage.Free_List.Validate_Free_List (DB.Page_Allocator, DB.File);
            if not Database.Status.Is_Ok (SR) then
               Add_Error (R, Invalid_Free_List, To_Wide_Wide_String (SR.Message));
            end if;
            Mark (Reachable, 0);
            Mark (Reachable, 1);
            if Database.Catalog.Table_Count > 0 then
            for I in 0 .. Database.Catalog.Table_Count - 1 loop
               declare
                  S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (I);
               begin
                  declare
                     Id : Page_Id := Page_Id (S.Heap_First_Page);
                  Guard : Natural := 0;
                  begin
                     while Id /= Invalid_Page_Id and then Guard <= Count loop
                        if Natural (Id) >= Count then
                           Add_Error (R, Missing_Page, "table heap references missing page", Id);
                           exit;
                        end if;
                        Mark (Reachable, Id);
                        SR := Database.Storage.File_IO.Read_Page (DB.File, Id, Table_Heap_Page, P);
                        exit when not Database.Status.Is_Ok (SR);
                        Id := Get_Next (P);
                        Guard := Guard + 1;
                     end loop;
                     if Guard > Count then
                        Add_Error (R, Invalid_Page, "loop in table heap pages", Page_Id (S.Heap_First_Page));
                     end if;
                  end;
                  if S.Primary_Index_Root /= Natural (Invalid_Page_Id) then
                     declare
                        Id : Page_Id := Page_Id (S.Primary_Index_Root);
                     Guard : Natural := 0;
                     begin
                        while Id /= Invalid_Page_Id and then Guard <= Count loop
                           if Natural (Id) >= Count then
                              Add_Error (R, Missing_Page, "primary index references missing page", Id);
                              exit;
                           end if;
                           Mark (Reachable, Id);
                           SR := Database.Storage.File_IO.Read_Page (DB.File, Id, BTree_Leaf_Page, P);
                           exit when not Database.Status.Is_Ok (SR);
                           Id := Get_Next (P);
                           Guard := Guard + 1;
                        end loop;
                        if Guard > Count then
                           Add_Error (R, Invalid_Index, "loop in primary index leaf chain",
                             Page_Id (S.Primary_Index_Root));
                        end if;
                     end;
                  end if;
                  for IX of S.Indexes loop
                     declare
                        Id : Page_Id := IX.Root_Page;
                     Guard : Natural := 0;
                     begin
                        while Id /= Invalid_Page_Id and then Guard <= Count loop
                           if Natural (Id) >= Count then
                              Add_Error (R, Missing_Page, "index references missing page", Id);
                              exit;
                           end if;
                           Mark (Reachable, Id);
                           SR := Database.Storage.File_IO.Read_Page (DB.File, Id, BTree_Leaf_Page, P);
                           exit when not Database.Status.Is_Ok (SR);
                           Id := Get_Next (P);
                           Guard := Guard + 1;
                        end loop;
                        if Guard > Count then
                           Add_Error (R, Invalid_Index, "loop in index leaf chain", IX.Root_Page);
                        end if;
                     end;
                  end loop;
               end;
            end loop;
            end if;
            for N in 0 .. Count - 1 loop
               SR := Database.Storage.File_IO.Read_Raw_Page (DB.File, Page_Id (N), P);
               if not Database.Status.Is_Ok (SR) then
                  Add_Error (R, Corrupt_Page, Kind_Name (SR), Page_Id (N));
               else
                  if Natural (Get_Id (P)) /= N then
                     Add_Error (R, Invalid_Page, "page id does not match file position", Page_Id (N));
                  end if;
                  SR := Database.Storage.Pages.Validate (P, Page_Id (N), Get_Kind (P));
                  if not Database.Status.Is_Ok (SR) then
                     Add_Error (R, Corrupt_Page, To_Wide_Wide_String (SR.Message), Page_Id (N));
                  end if;
                  if Get_Kind (P) = Free_Page then
                     Free (N) := True;
                  end if;
               end if;
            end loop;
            for N in 2 .. Count - 1 loop
               if not Reachable (N) and then not Free (N) then
                  Add_Error (R, Orphan_Page, "allocated page is not reachable from catalog roots", Page_Id (N));
               end if;
               if Reachable (N) and then Free (N) then
                  Add_Error (R, Invalid_Free_List, "free page is referenced by an active structure", Page_Id (N));
               end if;
            end loop;
         end;
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Internal_Error, "database check raised unexpectedly");
         return R;
   end Check_Database;

   function Check_Full_Text_Index
     (Tx   : in out Database.Transactions.Transaction;
      Name : Wide_Wide_String) return Check_Result is
      R : Check_Result;
   begin
      declare
         FT_Result : constant Database.Status.Result := Database.Full_Text.Check_Index (Tx, Name);
      begin
         if not Database.Status.Is_Ok (FT_Result) then
            Add_Error  (R,
              Invalid_Full_Text_Index,
              Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (FT_Result.Message));
         end if;
      end;
      return R;
   end Check_Full_Text_Index;

   function Check_Encryption_Metadata
     (Tx : in out Database.Transactions.Transaction) return Check_Result is
      R  : Check_Result;
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
   begin
      if DB = null or else not Database.Transactions.Can_Read (Tx) then
         Add_Error (R, Internal_Error, "encryption metadata check requires an active transaction");
         return R;
      end if;

      if DB.Encryption_Enabled then
         if DB.Encryption_Format_Version /= 1 then
            Add_Error (R, Invalid_Encryption_Metadata, "unsupported encryption format version");
         end if;
         if DB.Encryption_Key_Id = 0 then
            Add_Error (R, Invalid_Encryption_Metadata, "encrypted database has no key id");
         end if;
         if not DB.WAL_Encryption_Enabled then
            Add_Error (R, Invalid_Encryption_Metadata, "encrypted database has unencrypted WAL metadata");
         end if;
      else
         if DB.Encryption_Key_Id /= 0 then
            Add_Error (R, Invalid_Encryption_Metadata, "unencrypted database retains a key id");
         end if;
         if DB.WAL_Encryption_Enabled then
            Add_Error (R, Invalid_Encryption_Metadata, "unencrypted database reports encrypted WAL");
         end if;
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Internal_Error, "encryption metadata check raised unexpectedly");
         return R;
   end Check_Encryption_Metadata;

   function Check_WAL
     (Database_Path : Wide_Wide_String) return Check_Result is
      R  : Check_Result;
      SR : constant Database.Status.Result := Database.WAL.Validate (Database_Path);
   begin
      if not Database.Status.Is_Ok (SR) then
         Add_Error
           (R,
            Invalid_WAL,
            To_Wide_Wide_String (SR.Message));
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Invalid_WAL, "WAL check raised unexpectedly");
         return R;
   end Check_WAL;

   function Check_Backup_Manifest
     (Backup_Path : Wide_Wide_String) return Check_Result is
      R    : Check_Result;
      Item : Database.Backup_Format.Manifest;
      SR   : Database.Status.Result;
   begin
      SR := Database.Backup_Format.Read_Manifest (Backup_Path, Item);
      if not Database.Status.Is_Ok (SR) then
         Add_Error
           (R,
            Invalid_Backup_Manifest,
            To_Wide_Wide_String (SR.Message));
         return R;
      end if;

      SR := Database.Backup_Format.Validate_Manifest (Backup_Path, Item);
      if not Database.Status.Is_Ok (SR) then
         Add_Error
           (R,
            Invalid_Backup_Manifest,
            To_Wide_Wide_String (SR.Message));
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Invalid_Backup_Manifest, "backup manifest check raised unexpectedly");
         return R;
   end Check_Backup_Manifest;

   function Check_Import_Header
     (Header  : Wide_Wide_String;
      Version : Natural) return Check_Result is
      IR : constant Database.Invariant_Checks.Check_Report  :=
        Database.Invariant_Checks.Validate_Import_Header (Header, Version);
      R  : Check_Result;
   begin
      if not Database.Status.Is_Ok (IR.Result) then
         Add_Error
           (R,
            Invalid_Import_Structure,
            To_Wide_Wide_String (IR.Result.Message));
      end if;
      return R;
   exception
      when others =>
         Add_Error (R, Invalid_Import_Structure, "import header check raised unexpectedly");
         return R;
   end Check_Import_Header;

   function Check_Encryption_Metadata
     (Format_Version : Natural;
      Key_Id         : Natural;
      Authenticated  : Boolean) return Check_Result is
      ER : constant Database.Invariant_Checks.Check_Report  :=
        Database.Invariant_Checks.Validate_Encryption_Metadata
          (Format_Version, Key_Id, Authenticated);
      R  : Check_Result;
   begin
      if not Database.Status.Is_Ok (ER.Result) then
         Add_Error
           (R,
            Invalid_Encryption_Metadata,
            To_Wide_Wide_String (ER.Result.Message));
      end if;
      return R;
   exception
      when others =>
         Add_Error
           (R, Invalid_Encryption_Metadata,
            "encryption metadata artifact check raised unexpectedly");
         return R;
   end Check_Encryption_Metadata;

   function Check_Extension_Metadata
     (Tx : in out Database.Transactions.Transaction) return Check_Result is
      R : Check_Result;
      pragma Unreferenced (Tx);
      SR : constant Database.Status.Result := Database.Extensions.Validate_Dependencies;
   begin
      if not Database.Status.Is_Ok (SR) then
         Add_Error (R, Invalid_Extension_Metadata, To_Wide_Wide_String (SR.Message));
      end if;
      return R;
   end Check_Extension_Metadata;
end Database.Check;
