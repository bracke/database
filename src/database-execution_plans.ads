--  Physical execution plan representation and stable plan diagnostics.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Indexes;
with Database.Ordering;
with Database.Status;

--  Executable query-plan structures and diagnostics.
package Database.Execution_Plans is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Physical_Node_Kind defines a public database type used by this package.
   type Physical_Node_Kind is
     (Heap_Scan,
      Index_Lookup,
      Index_Range_Scan,
      Filter_Node,
      Projection_Node,
      Sort_Node,
      Limit_Node,
      Aggregate_Node,
      Hash_Group_Node,
      Nested_Loop_Join,
      Index_Nested_Loop_Join,
      Materialize_Node,
      Full_Text_Index_Search,
      Full_Text_Ranked_Search);

   --  Physical_Step stores the public fields for this database abstraction.
   type Physical_Step is record
      Node_Kind      : Physical_Node_Kind := Heap_Scan;
      Table_Id       : Natural := 0;
      Column_Id      : Natural := 0;
      Index          : Database.Indexes.Index_Metadata;
      Direction      : Database.Ordering.Direction := Database.Ordering.Ascending;
      Estimated_Cost : Long_Float := 0.0;
      Estimated_Rows : Natural := 0;
      Details        : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
   end record;

   --  Step_Vectors stores ordered step values for this package.
   package Step_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Physical_Step);

   --  Physical_Plan stores the public fields for this database abstraction.
   type Physical_Plan is record
      Steps          : Step_Vectors.Vector;
      Estimated_Cost : Long_Float := 0.0;
      Estimated_Rows : Natural := 0;
   end record;

   --  Physical_Plan_Result stores the public fields for this database abstraction.
   type Physical_Plan_Result is record
      Status : Database.Status.Result := Database.Status.Success;
      Plan   : Physical_Plan;
   end record;

   --  Perform append for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Step step argument supplied to the operation.
   procedure Append (Plan : in out Physical_Plan; Step : Physical_Step);
   --  Return contains for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Kind kind selector controlling the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Contains (Plan : Physical_Plan; Kind : Physical_Node_Kind) return Boolean;
   --  Return step count for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @return Number of items represented by the queried object.
   function Step_Count (Plan : Physical_Plan) return Natural;
   --  Return step for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @param Index zero-based or package-defined index used by the operation.
   --  @return Result produced by the function.
   function Step (Plan : Physical_Plan; Index : Natural) return Physical_Step;
   --  Return explain for the supplied database state or arguments.
   --  @param Plan plan argument supplied to the operation.
   --  @return Result produced by the function.
   function Explain (Plan : Physical_Plan) return Wide_Wide_String;
end Database.Execution_Plans;
