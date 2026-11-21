--  The work of a checkpoint, shared by Database.Checkpointing and a backup that forces a checkpoint.
with Database.Status;

--  Merge the WAL into the database file.
private package Database.Checkpoint_Merge is
   --  Write the committed WAL pages into the file, undo what unfinished transactions wrote, and delete the WAL when
   --  no reader may still need it. Emits the checkpoint start and end events; the end event only on success.
   --  The caller holds the write lock of DB, so no transaction writes meanwhile.
   --  @param DB open persistent database.
   --  @return Status result; the failure of the replay, the flush or the WAL deletion.
   function Merge_WAL (DB : in out Database.Handle) return Database.Status.Result;
end Database.Checkpoint_Merge;
