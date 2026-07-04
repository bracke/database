--  WAL checkpointing: merge committed WAL page frames into the main database file.
with Database.Status;

--  Checkpoint coordination for WAL-backed durability.
package Database.Checkpointing is
   --  Checkpoint_Mode enumerates the supported values for this database abstraction.
   type Checkpoint_Mode is (Passive, Full, Forced);

   --  Return checkpoint for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Mode mode argument supplied to the operation.
   --  @return Result produced by the function.
   function Checkpoint
     (DB   : in out Database.Handle;
      Mode : Checkpoint_Mode := Full) return Database.Status.Result;
end Database.Checkpointing;
