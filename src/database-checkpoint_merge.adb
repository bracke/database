with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.WAL;
with Database.Metrics;
with Database.Events;
with Database.Tracing;
with Database.Fault_Hooks;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Checkpoint_Merge is
   procedure Announce (Kind : Database.Events.Event_Kind; Text : Wide_Wide_String) is
   begin
      Database.Events.Emit_Event ((Kind, Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Text)));
      Database.Tracing.Emit_Trace ((0, Database.Tracing.WAL_Trace,
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Text), False));
   end Announce;

   function Merge_WAL (DB : in out Database.Handle) return Database.Status.Result is
      Path : constant Wide_Wide_String := Database.Storage.File_IO.Path (DB.File);
      R    : Database.Status.Result;
   begin
      Announce (Database.Events.Checkpoint_Start, "checkpoint start");
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
      if DB.Lock.Active_Readers = 0 then
         R := Database.WAL.Delete (Path);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      Database.Metrics.Increment_Checkpoints;
      Announce (Database.Events.Checkpoint_End, "checkpoint end");
      return Database.Status.Success;
   end Merge_WAL;
end Database.Checkpoint_Merge;
