with Database.Storage.File_IO;
with Database.WAL;
with Database.Metrics;
with Database.Events;
with Database.Tracing;
with Database.Fault_Hooks;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Checkpointing is
   function Checkpoint
     (DB   : in out Database.Handle;
      Mode : Checkpoint_Mode := Full) return Database.Status.Result is
      pragma Unreferenced (Mode);
      R : Database.Status.Result;
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
      if DB.Lock.Writer_Active then
         return Database.Status.Failure (Database.Status.Checkpoint_Failure,
           "checkpoint cannot run while writer is active");
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Checkpoint) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Checkpoint);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Checkpoint) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error,
           "deterministic crash during checkpoint");
      end if;
      declare
         Path : constant Wide_Wide_String := Database.Storage.File_IO.Path (DB.File);
      begin
         R := Database.WAL.Replay_Committed (Path, DB.File);
      end;
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Storage.File_IO.Flush (DB.File);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Database.Metrics.Increment_Checkpoints;
      Database.Events.Emit_Event ((Database.Events.Checkpoint_End,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("checkpoint end")));
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("checkpoint end"), False));
      if DB.Lock.Active_Readers = 0 then
         return Database.WAL.Delete (Database.Storage.File_IO.Path (DB.File));
      end if;
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.Checkpoint_Failure, "checkpoint failed");
   end Checkpoint;
end Database.Checkpointing;
