with Database.Catalog;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Table_Heap;
with Database.Memory_Store;
with Database.MVCC;
with Database.WAL;
with Database.Log_Sequence;
with Database.Schema;
with Database.Foreign_Keys;
with Database.Check_Constraints;
with Database.Full_Text;
with Database.Migrations;
with Database.Events;
with Database.Metrics;
with Database.Tracing;
with Database.Transactions.State_Rules;
with Ada.Containers;
with System;
with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;

package body Database.Transactions is
   use type Ada.Containers.Count_Type;
   use type Database.Log_Sequence.Log_Sequence_Number;
   use type System.Address;

   --  Transaction ids are handed out here. Concurrent readers on one handle run
   --  Start in parallel (the read lock admits many), so the allocation must be
   --  atomic or two transactions could receive the same id.
   protected Id_Counter is
      procedure Next (Id : out Database.Versioning.Transaction_Id);
      procedure Reserve_Through (Highest : Natural);
   private
      Value : Natural := 1;
   end Id_Counter;

   protected body Id_Counter is
      procedure Next (Id : out Database.Versioning.Transaction_Id) is
      begin
         Id := Value;
         Value := Value + 1;
      end Next;
      procedure Reserve_Through (Highest : Natural) is
      begin
         if Highest >= Value then
            Value := Highest + 1;
         end if;
      end Reserve_Through;
   end Id_Counter;

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
      Tx.Heap_Tails.Clear;
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
      if Mode_In = Read_Write and then Database.Is_Read_Only (DB) then
         Tx.Last := Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "write transaction requested on read-only database");
         return;
      end if;

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
      --  The database may have been closed while the lock was awaited; Close holds the lock while it closes.
      if not Database.Is_Open (DB) then
         case Mode_In is
            when Read_Only => DB.Lock.End_Read;
            when Read_Write => DB.Lock.End_Write;
         end case;
         Tx.Last := Database.Status.Failure (Database.Status.Not_Open, "database not open");
         return;
      end if;
      --  A transaction reads its own snapshot; pages cached before it started may predate it.
      Database.Storage.File_IO.Invalidate_Cache (DB.File);

      Tx.DB := DB'Unrestricted_Access;
      Tx.Current_State := Active;
      Tx.Current_Mode := Mode_In;
      Tx.Lock_Held := True;
      Id_Counter.Next (Tx.Transaction_Id);
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
      if Tx.DB /= null then
         Database.Storage.File_IO.Invalidate_Cache (Tx.DB.File);
      end if;
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

   function Allocate_Page
     (Tx   : in out Transaction;
      Kind : Database.Storage.Pages.Page_Kind;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result
   is
      R : Database.Status.Result;
   begin
      if Tx.Current_State /= Active or else Tx.DB = null then
         return Database.Status.Failure (Database.Status.Transaction_Error, "transaction not active");
      end if;
      R := Database.Storage.Free_List.Reserve (Tx.DB.Page_Allocator, Tx.DB.File, Kind, Page);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Write_Page (Tx, Page);
   end Allocate_Page;

   function Free_Page
     (Tx : in out Transaction;
      Id : Database.Storage.Pages.Page_Id) return Database.Status.Result
   is
      Page : Database.Storage.Pages.Page;
      R    : Database.Status.Result;
   begin
      if Tx.Current_State /= Active or else Tx.DB = null then
         return Database.Status.Failure (Database.Status.Transaction_Error, "transaction not active");
      end if;
      Database.Storage.Pages.Initialize (Page, Id, Database.Storage.Pages.Free_Page);
      R := Write_Page (Tx, Page);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Database.Storage.Free_List.Release (Tx.DB.Page_Allocator, Id);
   end Free_Page;

   function Heap_Tail
     (Tx    : Transaction;
      First : Database.Storage.Pages.Page_Id) return Database.Storage.Pages.Page_Id is
     (if Tx.Heap_Tails.Contains (First) then Tx.Heap_Tails.Element (First)
      else Database.Storage.Pages.Invalid_Page_Id);

   procedure Set_Heap_Tail
     (Tx    : in out Transaction;
      First : Database.Storage.Pages.Page_Id;
      Last  : Database.Storage.Pages.Page_Id) is
   begin
      Tx.Heap_Tails.Include (First, Last);
   end Set_Heap_Tail;

   procedure Begin_Read (DB : in out Database.Handle; Tx : out Transaction) is
      Granted : Boolean;
   begin
      Start (DB, Tx, Read_Only, True, Granted);
   end Begin_Read;

   procedure Reserve_Ids_Through (Highest : Natural) is
   begin
      Id_Counter.Reserve_Through (Highest);
   end Reserve_Ids_Through;

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
      First_Write : constant Boolean := not Tx.Has_Writes;
      Keep_Original : Boolean;
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

      --  A page the file had before the transaction keeps its first image, in memory for a rollback and in the log for
      --  recovery after a crash, which writes it back when the transaction did not finish.
      Keep_Original := Natural (Id) < Tx.Original_Page_Count and then not Already_Saved (Tx, Id);
      if Keep_Original then
         R := Database.Storage.File_IO.Read_Page (Tx.DB.File, Id, Get_Kind (Page), Original);
         if not Database.Status.Is_Ok (R) then
            --  The page changes kind, for example when it is allocated from or released to the free list.
            R := Database.Storage.File_IO.Read_Raw_Page (Tx.DB.File, Id, Original);
         end if;
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
      end if;

      declare
         W : Database.WAL.WAL_Handle;
         L : Database.Log_Sequence.Log_Sequence_Number;
      begin
         R := Database.WAL.Open (W, Database.Storage.File_IO.Path (Tx.DB.File));
         if Database.Status.Is_Ok (R) and then First_Write then
            R := Database.WAL.Append_Begin (W, Natural (Tx.Transaction_Id), Tx.Original_Page_Count, L);
         end if;
         if Database.Status.Is_Ok (R) and then Keep_Original then
            R := Database.WAL.Append_Page_Undo (W, Natural (Tx.Transaction_Id), Original, L);
         end if;
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

      if Keep_Original then
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

   function Visible_Rows_For_Table
     (Tx       : in out Transaction;
      Table_Id : Natural) return Database.Foreign_Keys.Row_Vectors.Vector is
      DB   : constant Handle_Access := Tx.DB;
      Rows : Database.Foreign_Keys.Row_Vectors.Vector;
      S    : Database.Schema.Table_Schema;
      C    : Database.Storage.Table_Heap.Heap_Cursor;
      R    : Database.Status.Result;
   begin
      if DB = null then
         return Rows;
      end if;
      if Database.Backend (DB.all) /= Database.Persistent_Backend then
         return Database.Catalog.Rows_For_Table
           (Database.Catalog_State_Key (DB.all), Table_Id);
      end if;

      R := Database.Catalog.Find_By_Id (Database.Catalog_State_Key (DB.all), Table_Id, S);
      if not Database.Status.Is_Ok (R) or else S.Heap_First_Page = 0 then
         return Rows;
      end if;

      R := Database.Storage.Table_Heap.Scan_First
        (Tx,
         DB.File,
         Database.Storage.Pages.Page_Id (S.Heap_First_Page),
         S,
         C);
      while Database.Status.Is_Ok (R) and then C.Has_Row loop
         Rows.Append (C.Row);
         R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, S, C);
      end loop;
      return Rows;
   end Visible_Rows_For_Table;

   function Validate_Deferred_Constraints (Tx : in out Transaction) return Database.Status.Result is
      S             : Database.Schema.Table_Schema;
      Referenced_S  : Database.Schema.Table_Schema;
      Rows          : Database.Foreign_Keys.Row_Vectors.Vector;
      Referenced    : Database.Foreign_Keys.Row_Vectors.Vector;
      Checks        : Database.Check_Constraints.Check_Constraint_Vectors.Vector;
      FKs           : Database.Foreign_Keys.Foreign_Key_Vectors.Vector;
      R             : Database.Status.Result;
   begin
      if Tx.DB = null or else Tx.Current_Mode /= Read_Write then
         return Database.Status.Success;
      end if;

      if Database.Catalog.Table_Count (Database.Catalog_State_Key (Tx.DB.all)) = 0 then
         return Database.Status.Success;
      end if;

      for I in 0 .. Database.Catalog.Table_Count (Database.Catalog_State_Key (Tx.DB.all)) - 1 loop
         S := Database.Catalog.Table_At (Database.Catalog_State_Key (Tx.DB.all), I);
         Rows := Visible_Rows_For_Table (Tx, S.Table_Id);
         Checks := Database.Catalog.Check_Constraints_For_Table
           (Database.Catalog_State_Key (Tx.DB.all), S.Table_Id);
         if Checks.Length > 0 then
            for Row of Rows loop
               R := Database.Check_Constraints.Validate_All
                 (Database.Catalog_State_Key (Tx.DB.all), Checks, S, Row, Include_Deferred => True);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
            end loop;
         end if;

         FKs := Database.Catalog.Foreign_Keys_For_Referencing_Table
           (Database.Catalog_State_Key (Tx.DB.all), S.Table_Id);
         for FK of FKs loop
            if FK.Deferred then
               R := Database.Catalog.Find_By_Id
                 (Database.Catalog_State_Key (Tx.DB.all), FK.Referenced_Table, Referenced_S);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               Referenced := Visible_Rows_For_Table (Tx, FK.Referenced_Table);
               for Row of Rows loop
                  R := Database.Foreign_Keys.Validate_Insert_Or_Update
                    (FK, S, Referenced_S, Row, Referenced);
                  if not Database.Status.Is_Ok (R) then
                     return R;
                  end if;
               end loop;
            end if;
         end loop;
      end loop;
      return Database.Status.Success;
   end Validate_Deferred_Constraints;

   --  Log that the transaction's writes are undone, so recovery does not undo them again over later work.
   function Log_Abort (Tx : Transaction) return Database.Status.Result is
      W : Database.WAL.WAL_Handle;
      L : Database.Log_Sequence.Log_Sequence_Number;
      R : Database.Status.Result := Database.WAL.Open (W, Database.Storage.File_IO.Path (Tx.DB.File));
   begin
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Append_Abort (W, Natural (Tx.Transaction_Id), L);
      end if;
      if Database.Status.Is_Ok (R) then
         R := Database.WAL.Flush (W);
      end if;
      declare
         CR : constant Database.Status.Result := Database.WAL.Close (W);
      begin
         return (if Database.Status.Is_Ok (R) then CR else R);
      end;
   end Log_Abort;

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
      if Tx.Current_Mode = Read_Write and then Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
         --  Catalog changes are staged in memory until here, so the page is logged like every other page.
         declare
            Catalog_Page : Database.Storage.Pages.Page;
            Changed      : Boolean;
         begin
            R := Database.Catalog.Pending_Page (Tx.DB.all, Catalog_Page, Changed);
            if Database.Status.Is_Ok (R) and then Changed then
               R := Write_Page (Tx, Catalog_Page);
            end if;
         end;
         if not Database.Status.Is_Ok (R) then
            Tx.Current_State := Failed;
            Tx.Last := R;
            return R;
         end if;
      end if;
      Tx.Current_State := Committing;
      R := Validate_Deferred_Constraints (Tx);
      if not Database.Status.Is_Ok (R) then
         Tx.Current_State := Failed;
         Tx.Last := R;
         return R;
      end if;
      if Tx.Current_Mode = Read_Write and then Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
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
         Database.Full_Text.Commit_Transaction
           (Database.Full_Text_State_Key (Tx.DB.all), Tx.Transaction_Id, Tx.DB.Version);
         Database.Migrations.Commit_Transaction (Natural (Tx.Transaction_Id));
         if Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
            R := Database.Full_Text.Save
              (Database.Full_Text_State_Key (Tx.DB.all),
               Database.Storage.File_IO.Path (Tx.DB.File));
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
        and then (Tx.Has_Writes or else not Database.Catalog.Is_Saved (Tx.DB.all))
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
         if Tx.Has_Writes and then Database.Storage.File_IO.Page_Count (Tx.DB.File) > Tx.Original_Page_Count then
            R := Database.Storage.File_IO.Truncate_To_Page_Count
              (Tx.DB.File, Tx.Original_Page_Count);
            if not Database.Status.Is_Ok (R) then
               Tx.Current_State := Failed;
               Tx.Last := R;
               return R;
            end if;
         end if;
         --  Pages past the restored end of the file and pages freed by the transaction are gone or in use again.
         Database.Storage.Free_List.Initialize_From_File (Tx.DB.Page_Allocator, Tx.DB.File);
         R := Database.Storage.File_IO.Flush (Tx.DB.File);
         if Database.Status.Is_Ok (R) and then Tx.Has_Writes then
            R := Log_Abort (Tx);
         end if;
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
         --  Undo the aborted transaction's work in every store: heap pages were
         --  restored from before-images above; drop its in-memory inserts and
         --  undo its in-memory delete marks here; then migrations and full text.
         Database.Memory_Store.Rollback (Tx.Transaction_Id);
         Database.Migrations.Rollback_Transaction
           (Natural (Tx.Transaction_Id), Tx.DB.all);
         Database.Full_Text.Rollback_Transaction
           (Database.Full_Text_State_Key (Tx.DB.all), Tx.Transaction_Id);
         if Database.Backend (Tx.DB.all) = Database.Persistent_Backend then
            R := Database.Full_Text.Save
              (Database.Full_Text_State_Key (Tx.DB.all),
               Database.Storage.File_IO.Path (Tx.DB.File));
            if not Database.Status.Is_Ok (R) then
               Tx.Current_State := Failed;
               Tx.Last := R;
               return R;
            end if;
         end if;
         --  Nothing references the transaction any more, so drop its lifecycle
         --  entry outright instead of retaining a Rolled_Back marker. This is
         --  what keeps the MVCC map bounded under a stream of aborts.
         Database.MVCC.Forget (Tx.Transaction_Id);
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

   function Is_Active (Tx : Transaction) return Boolean is
     (Database.Transactions.State_Rules.Is_Active_State (Tx.Current_State));
   function Can_Read (Tx : Transaction) return Boolean is
     (Database.Transactions.State_Rules.Can_Read_State (Tx.Current_State));
   function Can_Write (Tx : Transaction) return Boolean is
     (Database.Transactions.State_Rules.Can_Write_State (Tx.Current_State, Tx.Current_Mode)
      and then Owned_By_Current_Task (Tx));

   function Write_Refusal
     (Tx      : Transaction;
      Code    : Database.Status.Status_Code;
      Message : Wide_Wide_String) return Database.Status.Result is
     (if Database.Transactions.State_Rules.Can_Write_State (Tx.Current_State, Tx.Current_Mode)
        and then not Owned_By_Current_Task (Tx)
      then Database.Status.Failure (Database.Status.Invalid_Argument, "transaction belongs to another task")
      else Database.Status.Failure (Code, Message));
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

   function Belongs_To (Tx : Transaction; DB : Database.Handle) return Boolean is
     (Tx.DB /= null and then Tx.DB.all'Address = DB'Address);

   function Owned_By_Current_Task (Tx : Transaction) return Boolean is
     (Tx.Current_Mode = Read_Only
      or else (Tx.DB /= null and then Tx.DB.Lock.Own_Transaction_Writing));

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
