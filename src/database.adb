with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Locking;
with Database.Keys;
with Database.Catalog;
with Database.Extensions;
with Database.Functions;
with Database.Aggregate_Functions;
with Database.Collations;
with Database.Full_Text;
with Database.Full_Text.Tokenizers;
with Database.Full_Text.Ranking;
with Database.Validation_Hooks;
with Database.Replay;
with Database.WAL;

package body Database is
   protected body Read_Write_Lock is
      entry Begin_Read when True is
      begin
         Readers := Readers + 1;
      end Begin_Read;

      procedure Try_Begin_Read (Granted : out Boolean) is
      begin
         Granted := True;
         if Granted then
            Readers := Readers + 1;
         end if;
      end Try_Begin_Read;

      procedure End_Read is
      begin
         if Readers > 0 then
            Readers := Readers - 1;
         end if;
      end End_Read;

      entry Begin_Write when True is
      begin
         Waiting_Write := Waiting_Write + 1;
         requeue Acquire_Write;
      end Begin_Write;

      entry Acquire_Write when not Writer is
      begin
         if Waiting_Write > 0 then
            Waiting_Write := Waiting_Write - 1;
         end if;
         Writer := True;
      end Acquire_Write;

      procedure Try_Begin_Write (Granted : out Boolean) is
      begin
         Granted := not Writer;
         if Granted then
            Writer := True;
         end if;
      end Try_Begin_Write;

      procedure End_Write is
      begin
         Writer := False;
      end End_Write;

      function Active_Readers return Natural is (Readers);
      function Writer_Active return Boolean is (Writer);
      function Waiting_Writers return Natural is (Waiting_Write);
   end Read_Write_Lock;

   Next_Full_Text_State_Key : Natural := 1;
   Next_Catalog_State_Key : Natural := 1;

   procedure Assign_Catalog_State_Key (DB : in out Handle) is
   begin
      if DB.Catalog_State_Key_Value = 0 then
         DB.Catalog_State_Key_Value := Next_Catalog_State_Key;
         Next_Catalog_State_Key := Next_Catalog_State_Key + 1;
      end if;
      Database.Catalog.Select_Database (DB.Catalog_State_Key_Value);
      Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
      Database.Functions.Select_Database (DB.Catalog_State_Key_Value);
      Database.Aggregate_Functions.Select_Database (DB.Catalog_State_Key_Value);
      Database.Collations.Select_Database (DB.Catalog_State_Key_Value);
      Database.Full_Text.Tokenizers.Select_Database (DB.Catalog_State_Key_Value);
      Database.Full_Text.Ranking.Select_Database (DB.Catalog_State_Key_Value);
      Database.Validation_Hooks.Select_Database (DB.Catalog_State_Key_Value);
   end Assign_Catalog_State_Key;

   procedure Assign_Full_Text_State_Key (DB : in out Handle) is
   begin
      if DB.FT_State_Key = 0 then
         DB.FT_State_Key := Next_Full_Text_State_Key;
         Next_Full_Text_State_Key := Next_Full_Text_State_Key + 1;
      end if;
      Database.Full_Text.Select_Database (DB.FT_State_Key);
   end Assign_Full_Text_State_Key;

   procedure Open_In_Memory (DB : out Handle) is
   begin
      DB.Kind := In_Memory_Backend;
      DB.Last := Database.Status.Success;
      Assign_Catalog_State_Key (DB);
      Assign_Full_Text_State_Key (DB);
      Database.Catalog.Clear;
      Database.Full_Text.Clear;
      Database.Extensions.Clear;
   end Open_In_Memory;

   procedure Create (DB : out Handle; Path : Wide_Wide_String) is
   begin
      DB.Kind := Closed_Backend;
      DB.Last := Database.Storage.File_IO.Create (DB.File, Path);
      if Database.Status.Is_Ok (DB.Last) then
         DB.Kind := Persistent_Backend;
         Assign_Catalog_State_Key (DB);
         Assign_Full_Text_State_Key (DB);
         Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
         Database.Catalog.Clear;
         Database.Full_Text.Clear;
         Database.Extensions.Clear;
         DB.Last := Database.Catalog.Save (DB);
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Full_Text.Save (Path);
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
            DB.Last := Database.Extensions.Save (Path);
         end if;
      end if;
   end Create;

   procedure Create_Encrypted
     (DB   : out Handle;
      Path : Wide_Wide_String;
      Key  : Encryption_Key) is
   begin
      DB.Kind := Closed_Backend;
      DB.Last := Database.Storage.File_IO.Create_Encrypted (DB.File, Path, Key);
      if Database.Status.Is_Ok (DB.Last) then
         DB.Kind := Persistent_Backend;
         DB.Encryption_Enabled := True;
         DB.Encryption_Key_Id := Database.Keys.Identifier (Key);
         DB.WAL_Encryption_Enabled := True;
         Assign_Catalog_State_Key (DB);
         Assign_Full_Text_State_Key (DB);
         Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
         Database.Catalog.Clear;
         Database.Full_Text.Clear;
         Database.Extensions.Clear;
         DB.Last := Database.Catalog.Save (DB);
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Full_Text.Save (Path);
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
            DB.Last := Database.Extensions.Save (Path);
         end if;
      end if;
   end Create_Encrypted;

   procedure Open (DB : out Handle; Path : Wide_Wide_String) is
   begin
      DB.Kind := Closed_Backend;
      DB.Last := Database.Storage.File_IO.Open (DB.File, Path);
      if Database.Status.Is_Ok (DB.Last) then
         DB.Last := Database.Replay.Replay_WAL (Path, DB.File);
         if Database.Status.Is_Ok (DB.Last) then
            DB.Version := Natural'Max (DB.Version, Database.WAL.Max_Commit_Version (Path));
         end if;
      end if;
      if Database.Status.Is_Ok (DB.Last) then
         DB.Kind := Persistent_Backend;
         Assign_Catalog_State_Key (DB);
         Assign_Full_Text_State_Key (DB);
         Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
         DB.Last := Database.Catalog.Load (DB);
         if Database.Status.Is_Ok (DB.Last) then
            Database.Full_Text.Select_Database (DB.FT_State_Key);
            DB.Last := Database.Full_Text.Load (DB, Path);
            if Database.Status.Is_Ok (DB.Last) then
               DB.Version := Natural'Max (DB.Version, Database.Full_Text.Max_Commit_Version);
            end if;
            if Database.Status.Is_Ok (DB.Last) then
               Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
               DB.Last := Database.Extensions.Load (Path);
            end if;
         end if;
      else
         declare
            R : constant Database.Status.Result := Database.Storage.File_IO.Close (DB.File);
         begin
            null;
         end;
      end if;
   end Open;

   procedure Open_Encrypted
     (DB   : out Handle;
      Path : Wide_Wide_String;
      Key  : Encryption_Key) is
   begin
      DB.Kind := Closed_Backend;
      DB.Last := Database.Storage.File_IO.Open_Encrypted (DB.File, Path, Key);
      if Database.Status.Is_Ok (DB.Last) then
         DB.Last := Database.Replay.Replay_WAL (Path, DB.File);
         if Database.Status.Is_Ok (DB.Last) then
            DB.Version := Natural'Max (DB.Version, Database.WAL.Max_Commit_Version (Path));
         end if;
      end if;
      if Database.Status.Is_Ok (DB.Last) then
         DB.Kind := Persistent_Backend;
         DB.Encryption_Enabled := True;
         DB.Encryption_Key_Id := Database.Keys.Identifier (Key);
         DB.WAL_Encryption_Enabled := True;
         Assign_Catalog_State_Key (DB);
         Assign_Full_Text_State_Key (DB);
         Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
         DB.Last := Database.Catalog.Load (DB);
         if Database.Status.Is_Ok (DB.Last) then
            Database.Full_Text.Select_Database (DB.FT_State_Key);
            DB.Last := Database.Full_Text.Load (DB, Path);
            if Database.Status.Is_Ok (DB.Last) then
               DB.Version := Natural'Max (DB.Version, Database.Full_Text.Max_Commit_Version);
            end if;
            if Database.Status.Is_Ok (DB.Last) then
               Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
               DB.Last := Database.Extensions.Load (Path);
            end if;
         end if;
      else
         declare
            R : constant Database.Status.Result := Database.Storage.File_IO.Close (DB.File);
         begin
            null;
         end;
      end if;
   end Open_Encrypted;

   procedure Close (DB : in out Handle) is
   begin
      if DB.Lock.Active_Readers > 0 or else DB.Lock.Writer_Active then
         DB.Last := Database.Status.Failure
           (Database.Status.Transaction_Conflict, "cannot close database while transactions are active");
         return;
      end if;
      if DB.Kind = Persistent_Backend then
         DB.Last := Database.Catalog.Save (DB);
         if Database.Status.Is_Ok (DB.Last) then
            Database.Full_Text.Select_Database (DB.FT_State_Key);
            DB.Last := Database.Full_Text.Save (Database.Storage.File_IO.Path (DB.File));
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
            DB.Last := Database.Extensions.Save (Database.Storage.File_IO.Path (DB.File));
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Storage.File_IO.Flush (DB.File);
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.WAL.Delete (Database.Storage.File_IO.Path (DB.File));
         end if;
         declare
            R : constant Database.Status.Result := Database.Storage.File_IO.Close (DB.File);
         begin
            if not Database.Status.Is_Ok (R) then
               DB.Last := R;
            end if;
         end;
      else
         DB.Last := Database.Status.Success;
      end if;

      --  Full-text postings are handle-scoped transient state. Definitions are
      --  durable catalog state and persistent postings are rebuilt on open, so
      --  the in-process posting vectors must be discarded when the owning
      --  handle is closed. This prevents stale state from a closed handle from
      --  being visible if another handle later receives a different state key.
      if DB.FT_State_Key /= 0 then
         Database.Full_Text.Select_Database (DB.FT_State_Key);
         Database.Full_Text.Clear;
      end if;
      if DB.Catalog_State_Key_Value /= 0 then
         Database.Extensions.Select_Database (DB.Catalog_State_Key_Value);
         Database.Extensions.Clear;
      end if;
      if DB.Catalog_State_Key_Value /= 0 then
         Database.Catalog.Drop_Database (DB.Catalog_State_Key_Value);
         Database.Extensions.Drop_Database (DB.Catalog_State_Key_Value);
      end if;

      DB.Kind := Closed_Backend;
   end Close;
   function Is_Open (DB : Handle) return Boolean is
   begin
      return DB.Kind /= Closed_Backend;
   end Is_Open;
   function Last_Operation_Succeeded (DB : Handle) return Boolean is
   begin
      return Database.Status.Is_Ok (DB.Last);
   end Last_Operation_Succeeded;
   function Backend (DB : Handle) return Backend_Kind is
   begin
      if DB.Kind = Closed_Backend then
         return Closed_Backend;
      end if;
      return DB.Kind;
   end Backend;
   function Last_Result (DB : Handle) return Result is
   begin
      return DB.Last;
   end Last_Result;

   function Commit_Version (DB : Handle) return Natural is
   begin
      return DB.Version;
   end Commit_Version;

   function Full_Text_State_Key (DB : Handle) return Natural is
   begin
      return DB.FT_State_Key;
   end Full_Text_State_Key;

   function Catalog_State_Key (DB : Handle) return Natural is
   begin
      return DB.Catalog_State_Key_Value;
   end Catalog_State_Key;
end Database;
