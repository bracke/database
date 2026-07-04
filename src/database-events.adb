with Ada.Containers.Vectors;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Events is
   use Ada.Strings.Wide_Wide_Unbounded;
   package Handler_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Event_Handler);
   Handlers : Handler_Vectors.Vector;

   procedure Subscribe (Handler : Event_Handler) is
   begin
      if Handler /= null then
         Handlers.Append (Handler);
      end if;
   end Subscribe;

   procedure Clear_Handlers is
   begin
      Handlers.Clear;
   end Clear_Handlers;

   function Emit_Event (Event : Operational_Event) return Database.Status.Result is
   begin
      for Handler of Handlers loop
         begin
            Handler.all (Event);
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
