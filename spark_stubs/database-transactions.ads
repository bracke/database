package Database.Transactions
  with SPARK_Mode => On
is
   type Transaction_Mode is (Read_Only, Read_Write);
   type Transaction_State is (Active, Committing, Committed, Rolling_Back, Rolled_Back, Failed);
end Database.Transactions;
