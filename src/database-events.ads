--  Operational lifecycle events and isolated handler dispatch.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;

--  Operational event hooks.
package Database.Events is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Event_Kind defines a public database type used by this package.
   type Event_Kind is
     (Transaction_Begin,
      Transaction_Commit,
      Transaction_Rollback,
      Checkpoint_Start,
      Checkpoint_End,
      Backup_Start,
      Backup_End,
      Restore_End,
      Integrity_Check_Failure,
      WAL_Replay_Start,
      WAL_Replay_End,
      Extension_Registration,
      Encryption_Key_Rotation);

   --  Operational_Event stores the public fields for this database abstraction.
   type Operational_Event is record
      Kind    : Event_Kind := Transaction_Begin;
      Message : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
   end record;

   --  Event_Handler defines a public database type used by this package.
   type Event_Handler is access procedure (Event : Operational_Event);

   --  Perform subscribe for the supplied database state or arguments.
   --  @param Handler handler argument supplied to the operation.
   procedure Subscribe (Handler : Event_Handler);
   --  Perform clear handlers for the supplied database state or arguments.
   procedure Clear_Handlers;
   --  Return emit event for the supplied database state or arguments.
   --  @param Event event argument supplied to the operation.
   --  @return Result produced by the function.
   function Emit_Event (Event : Operational_Event) return Database.Status.Result;
   --  Perform emit event for the supplied database state or arguments.
   --  @param Event event argument supplied to the operation.
   procedure Emit_Event (Event : Operational_Event);
   --  Return emit for the supplied database state or arguments.
   --  @return Result produced by the function.
   --  @param Kind Parameter supplied to emit.
   --  @param Message Parameter supplied to emit.
   function Emit (Kind : Event_Kind; Message : Wide_Wide_String := "")
     return Database.Status.Result;
end Database.Events;
