--  Null-aware row predicates used for filtered scans and query pipelines.
with Database.Rows;
with Database.Values;

   --  Public nested package `Database.Predicates`.
package Database.Predicates is
   --  Public type `Predicate_Kind`.
   type Predicate_Kind is
     (Always_True,
      Equals,
      Not_Equals,
      Less_Than,
      Less_Or_Equal,
      Greater_Than,
      Greater_Or_Equal,
      And_Predicate,
      Or_Predicate);
   --  Public type `Predicate`.
   type Predicate is private;

   --  Public operation `True_Predicate`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @return Result produced by the function.
   function True_Predicate return Predicate;
   --  Public operation `Column_Equals`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Column_Equals (Index : Natural; Value : Database.Values.Value) return Predicate;
   --  Public operation `Column_Not_Equals`. See the package documentation for transaction, ownership, and error-
   --  result semantics.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Column_Not_Equals (Index : Natural; Value : Database.Values.Value) return Predicate;
   --  Return column less than for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Column_Less_Than (Index : Natural; Value : Database.Values.Value) return Predicate;
   --  Return column less or equal for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Column_Less_Or_Equal (Index : Natural; Value : Database.Values.Value) return Predicate;
   --  Return column greater than for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Column_Greater_Than (Index : Natural; Value : Database.Values.Value) return Predicate;
   --  Return column greater or equal for the supplied database state or arguments.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Column_Greater_Or_Equal (Index : Natural; Value : Database.Values.Value) return Predicate;
   --  Composes two predicates with null-aware logical conjunction.
   --  @param L Left predicate operand.
   --  @param R Right predicate operand.
   --  @return Predicate that matches only when both operands match.
   function "and" (L, R : Predicate) return Predicate;
   --  Composes two predicates with null-aware logical disjunction.
   --  @param L Left predicate operand.
   --  @param R Right predicate operand.
   --  @return Predicate that matches when either operand matches.
   function "or" (L, R : Predicate) return Predicate;
   --  Public operation `Matches`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param P p argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   --  @return Result produced by the function.
   function Matches (P : Predicate; Row : Database.Rows.Row) return Boolean;

   --  Return the structural kind of a predicate for optimizer inspection.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Kind (P : Predicate) return Predicate_Kind;
   --  Return True when the predicate is a single-column comparison.
   --  @param P p argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Column_Comparison (P : Predicate) return Boolean;
   --  Return the referenced column for a single-column comparison.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Column_Index (P : Predicate) return Natural;
   --  Return the literal value for a single-column comparison.
   --  @param P p argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Literal_Value (P : Predicate) return Database.Values.Value;
   --  Return the left operand of a composed predicate, or True_Predicate.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Left (P : Predicate) return Predicate;
   --  Return the right operand of a composed predicate, or True_Predicate.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Right (P : Predicate) return Predicate;

private
   --  Public type `Predicate_Access`.
   type Predicate_Access is access Predicate;
   --  Public type `Predicate`.
   type Predicate is record
      Kind  : Predicate_Kind := Always_True;
      Index : Natural := 0;
      Value : Database.Values.Value := Database.Values.Null_Value;
      Left  : Predicate_Access := null;
      Right : Predicate_Access := null;
   end record;
end Database.Predicates;
