with Ada.Finalization;

package body Database.Exclusive is
   --  The hold of one operation on DB's write lock. Finalization releases it however the operation ends, an abort
   --  included, and releases nothing when the lock was never granted.
   type Guard (DB : not null access Database.Handle) is new Ada.Finalization.Limited_Controlled with record
      Claim : Database.Lock_Claim;
   end record;

   overriding procedure Finalize (G : in out Guard);

   overriding procedure Finalize (G : in out Guard) is
   begin
      G.DB.Lock.End_Write (G.Claim);
   end Finalize;

   function Run_Waiting (DB : in out Database.Handle) return Database.Status.Result is
      G       : Guard (DB'Unrestricted_Access);
      Granted : Boolean;
   begin
      if DB.Lock.Held_By_Current_Task then
         return Database.Status.Failure
           (Database.Status.Transaction_Conflict, "the calling task already holds the write lock");
      end if;
      DB.Lock.Begin_Exclusive (G.Claim, Granted);
      if not Granted then
         return Database.Status.Failure (Database.Status.Transaction_Conflict, "the write lock was not granted");
      end if;
      return Work (DB);
   end Run_Waiting;

   function Try_Run (DB : in out Database.Handle; Refused : Database.Status.Result) return Database.Status.Result is
      G       : Guard (DB'Unrestricted_Access);
      Granted : Boolean;
   begin
      DB.Lock.Try_Begin_Exclusive (G.Claim, Granted);
      if not Granted then
         return Refused;
      end if;
      return Work (DB);
   end Try_Run;

   function Try_Close (DB : in out Database.Handle; Refused : Database.Status.Result) return Database.Status.Result is
      G       : Guard (DB'Unrestricted_Access);
      Granted : Boolean;
   begin
      DB.Lock.Try_Begin_Close (G.Claim, Granted);
      if not Granted then
         return Refused;
      end if;
      return Work (DB);
   end Try_Close;
end Database.Exclusive;
