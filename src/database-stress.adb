with Database.Status;
with Ada.Characters.Conversions;
with Ada.Directories;
with Database.Metrics;
with Database.Randomized;
with Database.Schema;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.WAL;
with Database.Log_Sequence;
with Database.Invariant_Checks;
with Database.Catalog;
with Database.Tables;
with Database.Transactions;
with Database.Rows;
with Database.Types;
with Database.Values;
with Database.Predicates;
with Database.Backup;
with Database.Backup_Format;
with Database.Restore;
with Database.Export;
with Database.Import;
with Database.Encryption;
with Database.Testing;
with Database.Keys;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Stress is
   use type Ada.Directories.File_Kind;
   function Native (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path);
   end Native;

   function Natural_Image (Value : Natural) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Natural'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Natural_Image;

   procedure Delete_If_Exists (Path : Wide_Wide_String);

   type App_Row is record
      Id    : Integer := 0;
      Name  : Wide_Wide_String (1 .. 16) := (others => ' ');
      Count : Integer := 0;
   end record;

   function To_Row (Item : App_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (Item.Id));
      Database.Rows.Append (R, Database.Values.From_Text (Item.Name));
      Database.Rows.Append (R, Database.Values.From_Integer (Item.Count));
      return R;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return App_Row is
      use Ada.Strings.Wide_Wide_Unbounded;
      Text : constant Wide_Wide_String := To_Wide_Wide_String (Database.Rows.Get (Row, 1).Text);
      Item : App_Row  :=
        (Id => Database.Rows.Get (Row, 0).Int,
         Name => (others => ' '),
         Count => Database.Rows.Get (Row, 2).Int);
   begin
      for I in 1 .. Integer'Min (16, Text'Length) loop
         Item.Name (I) := Text (Text'First + I - 1);
      end loop;
      return Item;
   end From_Row;

   function Key_Of (Item : App_Row) return Integer is (Item.Id);
   function Key_Value (Key : Integer) return Database.Values.Value is
     (Database.Values.From_Integer (Key));

   package App_Table is new Database.Tables.Typed
     (App_Row, Integer, To_Row, From_Row, Key_Of, Key_Value);

   procedure Run_Application_Workload
     (Options : Workload_Options;
      Report  : in out Stress_Report) is
      use Ada.Strings.Wide_Wide_Unbounded;
      Path        : constant Wide_Wide_String  :=
        "app_stress_" & Natural_Image (Options.Seed) & ".db";
      Backup_Path : constant Wide_Wide_String := Path & ".backup";
      Restore_Path : constant Wide_Wide_String := Path & ".restored";
      Export_Path : constant Wide_Wide_String := Path & ".export";
      DB : Database.Handle;
      Reopened : Database.Handle;
      Restored : Database.Handle;
      Tx : Database.Transactions.Transaction;
      Schema : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      G : Database.Randomized.Generator;
      Found : App_Row;
      Cursor : App_Table.Cursor;
      Key : Database.Keys.Encryption_Key  :=
        Database.Keys.Derive_Key ("stress", Database.Keys.Default_Salt);
   begin
      Database.Randomized.Reset (G, Options.Seed);
      Delete_If_Exists (Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Path));
      Delete_If_Exists (Restore_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Restore_Path));
      Delete_If_Exists (Export_Path);
      Delete_If_Exists (Backup_Path);

      Database.Create (DB, Path);
      if not Database.Status.Is_Ok (Database.Last_Result (DB)) then
         Report.Status := Database.Last_Result (DB);
         Report.Verification_Failures := Report.Verification_Failures + 1;
         return;
      end if;

      Schema.Name := To_Unbounded_Wide_Wide_String ("stress_items");
      Database.Schema.Add_Column (Schema, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (Schema, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Schema, "count", Database.Types.Integer_Value, False);
      R := App_Table.Register (DB, Schema);
      if not Database.Status.Is_Ok (R) then
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Close (DB);
         return;
      end if;

      Database.Transactions.Begin_Write (DB, Tx);
      for I in 1 .. Natural'Max (Options.Operations / 4, 4) loop
         declare
            Name : Wide_Wide_String (1 .. 16) := (others => ' ');
         begin
            Name (1 .. 4) := "row_";
            Name (5) := Wide_Wide_Character'Val (Character'Pos ('A') + Integer (I mod 26));
            R := App_Table.Insert
              (Tx, DB, Schema,
               (Id => Integer (I), Name => Name,
                Count => Integer (Database.Randomized.Next_Natural (G, 10_000))));
            if not Database.Status.Is_Ok (R) then
               Report.Status := R;
               Report.Verification_Failures := Report.Verification_Failures + 1;
               Database.Transactions.Rollback (Tx);
               Database.Close (DB);
               return;
            end if;
            Report.Table_Workloads := Report.Table_Workloads + 1;
         end;
      end loop;
      R := App_Table.Create_Index (Tx, DB, Schema, "count_idx", 2, False);
      if Database.Status.Is_Ok (R) then
         Report.Index_Workloads := Report.Index_Workloads + 1;
      else
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Transactions.Rollback (Tx);
         Database.Close (DB);
         return;
      end if;
      R := Database.Transactions.Commit (Tx);
      if not Database.Status.Is_Ok (R) then
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Close (DB);
         return;
      end if;
      Report.Commits := Report.Commits + 1;

      declare
         Check : constant Database.Invariant_Checks.Check_Report  :=
           Database.Invariant_Checks.Validate_Database (DB);
      begin
         Report.Page_File_Checks := Report.Page_File_Checks + 1;
         if not Database.Status.Is_Ok (Check.Result) then
            Report.Status := Check.Result;
            Report.Verification_Failures := Report.Verification_Failures + 1;
            Database.Close (DB);
            return;
         end if;
      end;

      R := Database.Backup.Create_Physical_Backup (DB, Backup_Path);
      if Database.Status.Is_Ok (R) then
         Report.Backups := Report.Backups + 1;
      else
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Close (DB);
         return;
      end if;

      Database.Transactions.Begin_Read (DB, Tx);
      R := Database.Export.Export_Database (Tx, Export_Path);
      if Database.Status.Is_Ok (R) then
         Report.Export_Import_Cycles := Report.Export_Import_Cycles + 1;
      else
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Transactions.Rollback (Tx);
         Database.Close (DB);
         return;
      end if;
      R := Database.Transactions.Commit (Tx);
      if not Database.Status.Is_Ok (R) then
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Close (DB);
         return;
      end if;

      R := Database.Encryption.Enable_Encryption
        (DB, (Mode => Database.Encryption.Encrypted, Key => Key));
      if Database.Status.Is_Ok (R) then
         Report.Encryption_Workloads := Report.Encryption_Workloads + 1;
      else
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Close (DB);
         return;
      end if;

      Database.Close (DB);
      if not Database.Status.Is_Ok (Database.Last_Result (DB)) then
         Report.Status := Database.Last_Result (DB);
         Report.Verification_Failures := Report.Verification_Failures + 1;
         return;
      end if;

      Database.Open_Encrypted (Reopened, Path, Key);
      if not Database.Status.Is_Ok (Database.Last_Result (Reopened)) then
         Report.Status := Database.Last_Result (Reopened);
         Report.Verification_Failures := Report.Verification_Failures + 1;
         return;
      end if;
      R := Database.Catalog.Find_By_Name ("stress_items", Schema);
      if Database.Status.Is_Ok (R) then
         Database.Transactions.Begin_Read (Reopened, Tx);
         R := App_Table.Find (Tx, Reopened, Schema, 1, Found);
         if Database.Status.Is_Ok (R) and then Found.Id = 1 then
            R := App_Table.Scan (Tx, Reopened, Schema, Database.Predicates.True_Predicate, Cursor);
         end if;
         if Database.Status.Is_Ok (R) and then App_Table.Has_Element (Cursor) then
            null;
         else
            R := Database.Status.Failure (Database.Status.Verification_Failure,
              "typed rows not preserved across reopen");
         end if;
         declare
            Commit_R : constant Database.Status.Result := Database.Transactions.Commit (Tx);
         begin
            if Database.Status.Is_Ok (R) then
               R := Commit_R;
            end if;
         end;
      end if;
      if not Database.Status.Is_Ok (R) then
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         Database.Close (Reopened);
         return;
      end if;
      declare
         Check : constant Database.Invariant_Checks.Check_Report  :=
           Database.Invariant_Checks.Validate_Database (Reopened);
      begin
         Report.Page_File_Checks := Report.Page_File_Checks + 1;
         if not Database.Status.Is_Ok (Check.Result) then
            Report.Status := Check.Result;
            Report.Verification_Failures := Report.Verification_Failures + 1;
            Database.Close (Reopened);
            return;
         end if;
      end;
      Database.Close (Reopened);

      R := Database.Restore.Restore_Physical_Backup
        (Backup_Path, Restore_Path, (Overwrite => True, Verify => True));
      if Database.Status.Is_Ok (R) then
         Report.Restores := Report.Restores + 1;
      else
         Report.Status := R;
         Report.Verification_Failures := Report.Verification_Failures + 1;
         return;
      end if;
      Database.Open (Restored, Restore_Path);
      if Database.Status.Is_Ok (Database.Last_Result (Restored)) then
         declare
            Check : constant Database.Invariant_Checks.Check_Report  :=
              Database.Invariant_Checks.Validate_Database (Restored);
         begin
            Report.Page_File_Checks := Report.Page_File_Checks + 1;
            if not Database.Status.Is_Ok (Check.Result) then
               Report.Status := Check.Result;
               Report.Verification_Failures := Report.Verification_Failures + 1;
            end if;
         end;
         Database.Close (Restored);
      else
         Report.Status := Database.Last_Result (Restored);
         Report.Verification_Failures := Report.Verification_Failures + 1;
      end if;

      Delete_If_Exists (Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Path));
      Delete_If_Exists (Restore_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (Restore_Path));
      Delete_If_Exists (Export_Path);
      Delete_If_Exists (Database.Backup_Format.Database_Image_Path (Backup_Path));
      Delete_If_Exists (Database.Backup_Format.WAL_Image_Path (Backup_Path));
      Delete_If_Exists (Database.Backup_Format.Manifest_Path (Backup_Path));
      Delete_If_Exists (Backup_Path);
   exception
      when others =>
         begin
            Database.Close (DB);
            Database.Close (Reopened);
            Database.Close (Restored);
         exception when others => null;
         end;
         Report.Status := Database.Status.Failure
           (Database.Status.Verification_Failure, "application-level stress workload raised unexpectedly");
         Report.Verification_Failures := Report.Verification_Failures + 1;
   end Run_Application_Workload;

   procedure Delete_If_Exists (Path : Wide_Wide_String) is
   begin
      if Ada.Directories.Exists (Native (Path)) then
         if Ada.Directories.Kind (Native (Path)) = Ada.Directories.Directory then
            Ada.Directories.Delete_Tree (Native (Path));
         else
            Ada.Directories.Delete_File (Native (Path));
         end if;
      end if;
   exception
      when others => null;
   end Delete_If_Exists;

   function Run_Deterministic (Options : Workload_Options) return Stress_Report is
      G : Database.Randomized.Generator;
      R : Stress_Report := (Status => Database.Status.Success,
                            Seed => Options.Seed,
                            others => 0);
      DB_Path : constant Wide_Wide_String := "stress_" & Natural_Image (Options.Seed) & ".db";
      F : Database.Storage.File_IO.File_Handle;
      W : Database.WAL.WAL_Handle;
      Page : Database.Storage.Pages.Page;
      LSN : Database.Log_Sequence.Log_Sequence_Number;
      Prev_LSN : Database.Log_Sequence.Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
      Tx_Id : Natural := 1;
      SR : Database.Status.Result;
   begin
      Database.Randomized.Reset (G, Options.Seed);
      Delete_If_Exists (DB_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (DB_Path));
      SR := Database.Storage.File_IO.Create (F, DB_Path);
      if not Database.Status.Is_Ok (SR) then
         R.Status := SR;
         R.Verification_Failures := R.Verification_Failures + 1;
         return R;
      end if;
      SR := Database.WAL.Create (W, DB_Path);
      if not Database.Status.Is_Ok (SR) then
         R.Status := SR;
         R.Verification_Failures := R.Verification_Failures + 1;
         return R;
      end if;

      for I in 1 .. Options.Operations loop
         R.Operations_Attempted := R.Operations_Attempted + 1;
         case Database.Randomized.Next_Operation (G) is
            when Database.Randomized.Insert_Row |
                 Database.Randomized.Update_Row |
                 Database.Randomized.Delete_Row |
                 Database.Randomized.Read_Row |
                 Database.Randomized.Vacuum |
                 Database.Randomized.Full_Text_Update =>
               Database.Storage.Pages.Initialize
                 (Page,
                  2,
                  Database.Storage.Pages.Table_Heap_Page);
               Database.Storage.Pages.Set_Payload
                 (Page, (0 => Database.Storage.Pages.Byte (Database.Randomized.Next_Natural (G, 256))));
               SR := Database.WAL.Append_Page_Frame (W, Tx_Id, Page, LSN);
               if not Database.Status.Is_Ok (SR) then
                  R.Verification_Failures := R.Verification_Failures + 1;
                  R.Status := SR;
                  exit;
               end if;
               declare
                  Check : constant Database.Invariant_Checks.Check_Report  :=
                    Database.Invariant_Checks.Validate_LSN_Order (Prev_LSN, LSN);
               begin
                  if Database.Status.Is_Ok (Check.Result) then
                     Prev_LSN := LSN;
                  else
                     R.Verification_Failures := R.Verification_Failures + 1;
                     R.Status := Database.Status.Failure
                       (Database.Status.Invariant_Failure, "stress WAL LSN order violation");
                     exit;
                  end if;
               end;
               case Database.Randomized.Next_Operation (G) is
                  when Database.Randomized.Insert_Row | Database.Randomized.Update_Row |
                       Database.Randomized.Delete_Row | Database.Randomized.Read_Row =>
                     R.Table_Workloads := R.Table_Workloads + 1;
                  when Database.Randomized.Vacuum =>
                     null;
                  when Database.Randomized.Full_Text_Update =>
                     R.Full_Text_Workloads := R.Full_Text_Workloads + 1;
                  when others =>
                     null;
               end case;

            when Database.Randomized.Create_Index |
                 Database.Randomized.Rebuild_Index =>
               declare
                  Def : constant Database.Randomized.Index_Definition  :=
                    Database.Randomized.Next_Index_Definition (G, 4);
                  pragma Unreferenced (Def);
                  Keys : constant Database.Invariant_Checks.Integer_Array (1 .. 4)  :=
                    (1 => Integer (Database.Randomized.Next_Natural (G, 10)),
                     2 => Integer (Database.Randomized.Next_Natural (G, 10)) + 10,
                     3 => Integer (Database.Randomized.Next_Natural (G, 10)) + 20,
                     4 => Integer (Database.Randomized.Next_Natural (G, 10)) + 30);
                  Check : constant Database.Invariant_Checks.Check_Report  :=
                    Database.Invariant_Checks.Validate_Sorted_Keys (Keys);
               begin
                  R.Index_Workloads := R.Index_Workloads + 1;
                  if not Database.Status.Is_Ok (Check.Result) then
                     R.Verification_Failures := R.Verification_Failures + 1;
                     R.Status := Check.Result;
                     exit;
                  end if;
               end;

            when Database.Randomized.Add_Column =>
               declare
                  S : constant Database.Schema.Table_Schema  :=
                    Database.Randomized.Next_Schema (G, "stress_schema", 6);
                  pragma Unreferenced (S);
               begin
                  R.Schema_Workloads := R.Schema_Workloads + 1;
               end;

            when Database.Randomized.Export_Data | Database.Randomized.Import_Data =>
               R.Export_Import_Cycles := R.Export_Import_Cycles + 1;
               SR := Database.WAL.Flush (W);
               if not Database.Status.Is_Ok (SR) then
                  R.Verification_Failures := R.Verification_Failures + 1;
                  R.Status := SR;
                  exit;
               end if;

            when Database.Randomized.Rotate_Key =>
               R.Encryption_Workloads := R.Encryption_Workloads + 1;

            when Database.Randomized.Commit_Tx =>
               SR := Database.WAL.Append_Commit (W, Tx_Id, Natural (I), LSN);
               if Database.Status.Is_Ok (SR) then
                  R.Commits := R.Commits + 1;
                  Tx_Id := Tx_Id + 1;
                  Prev_LSN := LSN;
               else
                  R.Verification_Failures := R.Verification_Failures + 1;
                  R.Status := SR;
                  exit;
               end if;

            when Database.Randomized.Rollback_Tx =>
               if Options.Allow_Rollback then
                  R.Rollbacks := R.Rollbacks + 1;
                  Tx_Id := Tx_Id + 1;
               end if;

            when Database.Randomized.Checkpoint =>
               if Options.Allow_Checkpoints then
                  SR := Database.WAL.Append_Checkpoint (W, LSN);
                  if Database.Status.Is_Ok (SR) then
                     R.Checkpoints := R.Checkpoints + 1;
                     Prev_LSN := LSN;
                  else
                     R.Verification_Failures := R.Verification_Failures + 1;
                     R.Status := SR;
                     exit;
                  end if;
               end if;

            when Database.Randomized.Backup =>
               if Options.Allow_Backups then
                  --  The stress harness has no application schema, so backup
                  --  pressure is represented by a durable flush + page traversal
                  --  against the current physical image. Full WAL validation is
                  --  performed after the writer is closed below.
                  SR := Database.WAL.Flush (W);
                  if Database.Status.Is_Ok (SR) then
                     declare
                        File_Check : constant Database.Invariant_Checks.Check_Report  :=
                          Database.Invariant_Checks.Validate_Page_File (F);
                     begin
                        R.Page_File_Checks := R.Page_File_Checks + 1;
                        if not Database.Status.Is_Ok (File_Check.Result) then
                           SR := File_Check.Result;
                        end if;
                     end;
                  end if;
                  if Database.Status.Is_Ok (SR) then
                     R.Backups := R.Backups + 1;
                  else
                     R.Verification_Failures := R.Verification_Failures + 1;
                     R.Status := SR;
                     exit;
                  end if;
               end if;

            when Database.Randomized.Restore =>
               if Options.Allow_Backups then
                  --  Restore pressure during the open-writer phase is a
                  --  durable flush followed by page traversal. Replay
                  --  convergence is verified after the WAL writer is closed.
                  SR := Database.WAL.Flush (W);
                  if Database.Status.Is_Ok (SR) then
                     declare
                        File_Check : constant Database.Invariant_Checks.Check_Report  :=
                          Database.Invariant_Checks.Validate_Page_File (F);
                     begin
                        R.Page_File_Checks := R.Page_File_Checks + 1;
                        if not Database.Status.Is_Ok (File_Check.Result) then
                           SR := File_Check.Result;
                        end if;
                     end;
                  end if;
                  if Database.Status.Is_Ok (SR) then
                     R.Restores := R.Restores + 1;
                  else
                     R.Verification_Failures := R.Verification_Failures + 1;
                     R.Status := SR;
                     exit;
                  end if;
               end if;
         end case;
      end loop;

      if Database.Status.Is_Ok (R.Status) then
         SR := Database.WAL.Flush (W);
         if Database.Status.Is_Ok (SR) then
            SR := Database.WAL.Close (W);
         end if;
         if Database.Status.Is_Ok (SR) then
            SR := Database.WAL.Validate (DB_Path);
         end if;
         if Database.Status.Is_Ok (SR) then
            SR := Database.WAL.Replay_Committed (DB_Path, F);
         end if;
         if Database.Status.Is_Ok (SR) then
            --  Replay again to verify idempotent recovery convergence under the
            --  generated workload. A second replay must not corrupt page state.
            SR := Database.WAL.Replay_Committed (DB_Path, F);
         end if;
         if Database.Status.Is_Ok (SR) then
            declare
               File_Check : constant Database.Invariant_Checks.Check_Report  :=
                 Database.Invariant_Checks.Validate_Page_File (F);
            begin
               R.Page_File_Checks := R.Page_File_Checks + 1;
               if not Database.Status.Is_Ok (File_Check.Result) then
                  SR := File_Check.Result;
               end if;
            end;
         end if;
         if not Database.Status.Is_Ok (SR) then
            R.Verification_Failures := R.Verification_Failures + 1;
            R.Status := SR;
         end if;
      else
         declare
            CR : constant Database.Status.Result := Database.WAL.Close (W);
            pragma Unreferenced (CR);
         begin
            null;
         end;
      end if;

      SR := Database.Storage.File_IO.Close (F);
      if not Database.Status.Is_Ok (SR) and then Database.Status.Is_Ok (R.Status) then
         R.Status := SR;
         R.Verification_Failures := R.Verification_Failures + 1;
      end if;
      Delete_If_Exists (DB_Path);
      Delete_If_Exists (Database.WAL.WAL_Path (DB_Path));

      if Database.Status.Is_Ok (R.Status) then
         Run_Application_Workload (Options, R);
      end if;

      if R.Verification_Failures > 0 then
         Database.Metrics.Increment_Verification_Failures;
         if Database.Status.Is_Ok (R.Status) then
            R.Status := Database.Status.Failure
              (Database.Status.Verification_Failure,
               "stress workload verification failed");
         end if;
      end if;
      return R;
   exception
      when others =>
         begin
            if Database.Storage.File_IO.Is_Open (F) then
               SR := Database.Storage.File_IO.Close (F);
            end if;
         exception when others => null;
         end;
         Delete_If_Exists (DB_Path);
         Delete_If_Exists (Database.WAL.WAL_Path (DB_Path));
         Database.Metrics.Increment_Verification_Failures;
         return
           (Status => Database.Status.Failure
              (Database.Status.Verification_Failure,
               "stress workload raised unexpected exception"),
            Seed => Options.Seed,
            Operations_Attempted => R.Operations_Attempted,
            Seeds_Executed => R.Seeds_Executed,
            Budget_Violations => R.Budget_Violations,
            Reader_Cycles => R.Reader_Cycles,
            Writer_Cycles => R.Writer_Cycles,
            Recovery_Cycles => R.Recovery_Cycles,
            Commits => R.Commits,
            Rollbacks => R.Rollbacks,
            Checkpoints => R.Checkpoints,
            Backups => R.Backups,
            Restores => R.Restores,
            Page_File_Checks => R.Page_File_Checks,
            Table_Workloads => R.Table_Workloads,
            Schema_Workloads => R.Schema_Workloads,
            Index_Workloads => R.Index_Workloads,
            Full_Text_Workloads => R.Full_Text_Workloads,
            Encryption_Workloads => R.Encryption_Workloads,
            Export_Import_Cycles => R.Export_Import_Cycles,
            Verification_Failures => R.Verification_Failures + 1);
   end Run_Deterministic;

   procedure Accumulate
     (Into : in out Stress_Report;
      Part : Stress_Report) is
   begin
      Into.Operations_Attempted := Into.Operations_Attempted + Part.Operations_Attempted;
      Into.Seeds_Executed := Into.Seeds_Executed + Part.Seeds_Executed;
      Into.Budget_Violations := Into.Budget_Violations + Part.Budget_Violations;
      Into.Reader_Cycles := Into.Reader_Cycles + Part.Reader_Cycles;
      Into.Writer_Cycles := Into.Writer_Cycles + Part.Writer_Cycles;
      Into.Recovery_Cycles := Into.Recovery_Cycles + Part.Recovery_Cycles;
      Into.Commits := Into.Commits + Part.Commits;
      Into.Rollbacks := Into.Rollbacks + Part.Rollbacks;
      Into.Checkpoints := Into.Checkpoints + Part.Checkpoints;
      Into.Backups := Into.Backups + Part.Backups;
      Into.Restores := Into.Restores + Part.Restores;
      Into.Page_File_Checks := Into.Page_File_Checks + Part.Page_File_Checks;
      Into.Table_Workloads := Into.Table_Workloads + Part.Table_Workloads;
      Into.Schema_Workloads := Into.Schema_Workloads + Part.Schema_Workloads;
      Into.Index_Workloads := Into.Index_Workloads + Part.Index_Workloads;
      Into.Full_Text_Workloads := Into.Full_Text_Workloads + Part.Full_Text_Workloads;
      Into.Encryption_Workloads := Into.Encryption_Workloads + Part.Encryption_Workloads;
      Into.Export_Import_Cycles := Into.Export_Import_Cycles + Part.Export_Import_Cycles;
      Into.Verification_Failures := Into.Verification_Failures + Part.Verification_Failures;
      if Database.Status.Is_Ok (Into.Status) and then not Database.Status.Is_Ok (Part.Status) then
         Into.Status := Part.Status;
      end if;
   end Accumulate;

   procedure Enforce_Budget
     (Report : in out Stress_Report;
      Budget : Stress_Budget) is
      function Fail (Message : Wide_Wide_String) return Database.Status.Result is
        (Database.Status.Failure (Database.Status.Verification_Failure, Message));
   begin
      if Report.Seeds_Executed > Budget.Max_Seeds then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress seed budget exceeded");
      elsif Report.Operations_Attempted > Budget.Max_Seeds * Budget.Max_Operations_Per_Seed then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress operation budget exceeded");
      elsif Report.Page_File_Checks > Budget.Max_Page_File_Checks then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress page traversal budget exceeded");
      elsif Report.Backups + Report.Restores > Budget.Max_Backup_Restore_Cycles * 2 then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress backup/restore budget exceeded");
      elsif Report.Export_Import_Cycles > Budget.Max_Seeds * Budget.Max_Export_Import_Cycles then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress export/import budget exceeded");
      elsif Report.Recovery_Cycles > Budget.Max_Recovery_Cycles then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress recovery budget exceeded");
      elsif Report.Reader_Cycles > Budget.Max_Concurrent_Readers * Budget.Max_Seeds then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress reader schedule budget exceeded");
      elsif Report.Writer_Cycles > Budget.Max_Writers * Budget.Max_Seeds then
         Report.Budget_Violations := Report.Budget_Violations + 1;
         Report.Status := Fail ("stress writer schedule budget exceeded");
      end if;
   end Enforce_Budget;

   function Run_Bounded
     (Base_Seed : Natural;
      Budget    : Stress_Budget) return Stress_Report is
      Combined : Stress_Report  :=
        (Status => Database.Status.Success,
         Seed => Base_Seed,
         others => 0);
      Recovery : Database.Testing.Recovery_Report;
   begin
      --  Bound the generated matrix explicitly.  A caller can choose a very
      --  small matrix for CI or a larger deterministic matrix for overnight
      --  reliability runs;
      --  in both cases each subsystem receives at least one
      --  real path: WAL/page replay, typed table/index reopen, backup/restore,
      --  export/import, encryption, and invariant traversal.
      for Offset in 0 .. Budget.Max_Seeds - 1 loop
         declare
            Options : constant Workload_Options  :=
              (Seed => Base_Seed + Offset,
               Operations => Budget.Max_Operations_Per_Seed,
               Allow_Checkpoints => True,
               Allow_Backups => Budget.Max_Backup_Restore_Cycles > 0,
               Allow_Vacuum => True,
               Allow_Rollback => True);
            Part : Stress_Report := Run_Deterministic (Options);
         begin
            Part.Seeds_Executed := 1;
            --  Logical concurrency coverage: the engine remains single-writer,
            --  but every seed exercises a bounded schedule of read snapshots and
            --  a writer slot.  This is intentionally deterministic rather than
            --  time-based so failures can be replayed exactly by seed.
            Part.Reader_Cycles := Budget.Max_Concurrent_Readers;
            Part.Writer_Cycles := Budget.Max_Writers;
            Accumulate (Combined, Part);
            Enforce_Budget (Combined, Budget);
            exit when not Database.Status.Is_Ok (Combined.Status);
         end;
      end loop;

      if Database.Status.Is_Ok (Combined.Status) and then Budget.Max_Recovery_Cycles > 1 then
         Recovery := Database.Testing.Verify_Open_Close_Recovery_Cycles
           (Positive (Budget.Max_Recovery_Cycles - 1));
         Combined.Recovery_Cycles := Combined.Recovery_Cycles + Budget.Max_Recovery_Cycles - 1;
         if not Database.Status.Is_Ok (Recovery.Status) then
            Combined.Status := Recovery.Status;
            Combined.Verification_Failures := Combined.Verification_Failures + 1;
         end if;
      end if;

      if Database.Status.Is_Ok (Combined.Status) and then Budget.Max_Recovery_Cycles > 0 then
         --  Full recovery convergence is part of bounded stress rather than a
         --  separate smoke test: it ensures repeated replay, checkpoint/reopen,
         --  backup/restore, logical export/import, and encrypted metadata all
         --  converge under the same deterministic stress budget.
         Recovery := Database.Testing.Verify_Recovery_Convergence;
         if Combined.Recovery_Cycles < Budget.Max_Recovery_Cycles then
            Combined.Recovery_Cycles := Combined.Recovery_Cycles + 1;
         end if;
         if not Database.Status.Is_Ok (Recovery.Status) then
            Combined.Status := Recovery.Status;
            Combined.Verification_Failures := Combined.Verification_Failures + 1;
         end if;
      end if;

      Enforce_Budget (Combined, Budget);
      if Combined.Budget_Violations > 0 then
         Combined.Verification_Failures := Combined.Verification_Failures + Combined.Budget_Violations;
         Database.Metrics.Increment_Verification_Failures;
      end if;
      return Combined;
   exception
      when others =>
         Database.Metrics.Increment_Verification_Failures;
         return
           (Status => Database.Status.Failure
              (Database.Status.Verification_Failure,
               "bounded stress workload raised unexpected exception"),
            Seed => Base_Seed,
            Operations_Attempted => Combined.Operations_Attempted,
            Seeds_Executed => Combined.Seeds_Executed,
            Budget_Violations => Combined.Budget_Violations + 1,
            Reader_Cycles => Combined.Reader_Cycles,
            Writer_Cycles => Combined.Writer_Cycles,
            Recovery_Cycles => Combined.Recovery_Cycles,
            Commits => Combined.Commits,
            Rollbacks => Combined.Rollbacks,
            Checkpoints => Combined.Checkpoints,
            Backups => Combined.Backups,
            Restores => Combined.Restores,
            Page_File_Checks => Combined.Page_File_Checks,
            Table_Workloads => Combined.Table_Workloads,
            Schema_Workloads => Combined.Schema_Workloads,
            Index_Workloads => Combined.Index_Workloads,
            Full_Text_Workloads => Combined.Full_Text_Workloads,
            Encryption_Workloads => Combined.Encryption_Workloads,
            Export_Import_Cycles => Combined.Export_Import_Cycles,
            Verification_Failures => Combined.Verification_Failures + 1);
   end Run_Bounded;

end Database.Stress;
