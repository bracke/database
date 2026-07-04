--  Simple explicit join operations for query results.
with Database.Queries;
with Database.Status;

   --  Public nested package `Database.Joins`.
package Database.Joins is
   --  Explicit equality predicate used by nested-loop joins.
   type Equality_Predicate is record
      Left_Column  : Natural := 0;
      Right_Column : Natural := 0;
   end record;

   --  Build an equality predicate between one left and one right column.
   --  @param Left_Column left column argument supplied to the operation.
   --  @param Right_Column right column argument supplied to the operation.
   --  @return Result produced by the function.
   function On_Equal (Left_Column, Right_Column : Natural) return Equality_Predicate;

   --  Join by explicit column indexes. NULL keys do not match.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Left_Column left column argument supplied to the operation.
   --  @param Right_Column right column argument supplied to the operation.
   --  @return Result produced by the function.
   function Inner_Join
     (Left         : Database.Queries.Query;
      Right        : Database.Queries.Query;
      Left_Column  : Natural;
      Right_Column : Natural) return Database.Queries.Query;

   --  Join by an explicit equality predicate. NULL keys do not match.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param On on argument supplied to the operation.
   --  @return Result produced by the function.
   function Inner_Join
     (Left  : Database.Queries.Query;
      Right : Database.Queries.Query;
      On    : Equality_Predicate) return Database.Queries.Query;

   --  Validate join columns and perform a nested-loop inner join.
   --  Returns Invalid_Argument if either join column is absent.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param On on argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Try_Inner_Join
     (Left   : Database.Queries.Query;
      Right  : Database.Queries.Query;
      On     : Equality_Predicate;
      Result : out Database.Queries.Query) return Database.Status.Result;
end Database.Joins;
