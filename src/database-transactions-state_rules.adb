package body Database.Transactions.State_Rules
  with SPARK_Mode => On
is
   function Is_Active_State (State : Transaction_State) return Boolean is
   begin
      return State = Active;
   end Is_Active_State;

   function Can_Read_State (State : Transaction_State) return Boolean is
   begin
      return Is_Active_State (State);
   end Can_Read_State;

   function Can_Write_State
     (State : Transaction_State;
      Mode  : Transaction_Mode) return Boolean
   is
   begin
      return Is_Active_State (State) and then Mode = Read_Write;
   end Can_Write_State;
end Database.Transactions.State_Rules;
