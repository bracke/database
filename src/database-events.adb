package body Database.Events is

   --  Subscribed handlers live in a protected registry over a fixed array, so
   --  concurrent multi-database tasks can Subscribe / Clear / Emit safely. To
   --  honour the "no user code under a lock" rule (a hung or re-entrant handler
   --  must not stall the registry), Emit_Event copies the handler set out under
   --  the lock and dispatches outside it. The cap is generous; handler counts
   --  are tiny in practice, and excess Subscribes past the cap are dropped.
   Max_Handlers : constant := 64;
   type Handler_Array is array (1 .. Max_Handlers) of Event_Handler;

   protected Registry is
      procedure Add (Handler : Event_Handler);
      procedure Clear;
      procedure Snapshot (Into : out Handler_Array; N : out Natural);
   private
      Slots : Handler_Array := [others => null];
      Count : Natural := 0;
   end Registry;

   protected body Registry is
      procedure Add (Handler : Event_Handler) is
      begin
         if Handler /= null and then Count < Max_Handlers then
            Count := Count + 1;
            Slots (Count) := Handler;
         end if;
      end Add;
      procedure Clear is
      begin
         Slots := [others => null];
         Count := 0;
      end Clear;
      procedure Snapshot (Into : out Handler_Array; N : out Natural) is
      begin
         Into := Slots;
         N := Count;
      end Snapshot;
   end Registry;

   procedure Subscribe (Handler : Event_Handler) is
   begin
      Registry.Add (Handler);
   end Subscribe;

   procedure Clear_Handlers is
   begin
      Registry.Clear;
   end Clear_Handlers;

   function Emit_Event (Event : Operational_Event) return Database.Status.Result is
      Snap : Handler_Array;
      N    : Natural;
   begin
      Registry.Snapshot (Snap, N);  --  copy under lock; dispatch outside it
      for I in 1 .. N loop
         begin
            Snap (I).all (Event);
         exception
            when others =>
               return Database.Status.Failure
                 (Database.Status.Event_Handler_Error, "event handler failed");
         end;
      end loop;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure
           (Database.Status.Event_Handler_Error, "event dispatch failed");
   end Emit_Event;

   procedure Emit_Event (Event : Operational_Event) is
      R : constant Database.Status.Result := Emit_Event (Event);
      pragma Unreferenced (R);
   begin
      null;
   end Emit_Event;

   function Emit (Kind : Event_Kind; Message : Wide_Wide_String := "")
     return Database.Status.Result is
      E : Operational_Event;
   begin
      E.Kind := Kind;
      E.Message := To_Unbounded_Wide_Wide_String (Message);
      return Emit_Event (E);
   end Emit;
end Database.Events;
