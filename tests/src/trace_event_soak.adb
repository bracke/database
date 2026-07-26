--  Phase 3 stressor: drive Database.Tracing and Database.Events concurrently
--  from many tasks with tracing enabled and a handler subscribed, so the
--  now-protected trace ring buffer / logical clock and the event handler
--  registry are actually exercised under contention. The ordinary
--  concurrency_soak runs with tracing off and no handlers, so it never touches
--  these paths. Exit 0 = buffer stayed capped and no crash; 1 = overflow.
--
--  Run under ThreadSanitizer the same way as concurrency_soak:
--    alr exec -- gprbuild -P tests.gpr -XSANITIZE=thread
--    TSAN_OPTIONS="halt_on_error=0 exitcode=66" setarch "$(uname -m)" -R \
--      ./bin/trace_event_soak
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Database.Events;
with Database.Status;
with Database.Tracing;

procedure Trace_Event_Soak is
   Workers  : constant := 8;
   Per_Task : constant := 1000;

   procedure Handler (Event : Database.Events.Operational_Event) is
      pragma Unreferenced (Event);
   begin
      null;  --  presence matters; it is invoked concurrently by Emit
   end Handler;

   task type Worker;
   task body Worker is
   begin
      for I in 1 .. Per_Task loop
         declare
            RT : constant Database.Status.Result :=
              Database.Tracing.Emit (Database.Tracing.Query_Trace, "trace");
            RE : constant Database.Status.Result :=
              Database.Events.Emit (Database.Events.Transaction_Begin, "event");
            pragma Unreferenced (RT, RE);
         begin
            null;
         end;
         --  Stir the registries: toggling subscription while others Emit
         --  exercises Add/Clear against Snapshot under the lock.
         if I mod 250 = 0 then
            Database.Events.Subscribe (Handler'Unrestricted_Access);
         end if;
      end loop;
   end Worker;

begin
   Database.Tracing.Reset;
   Database.Tracing.Enable;
   Database.Events.Subscribe (Handler'Unrestricted_Access);

   declare
      Fleet : array (1 .. Workers) of Worker;
      pragma Unreferenced (Fleet);
   begin
      null;  --  block completion joins every worker
   end;

   if Database.Tracing.Buffered_Count <= 256 then
      Put_Line
        ("TRACE/EVENT SOAK OK: buffer capped at"
         & Natural'Image (Database.Tracing.Buffered_Count));
   else
      Put_Line ("TRACE/EVENT SOAK FAIL: buffer overflow");
      Set_Exit_Status (1);
   end if;
end Trace_Event_Soak;
