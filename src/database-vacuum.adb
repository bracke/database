with Database.Status;
with Database.Transactions;

package body Database.Vacuum is

   function Vacuum
     (Tx : in out Database.Transactions.Transaction) return Database.Status.Result is
   begin
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure
           (Database.Status.Read_Only_Transaction,
            "vacuum requires a read-write transaction");
      end if;
      return Database.Status.Success;
   end Vacuum;

end Database.Vacuum;
