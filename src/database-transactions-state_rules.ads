package Database.Transactions.State_Rules
  with SPARK_Mode => On
is
   function Is_Active_State (State : Transaction_State) return Boolean
     with
       Global => null,
       Post => Is_Active_State'Result = (State = Active);

   function Can_Read_State (State : Transaction_State) return Boolean
     with
       Global => null,
       Post => Can_Read_State'Result = Is_Active_State (State);

   function Can_Write_State
     (State : Transaction_State;
      Mode  : Transaction_Mode) return Boolean
     with
       Global => null,
       Post => Can_Write_State'Result =
         (Is_Active_State (State) and then Mode = Read_Write);
end Database.Transactions.State_Rules;
