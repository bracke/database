with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.WAL;
with Database.Metrics;
with Database.Events;
with Database.Tracing;
with Database.Fault_Hooks;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Checkpointing is
   --  Write the committed WAL pages into the file and drop the WAL when no reader may still need it. The caller holds
   --  the write lock.
   function Merge_WAL (DB : in out Database.Handle) return Database.Status.Result is
      Path : constant Wide_Wide_String := Database.Storage.File_IO.Path (DB.File);
      R    : Database.Status.Result;
   begin
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Checkpoint) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Checkpoint);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Checkpoint) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error,
           "deterministic crash during checkpoint");
      end if;
      R := Database.WAL.Replay_Committed (Path, DB.File);
      if Database.Status.Is_Ok (R) then
         R := Database.Storage.File_IO.Flush (DB.File);
      end if;
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      --  Replay may have undone a transaction whose rollback failed and cut the file back, so the free pages and the
      --  end of the file are found again.
      Database.Storage.Free_List.Initialize_From_File (DB.Page_Allocator, DB.File);
      Database.Metrics.Increment_Checkpoints;
      Database.Events.Emit_Event ((Database.Events.Checkpoint_End,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("checkpoint end")));
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("checkpoint end"), False));
      if DB.Lock.Active_Readers = 0 then
         return Database.WAL.Delete (Path);
      end if;
      return Database.Status.Success;
   end Merge_WAL;

   function Checkpoint
     (DB   : in out Database.Handle;
      Mode : Checkpoint_Mode := Full) return Database.Status.Result is
      pragma Unreferenced (Mode);
      R       : Database.Status.Result;
      Granted : Boolean;
   begin
      if not Database.Is_Open (DB) then
         return Database.Status.Failure (Database.Status.Not_Open, "database not open");
      end if;
      if Database.Backend (DB) /= Database.Persistent_Backend then
         return Database.Status.Success;
      end if;
      Database.Events.Emit_Event ((Database.Events.Checkpoint_Start,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("checkpoint start")));
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("checkpoint start"), False));
      --  The checkpoint writes pages, may cut the file back and rescans the free pages, so no transaction may write
      --  meanwhile: it holds the write lock throughout instead of only checking that no writer is active.
      DB.Lock.Try_Begin_Write (Granted);
      if not Granted then
         return Database.Status.Failure (Database.Status.Checkpoint_Failure,
           "checkpoint cannot run while writer is active");
      end if;
      begin
         R := Merge_WAL (DB);
      exception
         when others =>
            R := Database.Status.Failure (Database.Status.Checkpoint_Failure, "checkpoint failed");
      end;
      DB.Lock.End_Write;
      return R;
   end Checkpoint;
end Database.Checkpointing;
