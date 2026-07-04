--  Logical query plans for Ada-native query composition.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Aggregates;
with Database.Indexes;
with Database.Ordering;
with Database.Predicates;

--  Logical and physical query plan structures.
package Database.Plans is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Logical_Node_Kind defines a public database type used by this package.
   type Logical_Node_Kind is
     (Table_Scan,
      Filter,
      Project,
      Order,
      Limit,
      Offset,
      Aggregate,
      Group,
      Join,
      Full_Text_Search);

   --  Column_Vectors stores ordered column values for this package.
   package Column_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Natural);

   --  Table_Statistics stores the public fields for this database abstraction.
   type Table_Statistics is record
      Row_Count  : Natural := 0;
      Page_Count : Natural := 0;
   end record;

   --  Logical_Step stores the public fields for this database abstraction.
   type Logical_Step is record
      Node_Kind  : Logical_Node_Kind := Table_Scan;
      Table_Id   : Natural := 0;
      Table_Name : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Predicate  : Database.Predicates.Predicate := Database.Predicates.True_Predicate;
      Columns    : Column_Vectors.Vector;
      Order_Column : Natural := 0;
      Direction  : Database.Ordering.Direction := Database.Ordering.Ascending;
      Count      : Natural := 0;
      Stats      : Table_Statistics;
      Indexes    : Database.Indexes.Index_Metadata_Vectors.Vector;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector;
      Full_Text_Index_Name : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Full_Text_Query      : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
   end record;

   --  Step_Vectors stores ordered step values for this package.
   package Step_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Logical_Step);

   --  Logical_Plan stores the public fields for this database abstraction.
   type Logical_Plan is record
      Steps : Step_Vectors.Vector;
   end record;

   --  Return table for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Table_Id table id argument supplied to the operation.
   --  @param Stats stats argument supplied to the operation.
   --  @return Result produced by the function.
   function Table
     (Name    : Wide_Wide_String;
      Table_Id : Natural := 0;
      Stats   : Table_Statistics := (others => 0)) return Logical_Plan;
   --  Return with indexes for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Indexes indexes argument supplied to the operation.
   --  @return Result produced by the function.
   function With_Indexes
     (Plan    : Logical_Plan;
      Indexes : Database.Indexes.Index_Metadata_Vectors.Vector) return Logical_Plan;
   --  Return where for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Predicate predicate argument supplied to the operation.
   --  @return Result produced by the function.
   function Where (Plan : Logical_Plan; Predicate : Database.Predicates.Predicate) return Logical_Plan;
   --  Return project for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Columns columns argument supplied to the operation.
   --  @return Result produced by the function.
   function Project (Plan : Logical_Plan; Columns : Column_Vectors.Vector) return Logical_Plan;
   --  Return order by for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Column column argument supplied to the operation.
   --  @param Dir dir argument supplied to the operation.
   --  @return Result produced by the function.
   function Order_By
     (Plan   : Logical_Plan;
      Column : Natural;
      Dir    : Database.Ordering.Direction := Database.Ordering.Ascending) return Logical_Plan;
   --  Return limit for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Count count argument supplied to the operation.
   --  @return Result produced by the function.
   function Limit (Plan : Logical_Plan; Count : Natural) return Logical_Plan;
   --  Return offset for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Count count argument supplied to the operation.
   --  @return Result produced by the function.
   function Offset (Plan : Logical_Plan; Count : Natural) return Logical_Plan;
   --  Return aggregate by for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Aggregates aggregates argument supplied to the operation.
   --  @return Result produced by the function.
   function Aggregate_By
     (Plan       : Logical_Plan;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector) return Logical_Plan;
   --  Return group by for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Columns columns argument supplied to the operation.
   --  @param Aggregates aggregates argument supplied to the operation.
   --  @return Result produced by the function.
   function Group_By
     (Plan       : Logical_Plan;
      Columns    : Column_Vectors.Vector;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector) return Logical_Plan;
   --  Return inner join for the supplied database state or arguments.
   --  @param Left_Plan left plan argument supplied to the operation.
   --  @param Right_Plan right plan argument supplied to the operation.
   --  @param Left_Column left column argument supplied to the operation.
   --  @param Right_Column right column argument supplied to the operation.
   --  @return Result produced by the function.
   function Inner_Join
     (Left_Plan    : Logical_Plan;
      Right_Plan   : Logical_Plan;
      Left_Column  : Natural;
      Right_Column : Natural) return Logical_Plan;

   --  Add an Ada-native full-text search logical step. The optimizer lowers
   --  this to a full-text physical access node;
   --  no SQL string parser is used.
   --  @param Plan plan argument supplied to the operation.
   --  @param Index_Name index name argument supplied to the operation.
   --  @param Query query argument supplied to the operation.
   --  @return Result produced by the function.
   function Full_Text
     (Plan       : Logical_Plan;
      Index_Name : Wide_Wide_String;
      Query      : Wide_Wide_String) return Logical_Plan;
   --  Return step count for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Step_Count (Plan : Logical_Plan) return Natural;
   --  Return step for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Step (Plan : Logical_Plan; Index : Natural) return Logical_Step;
   --  Return referenced columns for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @return Result produced by the function.
   function Referenced_Columns (Plan : Logical_Plan) return Column_Vectors.Vector;
end Database.Plans;
