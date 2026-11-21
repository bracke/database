--  Exclusive use of a database's write lock by an operation outside any transaction.
with Database.Status;

--  Run work that writes the database file directly, such as a checkpoint, a backup or a catalog change, while no
--  transaction or other such operation writes.
private package Database.Exclusive is
   --  Take the write lock of DB exclusively, run Work, and release the lock however Work ends. An exception Work
   --  raises propagates after the release; work that reports failures as results handles its exceptions itself.
   --  @param DB open database.
   --  @param Wait wait for the current writer; otherwise return Refused when the lock is taken.
   --  @param Refused result returned when Wait is False and the lock is taken.
   --  @return The result of Work, or Refused.
   generic
      with function Work (DB : in out Database.Handle) return Database.Status.Result;
   function Run
     (DB      : in out Database.Handle;
      Wait    : Boolean;
      Refused : Database.Status.Result) return Database.Status.Result;
end Database.Exclusive;
