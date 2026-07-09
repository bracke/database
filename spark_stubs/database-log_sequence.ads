package Database.Log_Sequence
  with SPARK_Mode => On
is
   type Log_Sequence_Number is mod 2 ** 64;
   Invalid_LSN : constant Log_Sequence_Number := 0;
end Database.Log_Sequence;
