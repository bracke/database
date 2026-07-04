--  Deterministic value ordering helpers used by queries and indexes.
with Database.Values;

   --  Public nested package `Database.Ordering`.
package Database.Ordering is
   --  Public type `Direction`.
   type Direction is (Ascending, Descending);

   --  Public operation `Less`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Dir dir argument supplied to the operation.
   --  @return Result produced by the function.
   function Less
     (Left, Right : Database.Values.Value;
      Dir         : Direction := Ascending) return Boolean;

   --  Public operation `Compare`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare
     (Left, Right : Database.Values.Value) return Integer;
end Database.Ordering;
