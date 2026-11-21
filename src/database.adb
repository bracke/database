with Database.Status;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Keys;
with Database.Catalog;
with Database.Exclusive;
with Database.Events;
with Database.Extensions;
with Database.Functions;
with Database.Aggregate_Functions;
with Database.Collations;
with Database.Full_Text;
with Database.Full_Text.Tokenizers;
with Database.Full_Text.Ranking;
with Database.Validation_Hooks;
with Database.Memory_Store;
with Database.MVCC;
with Database.Transactions;
with Database.WAL;

package body Database is
   protected body Read_Write_Lock is
      entry Begin_Read when not Closing is
      begin
         Readers := Readers + 1;
      end Begin_Read;

      procedure Try_Begin_Read (Granted : out Boolean) is
      begin
         Granted := not Closing;
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

      --  A waiting writer stays queued on its own entry, so it can be aborted or time out, and the queues count the
      --  waiting writers.
      entry Begin_Write when not Writer is
      begin
         Writer := True;
         Holder := Begin_Write'Caller;
      end Begin_Write;

      procedure Try_Begin_Write (Granted : out Boolean) is
      begin
         Granted := not Writer;
         if Granted then
            Writer := True;
            Holder := Ada.Task_Identification.Current_Task;
         end if;
      end Try_Begin_Write;

      entry Begin_Exclusive when not Writer is
      begin
         Writer := True;
         Exclusive := True;
         Holder := Begin_Exclusive'Caller;
      end Begin_Exclusive;

      procedure Try_Begin_Exclusive (Granted : out Boolean) is
      begin
         Granted := not Writer;
         if Granted then
            Writer := True;
            Exclusive := True;
            Holder := Ada.Task_Identification.Current_Task;
         end if;
      end Try_Begin_Exclusive;

      procedure Try_Begin_Close (Granted : out Boolean) is
      begin
         Granted := not Writer and then Readers = 0;
         if Granted then
            Writer := True;
            Exclusive := True;
            Closing := True;
            Holder := Ada.Task_Identification.Current_Task;
         end if;
      end Try_Begin_Close;

      procedure End_Write is
      begin
         Writer := False;
         Exclusive := False;
         Closing := False;
         Holder := Ada.Task_Identification.Null_Task_Id;
      end End_Write;

      function Active_Readers return Natural is (Readers);
      function Writer_Active return Boolean is (Writer);
      function Exclusive_Active return Boolean is (Writer and then Exclusive);

      function Held_By_Current_Task return Boolean is
        (Writer and then Ada.Task_Identification."=" (Holder, Ada.Task_Identification.Current_Task));

      function Own_Transaction_Writing return Boolean is (not Exclusive and then Held_By_Current_Task);
      function Closing_By_Current_Task return Boolean is (Closing and then Held_By_Current_Task);
      function Waiting_Writers return Natural is (Begin_Write'Count + Begin_Exclusive'Count);
   end Read_Write_Lock;

   --  State keys are process-global; opening databases from several tasks must
   --  not hand out the same key, so allocation is atomic.
   protected State_Key_Counter is
      procedure Next_Catalog (Key : out Natural);
      procedure Next_Full_Text (Key : out Natural);
   private
      Next_Catalog_Value   : Natural := 1;
      Next_Full_Text_Value : Natural := 1;
   end State_Key_Counter;

   protected body State_Key_Counter is
      procedure Next_Catalog (Key : out Natural) is
      begin
         Key := Next_Catalog_Value;
         Next_Catalog_Value := Next_Catalog_Value + 1;
      end Next_Catalog;
      procedure Next_Full_Text (Key : out Natural) is
      begin
         Key := Next_Full_Text_Value;
         Next_Full_Text_Value := Next_Full_Text_Value + 1;
      end Next_Full_Text;
   end State_Key_Counter;

   --  Allocate the handle's catalog state key if it does not have one yet.
   --  Per-subsystem state is resolved lazily from this key on first use; there
   --  is no longer a process-global "current database" selection to warm.
   procedure Assign_Catalog_State_Key (DB : in out Handle) is
   begin
      if DB.Catalog_State_Key_Value = 0 then
         State_Key_Counter.Next_Catalog (DB.Catalog_State_Key_Value);
      end if;
   end Assign_Catalog_State_Key;

   procedure Assign_Full_Text_State_Key (DB : in out Handle) is
   begin
      if DB.FT_State_Key = 0 then
         State_Key_Counter.Next_Full_Text (DB.FT_State_Key);
      end if;
   end Assign_Full_Text_State_Key;

   procedure Open_In_Memory (DB : out Handle) is
   begin
      DB.Kind := In_Memory_Backend;
      DB.Last := Database.Status.Success;
      Assign_Catalog_State_Key (DB);
      Assign_Full_Text_State_Key (DB);
      Database.Catalog.Clear (DB.Catalog_State_Key_Value);
      Database.Full_Text.Clear (DB.FT_State_Key);
      Database.Extensions.Clear (DB.Catalog_State_Key_Value);
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
         Database.Catalog.Clear (DB.Catalog_State_Key_Value);
         Database.Full_Text.Clear (DB.FT_State_Key);
         Database.Extensions.Clear (DB.Catalog_State_Key_Value);
         DB.Last := Database.Catalog.Save (DB);
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Full_Text.Save (DB.FT_State_Key, Path);
         end if;
         if Database.Status.Is_Ok (DB.Last) then
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
         Database.Catalog.Clear (DB.Catalog_State_Key_Value);
         Database.Full_Text.Clear (DB.FT_State_Key);
         Database.Extensions.Clear (DB.Catalog_State_Key_Value);
         DB.Last := Database.Catalog.Save (DB);
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Full_Text.Save (DB.FT_State_Key, Path);
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Extensions.Save (Path);
         end if;
      end if;
   end Create_Encrypted;

   --  Recover the file of DB from its WAL and take over what the WAL knows besides pages.
   function Recover (DB : in out Handle; Path : Wide_Wide_String) return Result is
      Summary : Database.WAL.Recovery_Summary;
      R       : constant Result := Database.WAL.Recover (Path, DB.File, Summary);
   begin
      if Database.Status.Is_Ok (R) then
         DB.Version := Natural'Max (DB.Version, Summary.Max_Commit_Version);
         --  Rebuild the MVCC committed-transaction map from the replayed WAL
         --  so visibility and reclamation treat recovered committed rows
         --  correctly (a fresh process starts with an empty map).
         for C in Summary.Committed.Iterate loop
            Database.MVCC.Mark_Committed
              (Database.WAL.Transaction_Maps.Key (C), Database.WAL.Transaction_Maps.Element (C));
         end loop;
         --  The WAL keeps the records of every transaction since the last checkpoint, rolled back or not, and
         --  replay tells transactions apart by id.
         Database.Transactions.Reserve_Ids_Through (Summary.Max_Transaction_Id);
      end if;
      return R;
   end Recover;

   procedure Open (DB : out Handle; Path : Wide_Wide_String) is
   begin
      DB.Kind := Closed_Backend;
      DB.Last := Database.Storage.File_IO.Open (DB.File, Path);
      if Database.Status.Is_Ok (DB.Last) then
         DB.Last := Recover (DB, Path);
      end if;
      if Database.Status.Is_Ok (DB.Last) then
         DB.Kind := Persistent_Backend;
         Assign_Catalog_State_Key (DB);
         Assign_Full_Text_State_Key (DB);
         Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
         DB.Last := Database.Catalog.Load (DB);
         if Database.Status.Is_Ok (DB.Last) then
            --  Never hand out a transaction id that a persisted row still
            --  references; Catalog.Load derived the high-water mark from the
            --  heap (covers both replayed-WAL and clean-checkpoint reopens).
            Database.Transactions.Reserve_Ids_Through (DB.Max_Persisted_Tx);
            DB.Last := Database.Full_Text.Load (DB, Path);
            if Database.Status.Is_Ok (DB.Last) then
               DB.Version := Natural'Max
                 (DB.Version, Database.Full_Text.Max_Commit_Version (DB.FT_State_Key));
            end if;
            if Database.Status.Is_Ok (DB.Last) then
               DB.Last := Database.Extensions.Load (Path);
            end if;
         end if;
      else
         --  Open validation failed; close the handle but keep DB.Last, which
         --  already holds the reason, rather than the close status.
         declare
            R : constant Database.Status.Result := Database.Storage.File_IO.Close (DB.File);
            pragma Unreferenced (R);
         begin
            null;
         end;
      end if;
   end Open;

   procedure Open_Read_Only (DB : out Handle; Path : Wide_Wide_String) is
   begin
      DB.Kind := Closed_Backend;
      DB.Read_Only_Mode := True;
      DB.Last := Database.Storage.File_IO.Open_Read_Only (DB.File, Path);
      if Database.Status.Is_Ok (DB.Last) and then Database.WAL.Exists (Path) then
         DB.Last := Database.Status.Failure
           (Database.Status.Recovery_Required,
            "database has a write-ahead log and requires recovery");
      end if;
      if Database.Status.Is_Ok (DB.Last) then
         DB.Kind := Persistent_Backend;
         Assign_Catalog_State_Key (DB);
         Assign_Full_Text_State_Key (DB);
         Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
         DB.Last := Database.Catalog.Load (DB);
         if Database.Status.Is_Ok (DB.Last) then
            Database.Transactions.Reserve_Ids_Through (DB.Max_Persisted_Tx);
            DB.Last := Database.Full_Text.Load (DB, Path);
         end if;
         if Database.Status.Is_Ok (DB.Last) then
            DB.Last := Database.Extensions.Load (Path);
         end if;
      end if;
      if not Database.Status.Is_Ok (DB.Last) then
         declare
            Saved : constant Database.Status.Result := DB.Last;
            R     : constant Database.Status.Result := Database.Storage.File_IO.Close (DB.File);
            pragma Unreferenced (R);
         begin
            if DB.FT_State_Key /= 0 then
               Database.Full_Text.Clear (DB.FT_State_Key);
            end if;
            if DB.Catalog_State_Key_Value /= 0 then
               Database.Catalog.Drop_Database (DB.Catalog_State_Key_Value);
               Database.Extensions.Drop_Database (DB.Catalog_State_Key_Value);
            end if;
            DB.Last := Saved;
            DB.Kind := Closed_Backend;
            DB.Read_Only_Mode := False;
         end;
      end if;
   end Open_Read_Only;

   procedure Open_Encrypted
     (DB   : out Handle;
      Path : Wide_Wide_String;
      Key  : Encryption_Key) is
   begin
      DB.Kind := Closed_Backend;
      DB.Last := Database.Storage.File_IO.Open_Encrypted (DB.File, Path, Key);
      if Database.Status.Is_Ok (DB.Last) then
         DB.Last := Recover (DB, Path);
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
            --  Never hand out a transaction id that a persisted row still
            --  references; Catalog.Load derived the high-water mark from the
            --  heap (covers both replayed-WAL and clean-checkpoint reopens).
            Database.Transactions.Reserve_Ids_Through (DB.Max_Persisted_Tx);
            DB.Last := Database.Full_Text.Load (DB, Path);
            if Database.Status.Is_Ok (DB.Last) then
               DB.Version := Natural'Max
                 (DB.Version, Database.Full_Text.Max_Commit_Version (DB.FT_State_Key));
            end if;
            if Database.Status.Is_Ok (DB.Last) then
               DB.Last := Database.Extensions.Load (Path);
            end if;
         end if;
      else
         --  Open validation failed; close the handle but keep DB.Last, which
         --  already holds the reason, rather than the close status.
         declare
            R : constant Database.Status.Result := Database.Storage.File_IO.Close (DB.File);
            pragma Unreferenced (R);
         begin
            null;
         end;
      end if;
   end Open_Encrypted;

   procedure Close (DB : in out Handle) is
      --  Save what the handle holds in memory, close the file and mark the handle closed, while no one else reads or
      --  writes: a reader or writer waiting for the lock then finds the handle closed.
      function Save_And_Close (Target : in out Handle) return Database.Status.Result is
         Result : Database.Status.Result := Database.Status.Success;
      begin
         Database.Events.Emit_Event
           ((Database.Events.Close_Start,
             Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("close start")));
         if Target.Kind = Persistent_Backend then
            --  The process lock is released below; another process may append to the WAL afterwards.
            Database.WAL.Forget_Trusted (Database.Storage.File_IO.Path (Target.File));
            if not Target.Read_Only_Mode then
               Result := Database.Catalog.Save_Holding_Lock (Target);
               if Database.Status.Is_Ok (Result) then
                  Result := Database.Full_Text.Save
                    (Target.FT_State_Key, Database.Storage.File_IO.Path (Target.File));
               end if;
               if Database.Status.Is_Ok (Result) then
                  Result := Database.Extensions.Save (Database.Storage.File_IO.Path (Target.File));
               end if;
               if Database.Status.Is_Ok (Result) then
                  Result := Database.Storage.File_IO.Flush (Target.File);
               end if;
               if Database.Status.Is_Ok (Result) then
                  Result := Database.WAL.Delete (Database.Storage.File_IO.Path (Target.File));
               end if;
            end if;
            declare
               R : constant Database.Status.Result := Database.Storage.File_IO.Close (Target.File);
            begin
               if not Database.Status.Is_Ok (R) then
                  Result := R;
               end if;
            end;
         end if;

         --  Full-text postings are handle-scoped transient state. Definitions are
         --  durable catalog state and persistent postings are rebuilt on open, so
         --  the in-process posting vectors must be discarded when the owning
         --  handle is closed. This prevents stale state from a closed handle from
         --  being visible if another handle later receives a different state key.
         if Target.FT_State_Key /= 0 then
            Database.Full_Text.Clear (Target.FT_State_Key);
         end if;
         if Target.Catalog_State_Key_Value /= 0 then
            Database.Extensions.Clear (Target.Catalog_State_Key_Value);
            Database.Catalog.Drop_Database (Target.Catalog_State_Key_Value);
            Database.Extensions.Drop_Database (Target.Catalog_State_Key_Value);
            --  Free this handle's in-memory rows (no-op for a persistent handle).
            Database.Memory_Store.Drop (Target.Catalog_State_Key_Value);
         end if;

         Target.Kind := Closed_Backend;
         Target.Read_Only_Mode := False;
         return Result;
      end Save_And_Close;

      function Close_Exclusively is new Database.Exclusive.Try_Close (Save_And_Close);
   begin
      --  Closing writes the catalog and closes the file, so it holds the write lock and keeps new readers out: no
      --  transaction, checkpoint, backup or catalog change of another task may start meanwhile.
      DB.Last := Close_Exclusively
        (DB,
         Refused => Database.Status.Failure
           (Database.Status.Transaction_Conflict,
            "cannot close database while transactions, a checkpoint, a backup or a catalog change are active"));
   end Close;
   function Is_Open (DB : Handle) return Boolean is
   begin
      return DB.Kind /= Closed_Backend;
   end Is_Open;
   function Is_Read_Only (DB : Handle) return Boolean is
   begin
      return DB.Kind /= Closed_Backend and then DB.Read_Only_Mode;
   end Is_Read_Only;
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
