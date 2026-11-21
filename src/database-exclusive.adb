package body Database.Exclusive is
   --  Run Work while DB's write lock is held, and release the lock however Work ends.
   generic
      with function Work (DB : in out Database.Handle) return Database.Status.Result;
   function Holding (DB : in out Database.Handle) return Database.Status.Result;

   function Holding (DB : in out Database.Handle) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      begin
         R := Work (DB);
      exception
         when others =>
            DB.Lock.End_Write;
            raise;
      end;
      DB.Lock.End_Write;
      return R;
   end Holding;

   function Run_Waiting (DB : in out Database.Handle) return Database.Status.Result is
      function Run is new Holding (Work);
   begin
      if DB.Lock.Held_By_Current_Task then
         return Database.Status.Failure
           (Database.Status.Transaction_Conflict, "the calling task already holds the write lock");
      end if;
      DB.Lock.Begin_Exclusive;
      return Run (DB);
   end Run_Waiting;

   function Try_Run (DB : in out Database.Handle; Refused : Database.Status.Result) return Database.Status.Result is
      function Run is new Holding (Work);
      Granted : Boolean;
   begin
      DB.Lock.Try_Begin_Exclusive (Granted);
      if not Granted then
         return Refused;
      end if;
      return Run (DB);
   end Try_Run;

   function Try_Close (DB : in out Database.Handle; Refused : Database.Status.Result) return Database.Status.Result is
      function Run is new Holding (Work);
      Granted : Boolean;
   begin
      DB.Lock.Try_Begin_Close (Granted);
      if not Granted then
         return Refused;
      end if;
      return Run (DB);
   end Try_Close;
end Database.Exclusive;
