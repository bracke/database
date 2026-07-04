--  Ada-native composable query pipeline over database rows.
with Ada.Containers.Indefinite_Vectors;
with Database.Aggregates;
with Database.Ordering;
with Database.Predicates;
with Database.Rows;
use Database.Rows;
with Database.Status;
with Database.Plans;
with Database.Execution_Plans;
with Database.Transactions;
with Database.Full_Text.Queries;

   --  Public nested package `Database.Queries`.
package Database.Queries is
   --  Public nested package `Row_Vectors`.
   package Row_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Database.Rows.Row);
   --  Public nested package `Column_Vectors`.
   package Column_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Natural);

   --  Public type `Query`.
   type Query is tagged private;
   --  Public type `Cursor`.
   type Cursor is private;

   --  Public operation `Empty`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @return Result produced by the function.
   function Empty return Query;
   --  Public operation `From_Rows`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Rows rows argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Rows (Rows : Row_Vectors.Vector) return Query;
   --  Public operation `Append`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @param Row row value supplied to or returned by the operation.
   procedure Append (Q : in out Query; Row : Database.Rows.Row);

   --  Public operation `Filter`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @param P p argument supplied to the operation.
   --  @return Result produced by the function.
   function Filter (Q : Query; P : Database.Predicates.Predicate) return Query;
   --  Return a query containing only the selected columns.
   --  This convenience function returns an empty query if validation fails.
   --  @param Q q argument supplied to the operation.
   --  @param Columns columns argument supplied to the operation.
   --  @return Result produced by the function.
   function Project (Q : Query; Columns : Column_Vectors.Vector) return Query;

   --  Validate projection columns and produce a projected query.
   --  Returns Invalid_Argument if any selected column is absent in any row.
   --  @param Q q argument supplied to the operation.
   --  @param Columns columns argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Try_Project
     (Q       : Query;
      Columns : Column_Vectors.Vector;
      Result  : out Query) return Database.Status.Result;
   --  Return a stably ordered query. NULL values sort last.
   --  This convenience function returns an empty query if validation fails.
   --  @param Q q argument supplied to the operation.
   --  @param Column column argument supplied to the operation.
   --  @param Dir dir argument supplied to the operation.
   --  @return Result produced by the function.
   function Order_By
     (Q      : Query;
      Column : Natural;
      Dir    : Database.Ordering.Direction := Database.Ordering.Ascending) return Query;

   --  Validate the ordering column and produce a stably ordered query.
   --  Returns Invalid_Argument if the column is absent in any row.
   --  @param Q q argument supplied to the operation.
   --  @param Column column argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @param Dir dir argument supplied to the operation.
   --  @return Result produced by the function.
   function Try_Order_By
     (Q      : Query;
      Column : Natural;
      Result : out Query;
      Dir    : Database.Ordering.Direction := Database.Ordering.Ascending) return Database.Status.Result;
   --  Public operation `Limit`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @param Count count argument supplied to the operation.
   --  @return Result produced by the function.
   function Limit (Q : Query; Count : Natural) return Query;
   --  Public operation `Offset`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @param Count count argument supplied to the operation.
   --  @return Result produced by the function.
   function Offset (Q : Query; Count : Natural) return Query;
   --  Public operation `Slice`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @param Offset_Count offset count argument supplied to the operation.
   --  @param Limit_Count limit count argument supplied to the operation.
   --  @return Result produced by the function.
   function Slice (Q : Query; Offset_Count, Limit_Count : Natural) return Query;

   --  Compute aggregate result values over the query.
   --  Aggregates ignore NULL except Count, and numeric aggregates reject non-numeric values.
   --  @param Q q argument supplied to the operation.
   --  @param Aggregates aggregates argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Aggregate
     (Q          : Query;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector;
      Result     : out Database.Rows.Row) return Database.Status.Result;

   --  Group rows by one or more columns and append aggregate values per group.
   --  Group-key NULL values are treated as ordinary key values.
   --  @param Q q argument supplied to the operation.
   --  @param Columns columns argument supplied to the operation.
   --  @param Aggregates aggregates argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Group_By
     (Q          : Query;
      Columns    : Column_Vectors.Vector;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector;
      Result     : out Query) return Database.Status.Result;

   --  Execute a full-text search and expose the matching rows as a normal
   --  Ada-native query value, so callers can compose it with Filter,
   --  Order_By, Limit, projection, grouping, and other relational operators.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param FT_Query ft query argument supplied to the operation.
   --  @return Result produced by the function.
   function Full_Text_Search
     (Tx    : in out Database.Transactions.Transaction;
      Index : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query) return Query;

   --  Status-returning full-text query integration. Prefer this operation in
   --  production code because it reports missing full-text indexes and row
   --  resolution failures instead of returning an indistinguishable empty
   --  query.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param FT_Query ft query argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Try_Full_Text_Search
     (Tx       : in out Database.Transactions.Transaction;
      Index    : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query;
      Result   : out Query) return Database.Status.Result;

   --  Execute a full-text search and append the computed rank as an extra
   --  trailing Float_Value column named by convention by the caller. This
   --  keeps the core Query row model unchanged while allowing normal
   --  Order_By/Limit composition on the score column.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param FT_Query ft query argument supplied to the operation.
   --  @return Result produced by the function.
   function Full_Text_Search_With_Score
     (Tx       : in out Database.Transactions.Transaction;
      Index    : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query) return Query;

   --  Status-returning scored full-text query integration. Each output row is
   --  the resolved table row plus one trailing Float_Value containing rank.
   --  @param Tx transaction object that scopes the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @param FT_Query ft query argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Try_Full_Text_Search_With_Score
     (Tx       : in out Database.Transactions.Transaction;
      Index    : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query;
      Result   : out Query) return Database.Status.Result;

   --  Public operation `Execute`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @param C c argument supplied to the operation.
   procedure Execute (Q : Query; C : out Cursor);
   --  Public operation `Has_Element`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param C c argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Has_Element (C : Cursor) return Boolean;
   --  Public operation `Element`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param C c argument supplied to the operation.
   --  @return Requested value or optional value according to the package contract.
   function Element (C : Cursor) return Database.Rows.Row;
   --  Public operation `Next`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param C c argument supplied to the operation.
   procedure Next (C : in out Cursor);
   --  Public operation `Row_Count`. See the package documentation for transaction, ownership, and error-result
   --  semantics.
   --  @param Q q argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Row_Count (Q : Query) return Natural;
   --  Public operation `Rows`. See the package documentation for transaction, ownership, and error-result semantics.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Rows (Q : Query) return Row_Vectors.Vector;

   --  Durable image for stored view definitions. This representation is
   --  explicit and versioned;
   --  it never serializes Ada object memory.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Persistent_Image (Q : Query) return Wide_Wide_String;

   --  Return from persistent image for the supplied database state or arguments.
   --  @param Image image argument supplied to the operation.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Persistent_Image
     (Image : Wide_Wide_String;
      Q     : out Query) return Database.Status.Result;

   --  Enable transparent optimizer use for this query value.
   --  @param Q q argument supplied to the operation.
   procedure Enable_Optimizer (Q : in out Query);
   --  Disable transparent optimizer use for this query value.
   --  @param Q q argument supplied to the operation.
   procedure Disable_Optimizer (Q : in out Query);
   --  Return whether this query value allows transparent optimizer use.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Optimizer_Enabled (Q : Query) return Boolean;
   --  Produce a stable diagnostic string for an already-built physical plan.
   --  @param Plan plan argument supplied to the operation.
   --  @return Result produced by the function.
   function Explain_Plan (Plan : Database.Execution_Plans.Physical_Plan) return Wide_Wide_String;

private
   --  Public type `Query`.
   type Query is tagged record
      Data : Row_Vectors.Vector;
      Use_Optimizer : Boolean := True;
   end record;
   --  Public type `Cursor`.
   type Cursor is record
      Data  : Row_Vectors.Vector;
      Index : Natural := 0;
   end record;
end Database.Queries;
