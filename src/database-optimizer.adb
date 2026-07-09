with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
use Ada.Strings.Wide_Wide_Unbounded;
with Database.Indexes;
with Database.Predicates;
with Database.Status;
with Database.Ordering;
with Database.Types;
with Database.Metrics;

package body Database.Optimizer is
   use type Ada.Containers.Count_Type;
   use type Database.Ordering.Direction;
   use type Database.Plans.Logical_Node_Kind;
   use type Database.Indexes.Index_Id;
   use type Database.Predicates.Predicate_Kind;
   use type Database.Types.Value_Kind;
   function Default_Settings return Optimizer_Settings is
   begin
      return (Enabled => True, Force_Heap_Scan => False);
   end Default_Settings;

   function Base_Rows (Plan : Database.Plans.Logical_Plan) return Natural is
   begin
      if Database.Plans.Step_Count (Plan) = 0 then
         return 0;
      end if;
      return Database.Plans.Step (Plan, 0).Stats.Row_Count;
   end Base_Rows;

   function Base_Pages (Plan : Database.Plans.Logical_Plan) return Natural is
   begin
      if Database.Plans.Step_Count (Plan) = 0 then
         return 0;
      end if;
      return Database.Plans.Step (Plan, 0).Stats.Page_Count;
   end Base_Pages;

   function Matching_Index
     (Indexes : Database.Indexes.Index_Metadata_Vectors.Vector;
      Column  : Natural;
      Unique_Only : Boolean := False) return Database.Indexes.Index_Metadata is
   begin
      for I of Indexes loop
         if I.Column_Id = Column and then (not Unique_Only or else I.Unique) then
            return I;
         end if;
      end loop;
      return (others => <>);
   end Matching_Index;

   function Has_Index_For
     (Indexes : Database.Indexes.Index_Metadata_Vectors.Vector;
      Column  : Natural) return Boolean is
   begin
      for I of Indexes loop
         if I.Column_Id = Column then
            return True;
         end if;
      end loop;
      return False;
   end Has_Index_For;

   function Is_Indexable_Comparison (P : Database.Predicates.Predicate) return Boolean is
   begin
      return Database.Predicates.Kind (P) in
        Database.Predicates.Equals | Database.Predicates.Less_Than |
        Database.Predicates.Less_Or_Equal | Database.Predicates.Greater_Than |
        Database.Predicates.Greater_Or_Equal;
   end Is_Indexable_Comparison;

   function Extract_Indexable
     (P       : Database.Predicates.Predicate;
      Indexes : Database.Indexes.Index_Metadata_Vectors.Vector;
      Found   : out Boolean) return Database.Predicates.Predicate is
      L_Found : Boolean := False;
      R_Found : Boolean := False;
      L : Database.Predicates.Predicate;
      R : Database.Predicates.Predicate;
   begin
      Found := False;
      if Is_Indexable_Comparison (P) and then
        Database.Predicates.Literal_Value (P).Kind /= Database.Types.Null_Value and then
        Has_Index_For (Indexes, Database.Predicates.Column_Index (P))
      then
         Found := True;
         return P;
      elsif Database.Predicates.Kind (P) = Database.Predicates.And_Predicate then
         L := Extract_Indexable (Database.Predicates.Left (P), Indexes, L_Found);
         if L_Found then
            Found := True;
            return L;
         end if;
         R := Extract_Indexable (Database.Predicates.Right (P), Indexes, R_Found);
         if R_Found then
            Found := True;
            return R;
         end if;
      end if;
      return P;
   end Extract_Indexable;

   function Needs_Residual_Filter
     (Original : Database.Predicates.Predicate;
      Chosen   : Database.Predicates.Predicate;
      Chosen_Used : Boolean) return Boolean is
   begin
      if not Chosen_Used then
         return Database.Predicates.Kind (Original) /= Database.Predicates.Always_True;
      end if;
      return Database.Predicates.Kind (Original) /= Database.Predicates.Kind (Chosen)
        or else Database.Predicates.Kind (Original) = Database.Predicates.And_Predicate
        or else Database.Predicates.Kind (Original) = Database.Predicates.Or_Predicate;
   end Needs_Residual_Filter;

   procedure Emit_Access_Path
     (Out_Plan : in out Database.Execution_Plans.Physical_Plan;
      Scan     : Database.Plans.Logical_Step;
      Filter   : Database.Plans.Logical_Step;
      Have_Filter : Boolean;
      Settings : Optimizer_Settings) is
      use Database.Execution_Plans;
      Rows : constant Natural := Natural'Max (1, Scan.Stats.Row_Count);
      Pages : constant Natural := Natural'Max (1, Scan.Stats.Page_Count);
      S : Physical_Step;
      Indexed : Database.Indexes.Index_Metadata;
      Chosen : Database.Predicates.Predicate := Filter.Predicate;
      Found_Indexable : Boolean := False;
   begin
      if Settings.Enabled and then not Settings.Force_Heap_Scan and then Have_Filter then
         Chosen := Extract_Indexable (Filter.Predicate, Scan.Indexes, Found_Indexable);
      end if;

      if Settings.Enabled and then not Settings.Force_Heap_Scan and then Have_Filter and then Found_Indexable then
         Indexed := Matching_Index (Scan.Indexes, Database.Predicates.Column_Index (Chosen));
         if Indexed.Id /= 0 or else Indexed.Column_Id = Database.Predicates.Column_Index (Chosen) then
            S.Node_Kind  :=
              (if Database.Predicates.Kind (Chosen)
                = Database.Predicates.Equals then Index_Lookup else Index_Range_Scan);
            S.Table_Id := Scan.Table_Id;
            S.Column_Id := Indexed.Column_Id;
            S.Index := Indexed;
            S.Estimated_Rows := (if Indexed.Unique then 1 else Natural'Max (1, Rows / 10));
            S.Estimated_Cost := 2.0 + Long_Float (S.Estimated_Rows);
            S.Details  :=
              To_Unbounded_Wide_Wide_String ((if S.Node_Kind
                = Index_Lookup then "equality predicate uses index" else "range predicate uses index"));
            Append (Out_Plan, S);
            return;
         end if;
      end if;

      S.Node_Kind := Heap_Scan;
      S.Table_Id := Scan.Table_Id;
      S.Estimated_Rows := Rows;
      S.Estimated_Cost := Long_Float (Pages + Rows);
      S.Details := To_Unbounded_Wide_Wide_String ("heap access path");
      Append (Out_Plan, S);
   end Emit_Access_Path;

   function Optimize
     (Tx       : in out Database.Transactions.Transaction;
      Plan     : Database.Plans.Logical_Plan;
      Settings : Optimizer_Settings := Default_Settings)
      return Database.Execution_Plans.Physical_Plan_Result is
      pragma Unreferenced (Tx);
      use Database.Execution_Plans;
      Result : Physical_Plan_Result;
      Have_Filter : Boolean := False;
      First_Filter : Database.Plans.Logical_Step;
      Scan : Database.Plans.Logical_Step;
      Have_Scan : Boolean := False;
   begin
      Database.Metrics.Increment_Optimizer_Plans;
      if Settings.Force_Heap_Scan or else not Settings.Enabled then
         Database.Metrics.Increment_Heap_Scan_Fallbacks;
      end if;
      Result.Status := Database.Status.Success;
      if Database.Plans.Step_Count (Plan) = 0 then
         Result.Status := Database.Status.Failure (Database.Status.Invalid_Argument, "empty logical plan");
         return Result;
      end if;

      for I in 0 .. Database.Plans.Step_Count (Plan) - 1 loop
         declare
            L : constant Database.Plans.Logical_Step := Database.Plans.Step (Plan, I);
         begin
            if L.Node_Kind = Database.Plans.Table_Scan and then not Have_Scan then
               Scan := L;
               Have_Scan := True;
            elsif L.Node_Kind = Database.Plans.Filter and then not Have_Filter then
               First_Filter := L;
               Have_Filter := True;
            end if;
         end;
      end loop;

      if not Have_Scan then
         Result.Status := Database.Status.Failure (Database.Status.Invalid_Argument,
           "logical plan has no table scan");
         return Result;
      end if;

      Emit_Access_Path (Result.Plan, Scan, First_Filter, Have_Filter, Settings);

      for I in 0 .. Database.Plans.Step_Count (Plan) - 1 loop
         declare
            L : constant Database.Plans.Logical_Step := Database.Plans.Step (Plan, I);
            S : Physical_Step;
            Rows : constant Natural := Natural'Max (1, Base_Rows (Plan));
         begin
            case L.Node_Kind is
               when Database.Plans.Table_Scan =>
                  null;
               when Database.Plans.Filter =>
                  declare
                     Chosen : Database.Predicates.Predicate := L.Predicate;
                     Found_Indexable : Boolean := False;
                  begin
                     if Settings.Enabled and then not Settings.Force_Heap_Scan then
                        Chosen := Extract_Indexable (L.Predicate, Scan.Indexes, Found_Indexable);
                     end if;
                     if Needs_Residual_Filter (L.Predicate, Chosen, Found_Indexable) then
                     S.Node_Kind := Filter_Node;
                     S.Estimated_Rows := Natural'Max (1, Rows / 2);
                     S.Estimated_Cost := Long_Float (Rows);
                     S.Details := To_Unbounded_Wide_Wide_String ("predicate retained as filter node");
                     Append (Result.Plan, S);
                     end if;
                  end;
               when Database.Plans.Project =>
                  S.Node_Kind := Projection_Node;
                  S.Estimated_Rows := Result.Plan.Estimated_Rows;
                  S.Estimated_Cost := Long_Float (S.Estimated_Rows) / 10.0;
                  S.Details := To_Unbounded_Wide_Wide_String ("projection pruning boundary");
                  Append (Result.Plan, S);
               when Database.Plans.Order =>
                  if not (Settings.Enabled
                    and then Has_Index_For (Scan.Indexes, L.Order_Column))
                  then
                     S.Node_Kind := Sort_Node;
                     S.Column_Id := L.Order_Column;
                     S.Direction := L.Direction;
                     S.Estimated_Rows := Result.Plan.Estimated_Rows;
                     S.Estimated_Cost := Long_Float (Rows * 2);
                     S.Details := To_Unbounded_Wide_Wide_String ("materialized ordering");
                     Append (Result.Plan, S);
                  end if;
               when Database.Plans.Limit =>
                  S.Node_Kind := Limit_Node;
                  S.Estimated_Rows := Natural'Min (L.Count, Result.Plan.Estimated_Rows);
                  S.Estimated_Cost := 1.0;
                  S.Details := To_Unbounded_Wide_Wide_String ("limit after semantic barriers");
                  Append (Result.Plan, S);
               when Database.Plans.Offset =>
                  S.Node_Kind := Materialize_Node;
                  S.Estimated_Rows  :=
                    (if Result.Plan.Estimated_Rows > L.Count then Result.Plan.Estimated_Rows - L.Count else 0);
                  S.Estimated_Cost := Long_Float (Rows);
                  S.Details := To_Unbounded_Wide_Wide_String ("offset requires ordered materialization");
                  Append (Result.Plan, S);
               when Database.Plans.Aggregate =>
                  S.Node_Kind := Aggregate_Node;
                  S.Estimated_Rows := 1;
                  S.Estimated_Cost := Long_Float (Rows);
                  S.Details := To_Unbounded_Wide_Wide_String ("aggregate execution");
                  Append (Result.Plan, S);
               when Database.Plans.Group =>
                  S.Node_Kind := Hash_Group_Node;
                  S.Estimated_Rows := Natural'Max (1, Rows / 10);
                  S.Estimated_Cost := Long_Float (Rows);
                  S.Details := To_Unbounded_Wide_Wide_String ("group execution");
                  Append (Result.Plan, S);
               when Database.Plans.Full_Text_Search =>
                  S.Node_Kind := Full_Text_Ranked_Search;
                  S.Table_Id := Scan.Table_Id;
                  S.Estimated_Rows := Natural'Max (1, Rows / 10);
                  S.Estimated_Cost := Long_Float (S.Estimated_Rows);
                  S.Details := To_Unbounded_Wide_Wide_String
                    ("full-text ranked search using index " & To_Wide_Wide_String (L.Full_Text_Index_Name));
                  Append (Result.Plan, S);
               when Database.Plans.Join =>
                  if Settings.Enabled and then L.Columns.Length >= 2 and then Has_Index_For  (Scan.Indexes,
                    L.Columns.Element (1)) then
                     S.Node_Kind := Index_Nested_Loop_Join;
                     S.Estimated_Rows := Rows;
                     S.Estimated_Cost := Long_Float (Rows * 4);
                     S.Details := To_Unbounded_Wide_Wide_String ("indexed inner join on declared join column");
                  else
                     S.Node_Kind := Nested_Loop_Join;
                     S.Estimated_Rows := Rows;
                     S.Estimated_Cost := Long_Float (Rows * Rows);
                     S.Details := To_Unbounded_Wide_Wide_String ("safe nested loop join fallback");
                  end if;
                  Append (Result.Plan, S);
            end case;
         end;
      end loop;
      return Result;
   end Optimize;
end Database.Optimizer;
