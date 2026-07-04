with Database.Status;
with Database.Catalog;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.MVCC;
with Database.Versioning;
with Database.WAL;
with Database.Log_Sequence;
with Database.Full_Text;
with Database.Migrations;
with Database.Events;
with Database.Metrics;
with Database.Tracing;
with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;

package body Database.Transactions is
   use type Database.Log_Sequence.Log_Sequence_Number;
   Next_Transaction_Id : Natural := 1;

   function Already_Saved
     (Tx : Transaction;
      Id : Database.Storage.Pages.Page_Id) return Boolean is
   begin
      for Existing of Tx.Before_Image_Ids loop
         if Existing = Id then
            return True;
         end if;
      end loop;
      return False;
   end Already_Saved;

   procedure Reset (Tx : out Transaction) is
   begin
      Tx.DB := null;
      Tx.Current_State := Rolled_Back;
      Tx.Current_Mode := Read_Only;
      Tx.Last := Database.Status.Success;
      Tx.Has_Writes := False;
      Tx.Before_Image_Ids.Clear;
      Tx.Before_Image_Pages.Clear;
      Tx.Original_Page_Count := 0;
      Tx.Transaction_Id := 0;
      Tx.Lock_Held := False;
      Tx.Started_At_Version := 0;
      Tx.Ended_At_Version := 0;
   end Reset;

   procedure Start
     (DB      : in out Database.Handle;
      Tx      : out Transaction;
      Mode_In : Transaction_Mode;
      Blocking : Boolean;
      Granted : out Boolean) is
   begin
      Reset (Tx);
      Granted := False;
      if not Database.Is_Open (DB) then
         Tx.Last := Database.Status.Failure (Database.Status.Not_Open, "database not open");
         return;
      end if;

      Database.Catalog.Select_Database (Database.Catalog_State_Key (DB));
      Database.Full_Text.Select_Database (Database.Full_Text_State_Key (DB));

      if Blocking then
         case Mode_In is
            when Read_Only => DB.Lock.Begin_Read;
            when Read_Write => DB.Lock.Begin_Write;
         end case;
         Granted := True;
      else
         case Mode_In is
            when Read_Only => DB.Lock.Try_Begin_Read (Granted);
            when Read_Write => DB.Lock.Try_Begin_Write (Granted);
         end case;
         if not Granted then
            Tx.Last := Database.Status.Failure
              (Database.Status.Transaction_Conflict, "transaction lock is not available");
            return;
         end if;
      end if;

      Tx.DB := DB'Unrestricted_Access;
      Tx.Current_State := Active;
      Tx.Current_Mode := Mode_In;
      Tx.Lock_Held := True;
      Tx.Transaction_Id := Next_Transaction_Id;
      Next_Transaction_Id := Next_Transaction_Id + 1;
      Tx.Started_At_Version := Database.Commit_Version (DB);
      Database.MVCC.Register_Snapshot (Tx.Started_At_Version);
      Database.MVCC.Register_Transaction (Tx.Transaction_Id);
      Tx.Last := Database.Status.Success;
      Database.Metrics.Increment_Transactions_Begun;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Transaction_Trace,
        To_Unbounded_Wide_Wide_String ("transaction begin"),
        False));
      declare
         ER : constant Database.Status.Result  :=
           Database.Events.Emit (Database.Events.Transaction_Begin,
                                 "transaction begin");
         pragma Unreferenced (ER);
      begin
         null;
      end;
   exception
      when others =>
         Tx.Current_State := Failed;
         Tx.Last := Database.Status.Failure (Database.Status.Lock_Error, "failed to acquire transaction lock");
   end Start;

   procedure Release_Lock (Tx : in out Transaction) is
   begin
      if Tx.Lock_Held and then Tx.DB /= null then
         case Tx.Current_Mode is
            when Read_Only => Tx.DB.Lock.End_Read;
            when Read_Write => Tx.DB.Lock.End_Write;
         end case;
         Tx.Lock_Held := False;
         if Tx.Started_At_Version /= 0 or else Tx.Transaction_Id /= 0 then
            Database.MVCC.Release_Snapshot (Tx.Started_At_Version);
         end if;
      end if;
   exception
      when others =>
         Tx.Lock_Held := False;
   end Release_Lock;

   function Ensure_Write_State (Tx : in out Transaction) return Database.Status.Result is
   begin
      if Tx.Current_Mode /= Read_Write then
         Tx.Last := Database.Status.Failure
           (Database.Status.Read_Only_Transaction, "write attempted in read-only transaction");
         return Tx.Last;
      end if;
      if not Tx.Has_Writes then
         Tx.Original_Page_Count := Database.Storage.File_IO.Page_Count (Tx.DB.File);
         Tx.Has_Writes := True;
      end if;
      return Database.Status.Success;
   end Ensure_Write_State;

   procedure Begin_Read (DB : in out Database.Handle; Tx : out Transaction) is
      Granted : Boolean;
   begin
      Start (DB, Tx, Read_Only, True, Granted);
   end Begin_Read;

   procedure Begin_Write (DB : in out Database.Handle; Tx : out Transaction) is
      Granted : Boolean;
   begin
      Start (DB, Tx, Read_Write, True, Granted);
   end Begin_Write;

   procedure Try_Begin_Read
     (DB      : in out Database.Handle;
      Tx      : out Transaction;
      Granted : out Boolean) is
   begin
      Start (DB, Tx, Read_Only, False, Granted);
   end Try_Begin_Read;

   procedure Try_Begin_Write
     (DB      : in out Database.Handle;
      Tx      : out Transaction;
      Granted : out Boolean) is
   begin
      Start (DB, Tx, Read_Write, False, Granted);
   end Try_Begin_Write;

   function Write_Page
     (Tx   : in out Transaction;
      Page : Database.Storage.Pages.Page) return Database.Status.Result is
      use Database.Storage.Pages;
      Original : Database.Storage.Pages.Page;
      R : Database.Status.Result;
      Id : constant Page_Id := Get_Id (Page);
      Last_WAL_LSN : Database.Log_Sequence.Log_Sequence_Number := Database.Log_Sequence.Invalid_LSN;
   begin
      if Tx.Current_State /= Active or else Tx.DB = null then
         Tx.Last := Database.Status.Failure (Database.Status.Transaction_Error, "transaction not active");
         return Tx.Last;
      end if;
      if Tx.Current_Mode /= Read_Write then
         Tx.Last := Database.Status.Failure
           (Database.Status.Read_Only_Transaction, "write attempted in read-only transaction");
         return Tx.Last;
      end if;
      if Database.Backend (Tx.DB.all) /= Database.Persistent_Backend then
         return Database.Status.Success;
      end if;
      R := Ensure_Write_State (Tx);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      declare
         W : Database.WAL.WAL_Handle;
         L : Database.Log_Sequence.Log_Sequence_Number;
      begin
         R := Database.WAL.Open (W, Database.Storage.File_IO.Path (Tx.DB.File));
         if Database.Status.Is_Ok (R) then
            R := Database.WAL.Append_Page_Frame (W, Natural (Tx.Transaction_Id), Page, L);
            if Database.Status.Is_Ok (R) then
               Last_WAL_LSN := L;
            end if;
         end if;
         if Database.Status.Is_Ok (R) then
            R := Database.WAL.Flush (W);
         end if;
         declare
            CR : constant Database.Status.Result := Database.WAL.Close (W);
         begin
            if Database.Status.Is_Ok (R) and then not Database.Status.Is_Ok (CR) then
               R := CR;
            end if;
         end;
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
      end;

      if Natural (Id) < Tx.Original_Page_Count and then not Already_Saved (Tx, Id) then
         R := Database.Storage.File_IO.Read_Page (Tx.DB.File, Id, Get_Kind (Page), Original);
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
         Tx.Before_Image_Ids.Append (Id);
         Tx.Before_Image_Pages.Append (Original);
      end if;
      declare
         Page_To_Write : Database.Storage.Pages.Page := Page;
      begin
         if Last_WAL_LSN /= Database.Log_Sequence.Invalid_LSN then
            Database.Storage.Pages.Set_Last_LSN (Page_To_Write, Last_WAL_LSN);
         end if;
         R := Database.Storage.File_IO.Write_Page (Tx.DB.File, Page_To_Write);
      end;
      if not Database.Status.Is_Ok (R) then
         Tx.Current_State := Failed;
         Tx.Last := R;
         return R;
      end if;
      Tx.Last := Database.Status.Success;
      return Tx.Last;
   end Write_Page;

   function Commit (Tx : in out Transaction) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if Tx.Current_State = Committed then
         Tx.Last := Database.Status.Success;
         return Tx.Last;
      elsif Tx.Current_State = Rolled_Back then
         Tx.Last := Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction already rolled back");
         return Tx.Last;
      elsif Tx.Current_State /= Active or else Tx.DB = null then
         Tx.Last := Database.Status.Failure (Database.Status.Transaction_Error, "transaction not active");
         return Tx.Last;
      end if;
      Tx.Current_State := Committing;
      if Tx.Current_Mode = Read_Write and then Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
         R := Database.Catalog.Save (Tx.DB.all);
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
         R := Database.Storage.File_IO.Flush (Tx.DB.File);
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
         declare
            W : Database.WAL.WAL_Handle;
            L : Database.Log_Sequence.Log_Sequence_Number;
         begin
            R := Database.WAL.Open (W, Database.Storage.File_IO.Path (Tx.DB.File));
            if Database.Status.Is_Ok (R) then
               R := Database.WAL.Append_Commit (W, Natural (Tx.Transaction_Id), Tx.DB.Version + 1, L);
            end if;
            if Database.Status.Is_Ok (R) then
               R := Database.WAL.Flush (W);
            end if;
            declare
               CR : constant Database.Status.Result := Database.WAL.Close (W);
            begin
               if Database.Status.Is_Ok (R) and then not Database.Status.Is_Ok (CR) then
                  R := CR;
               end if;
            end;
            if not Database.Status.Is_Ok (R) then
               Tx.Current_State := Failed;
               Tx.Last := R;
               return R;
            end if;
         end;
      end if;
      if Tx.Current_Mode = Read_Write then
         Tx.DB.Version := Tx.DB.Version + 1;
         Database.MVCC.Mark_Committed (Tx.Transaction_Id, Tx.DB.Version);
         Database.Full_Text.Select_Database (Database.Full_Text_State_Key (Tx.DB.all));
         Database.Full_Text.Commit_Transaction (Tx.Transaction_Id, Tx.DB.Version);
         Database.Migrations.Commit_Transaction (Natural (Tx.Transaction_Id));
         if Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
            Database.Full_Text.Select_Database (Database.Full_Text_State_Key (Tx.DB.all));
            R := Database.Full_Text.Save (Database.Storage.File_IO.Path (Tx.DB.File));
            if not Database.Status.Is_Ok (R) then
               Tx.Current_State := Failed;
               Tx.Last := R;
               return R;
            end if;
         end if;
      end if;
      Tx.Ended_At_Version := Database.Commit_Version (Tx.DB.all);
      Tx.Current_State := Committed;
      Release_Lock (Tx);
      Tx.Last := Database.Status.Success;
      Database.Metrics.Increment_Transactions_Committed;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Transaction_Trace,
        To_Unbounded_Wide_Wide_String ("transaction commit"),
        False));
      declare
         ER : constant Database.Status.Result  :=
           Database.Events.Emit (Database.Events.Transaction_Commit,
                                 "transaction commit");
         pragma Unreferenced (ER);
      begin
         null;
      end;
      return Tx.Last;
   end Commit;

   function Rollback (Tx : in out Transaction) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if Tx.Current_State = Rolled_Back then
         Tx.Last := Database.Status.Success;
         return Tx.Last;
      elsif Tx.Current_State = Committed then
         Tx.Last := Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction already committed");
         return Tx.Last;
      elsif not (Tx.Current_State = Active or else Tx.Current_State = Failed) or else Tx.DB = null then
         Tx.Last := Database.Status.Failure
           (Database.Status.Transaction_Error, "transaction cannot roll back from current state");
         return Tx.Last;
      end if;
      Tx.Current_State := Rolling_Back;
      if Tx.Current_Mode = Read_Write
        and then Database.Backend (Tx.DB.all) = Database.Persistent_Backend
        and then Tx.Has_Writes
      then
         if not Tx.Before_Image_Pages.Is_Empty then
            for I in 0 .. Natural (Tx.Before_Image_Pages.Length) - 1 loop
               R := Database.Storage.File_IO.Write_Page
                 (Tx.DB.File, Tx.Before_Image_Pages.Element (I));
               if not Database.Status.Is_Ok (R) then
                  Tx.Current_State := Failed;
                  Tx.Last := R;
                  return R;
               end if;
            end loop;
         end if;
         if Database.Storage.File_IO.Page_Count (Tx.DB.File) > Tx.Original_Page_Count then
            R := Database.Storage.File_IO.Truncate_To_Page_Count
              (Tx.DB.File, Tx.Original_Page_Count);
            if not Database.Status.Is_Ok (R) then
               Tx.Current_State := Failed;
               Tx.Last := R;
               return R;
            end if;
         end if;
         R := Database.Storage.File_IO.Flush (Tx.DB.File);
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
         R := Database.Catalog.Load (Tx.DB.all);
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
      end if;
      if Tx.Current_Mode = Read_Write then
         Database.MVCC.Mark_Rolled_Back (Tx.Transaction_Id);
         Database.Migrations.Rollback_Transaction
           (Natural (Tx.Transaction_Id), Tx.DB.all);
         Database.Full_Text.Select_Database (Database.Full_Text_State_Key (Tx.DB.all));
         Database.Full_Text.Rollback_Transaction (Tx.Transaction_Id);
         if Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
            Database.Full_Text.Select_Database (Database.Full_Text_State_Key (Tx.DB.all));
            R := Database.Full_Text.Save (Database.Storage.File_IO.Path (Tx.DB.File));
            if not Database.Status.Is_Ok (R) then
               Tx.Current_State := Failed;
               Tx.Last := R;
               return R;
            end if;
         end if;
      end if;
      Tx.Ended_At_Version := Database.Commit_Version (Tx.DB.all);
      Tx.Current_State := Rolled_Back;
      Release_Lock (Tx);
      Tx.Last := Database.Status.Success;
      Database.Metrics.Increment_Transactions_Rolled_Back;
      Database.Tracing.Emit_Trace ((0, Database.Tracing.Transaction_Trace,
        To_Unbounded_Wide_Wide_String ("transaction rollback"),
        False));
      declare
         ER : constant Database.Status.Result  :=
           Database.Events.Emit (Database.Events.Transaction_Rollback,
                                 "transaction rollback");
         pragma Unreferenced (ER);
      begin
         null;
      end;
      return Tx.Last;
   end Rollback;

   procedure Commit (Tx : in out Transaction) is
      R : constant Database.Status.Result := Commit (Tx);
      pragma Unreferenced (R);
   begin
      null;
   end Commit;

   procedure Rollback (Tx : in out Transaction) is
      R : constant Database.Status.Result := Rollback (Tx);
      pragma Unreferenced (R);
   begin
      null;
   end Rollback;

   function Is_Active (Tx : Transaction) return Boolean is (Tx.Current_State = Active);
   function Can_Read (Tx : Transaction) return Boolean is (Tx.Current_State = Active);
   function Can_Write (Tx : Transaction) return Boolean is
     (Tx.Current_State = Active and then Tx.Current_Mode = Read_Write);
   function Result (Tx : Transaction) return Database.Status.Result is (Tx.Last);
   function State (Tx : Transaction) return Transaction_State is (Tx.Current_State);
   function Mode (Tx : Transaction) return Transaction_Mode is (Tx.Current_Mode);
   function Id (Tx : Transaction) return Database.Versioning.Transaction_Id is (Tx.Transaction_Id);
   function Snapshot_Version (Tx : Transaction) return Database.Versioning.Commit_Version is (Tx.Started_At_Version);
   function Start_Version (Tx : Transaction) return Database.Versioning.Commit_Version is (Tx.Started_At_Version);
   function Ended_Version (Tx : Transaction) return Database.Versioning.Commit_Version is (Tx.Ended_At_Version);
   function Commit_Version (Tx : Transaction) return Database.Versioning.Commit_Version is
     (if Tx.Current_State = Committed then Tx.Ended_At_Version else 0);

   function Owning_Database (Tx : in out Transaction) return access Database.Handle is
   begin
      return Tx.DB;
   end Owning_Database;

   overriding procedure Finalize (Tx : in out Transaction) is
      R : Database.Status.Result;
   begin
      if Tx.Current_State = Active or else Tx.Current_State = Failed then
         R := Rollback (Tx);
         pragma Unreferenced (R);
      else
         Release_Lock (Tx);
      end if;
   exception
      when others => null;
   end Finalize;
end Database.Transactions;
