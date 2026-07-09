package body Database.Log_Sequence.Rules
  with SPARK_Mode => On
is
   function Next_LSN (Current : Log_Sequence_Number) return Log_Sequence_Number is
   begin
      return Current + 1;
   end Next_LSN;

   function Observed_LSN
     (Current : Log_Sequence_Number;
      Seen    : Log_Sequence_Number) return Log_Sequence_Number
   is
   begin
      if Seen > Current then
         return Seen;
      else
         return Current;
      end if;
   end Observed_LSN;

   function Is_After_Rule
     (Left, Right : Log_Sequence_Number) return Boolean
   is
   begin
      return Left > Right;
   end Is_After_Rule;

   function Is_At_Or_After_Rule
     (Left, Right : Log_Sequence_Number) return Boolean
   is
   begin
      return Left >= Right;
   end Is_At_Or_After_Rule;
end Database.Log_Sequence.Rules;
