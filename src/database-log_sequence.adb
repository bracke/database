with Database.Log_Sequence.Rules;

package body Database.Log_Sequence is
   procedure Reset (G : in out Generator; Start_At : Log_Sequence_Number := Invalid_LSN) is
   begin
      G.Last := Start_At;
   end Reset;

   function Allocate (G : in out Generator) return Log_Sequence_Number is
   begin
      G.Last := Database.Log_Sequence.Rules.Next_LSN (G.Last);
      return G.Last;
   end Allocate;

   procedure Observe (G : in out Generator; LSN : Log_Sequence_Number) is
   begin
      G.Last := Database.Log_Sequence.Rules.Observed_LSN (G.Last, LSN);
   end Observe;

   function Current (G : Generator) return Log_Sequence_Number is (G.Last);
end Database.Log_Sequence;
