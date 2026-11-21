package body Database.Exclusive is
   function Run
     (DB      : in out Database.Handle;
      Wait    : Boolean;
      Refused : Database.Status.Result) return Database.Status.Result
   is
      Granted : Boolean := True;
      R       : Database.Status.Result;
   begin
      if Wait then
         DB.Lock.Begin_Exclusive;
      else
         DB.Lock.Try_Begin_Exclusive (Granted);
         if not Granted then
            return Refused;
         end if;
      end if;
      begin
         R := Work (DB);
      exception
         when others =>
            DB.Lock.End_Write;
            raise;
      end;
      DB.Lock.End_Write;
      return R;
   end Run;
end Database.Exclusive;
