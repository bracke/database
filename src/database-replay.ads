--  WAL replay entry points used during open-time recovery and explicit tests.
with Database.Status;
with Database.Storage.File_IO;

--  WAL replay and recovery convergence support.
package Database.Replay is
   --  Return replay wal for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @param F f argument supplied to the operation.
   --  @return Result produced by the function.
   function Replay_WAL
     (Database_Path : Wide_Wide_String;
      F             : in out Database.Storage.File_IO.File_Handle) return Database.Status.Result;

   --  Return validate wal for the supplied database state or arguments.
   --  @param Database_Path database path argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_WAL (Database_Path : Wide_Wide_String) return Database.Status.Result;
end Database.Replay;
