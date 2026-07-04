with Database;
with Database.Status;
with Database.Transactions;

procedure Main is
   DB : Database.Handle;
   R1, R2 : Database.Transactions.Transaction;
   W : Database.Transactions.Transaction;
   Granted : Boolean;
begin
   Database.Open_In_Memory (DB);
   Database.Transactions.Begin_Read (DB, R1);
   Database.Transactions.Try_Begin_Read (DB, R2, Granted);
   pragma Assert (Granted, "second reader was not granted");
   Database.Transactions.Try_Begin_Write (DB, W, Granted);
   pragma Assert (not Granted, "writer granted while readers are active");
   Database.Transactions.Rollback (R2);
   Database.Transactions.Rollback (R1);
   Database.Transactions.Try_Begin_Write (DB, W, Granted);
   pragma Assert (Granted, "writer not granted after readers released");
   pragma Assert (Database.Status.Is_Ok (Database.Transactions.Commit (W)), "writer commit failed");
   Database.Close (DB);
end Main;
