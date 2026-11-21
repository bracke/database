--  WAL checkpointing: merge committed WAL page frames into the main database file.
with Database.Status;

--  Checkpoint coordination for WAL-backed durability.
package Database.Checkpointing is
   --  Checkpoint_Mode enumerates the supported values for this database abstraction.
   type Checkpoint_Mode is (Passive, Full, Forced);

   --  Write the committed WAL pages into the database file and delete the WAL when no reader is active. The
   --  checkpoint holds the write lock while it runs, so it is refused beside an active writer. An in-memory database
   --  has nothing to checkpoint and succeeds.
   --  @param DB open database.
   --  @param Mode currently ignored: every mode performs the full checkpoint described above.
   --  @return Status result; Not_Open, Checkpoint_Failure beside a writer or when the merge raises, or the failure
   --  of the replay, the flush or the WAL deletion.
   function Checkpoint
     (DB   : in out Database.Handle;
      Mode : Checkpoint_Mode := Full) return Database.Status.Result;
end Database.Checkpointing;
