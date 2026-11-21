--  WAL replay entry points used during open-time recovery and explicit tests.
with Database.Status;
with Database.Storage.File_IO;

--  WAL replay and recovery convergence support.
package Database.Replay is
   --  Recover the database file from its WAL; another name for Database.WAL.Replay_Committed, kept for callers of
   --  this package. Opening a database recovers through Database.WAL.Recover, which also reports what the WAL holds.
   --  @param Database_Path path of the database whose WAL is replayed.
   --  @param F the open database file.
   --  @return Status result; Replay_Failure or a WAL corruption status when the WAL cannot be applied.
   function Replay_WAL
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result;

   --  Return validate wal for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_WAL (Database_Path : Wide_Wide_String) return Database.Status.Result;
end Database.Replay;
