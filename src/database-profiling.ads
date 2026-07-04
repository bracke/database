--  Query profiling and optimizer/execution diagnostics.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Queries;
with Database.Status;

--  Query and operation profiling support.
package Database.Profiling is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Operator_Profile stores the public fields for this database abstraction.
   type Operator_Profile is record
      Name          : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Rows_Scanned  : Natural := 0;
      Rows_Returned : Natural := 0;
      Duration      : Natural := 0;
   end record;

   --  Operator_Profile_Vectors stores ordered operator profile values for this package.
   package Operator_Profile_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Operator_Profile);

   --  Query_Profile stores the public fields for this database abstraction.
   type Query_Profile is record
      Logical_Plan       : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Physical_Plan      : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Optimizer_Decision : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
      Rows_Scanned       : Natural := 0;
      Rows_Returned      : Natural := 0;
      Index_Lookups      : Natural := 0;
      Sort_Duration      : Natural := 0;
      Join_Cost          : Natural := 0;
      Aggregate_Duration : Natural := 0;
      WAL_Flush_Latency  : Natural := 0;
      Operators          : Operator_Profile_Vectors.Vector;
   end record;

   --  Return profile query for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Profile_Query (Q : Database.Queries.Query) return Query_Profile;
   --  Return try profile query for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @param Profile profile argument supplied to the operation.
   --  @return Result produced by the function.
   function Try_Profile_Query
     (Q       : Database.Queries.Query;
      Profile : out Query_Profile) return Database.Status.Result;
end Database.Profiling;
