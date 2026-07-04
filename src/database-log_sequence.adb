package body Database.Log_Sequence is
   procedure Reset (G : in out Generator; Start_At : Log_Sequence_Number := Invalid_LSN) is
   begin
      G.Last := Start_At;
   end Reset;

   function Allocate (G : in out Generator) return Log_Sequence_Number is
   begin
      G.Last := G.Last + 1;
      return G.Last;
   end Allocate;

   procedure Observe (G : in out Generator; LSN : Log_Sequence_Number) is
   begin
      if LSN > G.Last then
         G.Last := LSN;
      end if;
   end Observe;

   function Current (G : Generator) return Log_Sequence_Number is (G.Last);
end Database.Log_Sequence;
