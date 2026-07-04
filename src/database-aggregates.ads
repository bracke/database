--  Aggregate specifications used by Database.Queries.
with Ada.Containers.Indefinite_Vectors;

   --  Public nested package `Database.Aggregates`.
package Database.Aggregates is
   --  Public type `Aggregate_Kind`.
   type Aggregate_Kind is (Count_All, Count_Column, Minimum, Maximum, Total, Average);

   --  Public type `Aggregate`.
   type Aggregate is record
      Kind   : Aggregate_Kind := Count_All;
      Column : Natural := 0;
   end record;

   --  Public nested package `Aggregate_Vectors`.
   package Aggregate_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Aggregate);

   --  Public operation `Count`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @return Number of items represented by the queried object.
   function Count return Aggregate;
   --  Public operation `Count`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Column column argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Count (Column : Natural) return Aggregate;
   --  Public operation `Min`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Column column argument supplied to the operation.
   --  @return Result produced by the function.
   function Min (Column : Natural) return Aggregate;
   --  Public operation `Max`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Column column argument supplied to the operation.
   --  @return Result produced by the function.
   function Max (Column : Natural) return Aggregate;
   --  Public operation `Sum`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Column column argument supplied to the operation.
   --  @return Result produced by the function.
   function Sum (Column : Natural) return Aggregate;
   --  Public operation `Avg`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Column column argument supplied to the operation.
   --  @return Result produced by the function.
   function Avg (Column : Natural) return Aggregate;
end Database.Aggregates;
