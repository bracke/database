--  Exclusive use of a database's write lock by an operation outside any transaction.
with Database.Status;

--  Run work that writes the database file directly, such as a checkpoint, a backup or a catalog change, while no
--  transaction or other such operation writes. The lock is released however the work ends; an exception the work
--  raises propagates after the release, so work that reports failures as results handles its exceptions itself.
private package Database.Exclusive is
   --  Wait for the current writer, then take the write lock of DB exclusively and run Work. A task that already holds
   --  the lock, for example in an event handler of a checkpoint it runs, would wait for itself; it gets
   --  Transaction_Conflict instead.
   --  @param DB open database.
   --  @return The result of Work, or Transaction_Conflict.
   generic
      with function Work (DB : in out Database.Handle) return Database.Status.Result;
   function Run_Waiting (DB : in out Database.Handle) return Database.Status.Result;

   --  Take the write lock of DB exclusively and run Work, or return Refused when anyone holds the lock.
   --  @param DB open database.
   --  @param Refused result returned when the lock is taken.
   --  @return The result of Work, or Refused.
   generic
      with function Work (DB : in out Database.Handle) return Database.Status.Result;
   function Try_Run (DB : in out Database.Handle; Refused : Database.Status.Result) return Database.Status.Result;

   --  Take the write lock of DB exclusively for closing it and run Work, or return Refused when anyone reads or
   --  writes. Until Work ends, new readers wait or are refused.
   --  @param DB open database.
   --  @param Refused result returned when the lock is taken or a reader is active.
   --  @return The result of Work, or Refused.
   generic
      with function Work (DB : in out Database.Handle) return Database.Status.Result;
   function Try_Close (DB : in out Database.Handle; Refused : Database.Status.Result) return Database.Status.Result;
end Database.Exclusive;
