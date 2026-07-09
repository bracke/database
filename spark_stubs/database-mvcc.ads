package Database.MVCC
  with SPARK_Mode => On
is
   type Transaction_Lifecycle is (Unknown, Active, Committed, Rolled_Back);
end Database.MVCC;
