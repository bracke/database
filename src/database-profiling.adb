with Ada.Strings.Wide_Wide_Unbounded;
with Database.Metrics;

package body Database.Profiling is
   use Ada.Strings.Wide_Wide_Unbounded;

   function Build (Q : Database.Queries.Query) return Query_Profile is
      P : Query_Profile;
      Count : constant Natural := Database.Queries.Row_Count (Q);
      Op : Operator_Profile;
   begin
      P.Logical_Plan := To_Unbounded_Wide_Wide_String ("Ada-native query pipeline");
      P.Physical_Plan := To_Unbounded_Wide_Wide_String ("in-process row scan");
      if Database.Queries.Optimizer_Enabled (Q) then
         P.Optimizer_Decision  :=
           To_Unbounded_Wide_Wide_String ("optimizer enabled");
      else
         P.Optimizer_Decision  :=
           To_Unbounded_Wide_Wide_String ("optimizer disabled");
      end if;
      P.Rows_Scanned := Count;
      P.Rows_Returned := Count;
      Op.Name := To_Unbounded_Wide_Wide_String ("rows");
      Op.Rows_Scanned := Count;
      Op.Rows_Returned := Count;
      P.Operators.Append (Op);
      Database.Metrics.Increment_Query_Executions;
      Database.Metrics.Add_Rows_Scanned (Count);
      Database.Metrics.Add_Rows_Returned (Count);
      return P;
   end Build;

   function Profile_Query (Q : Database.Queries.Query) return Query_Profile is (Build (Q));

   function Try_Profile_Query
     (Q       : Database.Queries.Query;
      Profile : out Query_Profile) return Database.Status.Result is
   begin
      Profile := Build (Q);
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure (Database.Status.Profiling_Error, "query profiling failed");
   end Try_Profile_Query;
end Database.Profiling;
