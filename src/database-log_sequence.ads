--  Log sequence number support for write-ahead logging.
--  LSN values are monotonically increasing identifiers assigned to WAL records.
package Database.Log_Sequence is
   --  Log_Sequence_Number defines a public database type used by this package.
   type Log_Sequence_Number is mod 2 ** 64;
   --  WAL_Frame_Id defines a public database type used by this package.
   type WAL_Frame_Id is new Natural;

   --  Invalid_LSN is a public constant used by this package.
   Invalid_LSN : constant Log_Sequence_Number := 0;

   --  Generator defines a public database type used by this package.
   type Generator is private;

   --  Perform reset for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param Start_At start at argument supplied to the operation.
   procedure Reset (G : in out Generator; Start_At : Log_Sequence_Number := Invalid_LSN);
   --  Return allocate for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Allocate (G : in out Generator) return Log_Sequence_Number;
   --  Perform observe for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @param LSN lsn argument supplied to the operation.
   procedure Observe (G : in out Generator; LSN : Log_Sequence_Number);
   --  Return current for the supplied database state or arguments.
   --  @param G g argument supplied to the operation.
   --  @return Result produced by the function.
   function Current (G : Generator) return Log_Sequence_Number;

   --  Return is after for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_After (Left, Right : Log_Sequence_Number) return Boolean is (Left > Right);
   --  Return is at or after for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_At_Or_After (Left, Right : Log_Sequence_Number) return Boolean is (Left >= Right);

private
   --  Generator stores the public fields for this database abstraction.
   type Generator is record
      Last : Log_Sequence_Number := Invalid_LSN;
   end record;
end Database.Log_Sequence;
