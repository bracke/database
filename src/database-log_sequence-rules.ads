package Database.Log_Sequence.Rules
  with SPARK_Mode => On
is
   function Next_LSN (Current : Log_Sequence_Number) return Log_Sequence_Number
     with
       Global => null,
       Post => Next_LSN'Result = Current + 1;

   function Observed_LSN
     (Current : Log_Sequence_Number;
      Seen    : Log_Sequence_Number) return Log_Sequence_Number
     with
       Global => null,
       Post =>
         Observed_LSN'Result = (if Seen > Current then Seen else Current)
         and then Observed_LSN'Result >= Current
         and then Observed_LSN'Result >= Seen;

   function Is_After_Rule
     (Left, Right : Log_Sequence_Number) return Boolean
     with
       Global => null,
       Post => Is_After_Rule'Result = (Left > Right);

   function Is_At_Or_After_Rule
     (Left, Right : Log_Sequence_Number) return Boolean
     with
       Global => null,
       Post => Is_At_Or_After_Rule'Result = (Left >= Right);
end Database.Log_Sequence.Rules;
