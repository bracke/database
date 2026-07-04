with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
use Ada.Strings.Wide_Wide_Unbounded;
package body Database.Plans is
   use type Ada.Containers.Count_Type;
   use type Database.Aggregates.Aggregate_Kind;
   procedure Append_Unique (Cols : in out Column_Vectors.Vector; Column : Natural) is
   begin
      for Existing of Cols loop
         if Existing = Column then
            return;
         end if;
      end loop;
      Cols.Append (Column);
   end Append_Unique;
   procedure Append_Predicate_Columns
     (Cols : in out Column_Vectors.Vector;
      P    : Database.Predicates.Predicate) is
   begin
      case Database.Predicates.Kind (P) is
         when Database.Predicates.Equals | Database.Predicates.Not_Equals |
              Database.Predicates.Less_Than | Database.Predicates.Less_Or_Equal |
              Database.Predicates.Greater_Than | Database.Predicates.Greater_Or_Equal =>
            Append_Unique (Cols, Database.Predicates.Column_Index (P));
         when Database.Predicates.And_Predicate | Database.Predicates.Or_Predicate =>
            Append_Predicate_Columns (Cols, Database.Predicates.Left (P));
            Append_Predicate_Columns (Cols, Database.Predicates.Right (P));
         when Database.Predicates.Always_True =>
            null;
      end case;
   end Append_Predicate_Columns;

   function Table
     (Name    : Wide_Wide_String;
      Table_Id : Natural := 0;
      Stats   : Table_Statistics := (others => 0)) return Logical_Plan is
      P : Logical_Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Table_Scan;
      S.Table_Id := Table_Id;
      S.Table_Name := To_Unbounded_Wide_Wide_String (Name);
      S.Stats := Stats;
      P.Steps.Append (S);
      return P;
   end Table;

   function With_Indexes
     (Plan    : Logical_Plan;
      Indexes : Database.Indexes.Index_Metadata_Vectors.Vector) return Logical_Plan is
      P : Logical_Plan := Plan;
   begin
      if P.Steps.Length > 0 then
         declare
            S : Logical_Step := P.Steps.Element (0);
         begin
            S.Indexes := Indexes;
            P.Steps.Replace_Element (0, S);
         end;
      end if;
      return P;
   end With_Indexes;

   function Where (Plan : Logical_Plan; Predicate : Database.Predicates.Predicate) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Filter;
      S.Predicate := Predicate;
      P.Steps.Append (S);
      return P;
   end Where;

   function Project (Plan : Logical_Plan; Columns : Column_Vectors.Vector) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Project;
      S.Columns := Columns;
      P.Steps.Append (S);
      return P;
   end Project;

   function Order_By
     (Plan   : Logical_Plan;
      Column : Natural;
      Dir    : Database.Ordering.Direction := Database.Ordering.Ascending) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Order;
      S.Order_Column := Column;
      S.Direction := Dir;
      P.Steps.Append (S);
      return P;
   end Order_By;

   function Limit (Plan : Logical_Plan; Count : Natural) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Limit;
      S.Count := Count;
      P.Steps.Append (S);
      return P;
   end Limit;

   function Offset (Plan : Logical_Plan; Count : Natural) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Offset;
      S.Count := Count;
      P.Steps.Append (S);
      return P;
   end Offset;

   function Aggregate_By
     (Plan       : Logical_Plan;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Aggregate;
      S.Aggregates := Aggregates;
      P.Steps.Append (S);
      return P;
   end Aggregate_By;

   function Group_By
     (Plan       : Logical_Plan;
      Columns    : Column_Vectors.Vector;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Group;
      S.Columns := Columns;
      S.Aggregates := Aggregates;
      P.Steps.Append (S);
      return P;
   end Group_By;

   function Inner_Join
     (Left_Plan    : Logical_Plan;
      Right_Plan   : Logical_Plan;
      Left_Column  : Natural;
      Right_Column : Natural) return Logical_Plan is
      P : Logical_Plan := Left_Plan;
      S : Logical_Step;
   begin
      for R of Right_Plan.Steps loop
         P.Steps.Append (R);
      end loop;
      S.Node_Kind := Join;
      S.Columns.Append (Left_Column);
      S.Columns.Append (Right_Column);
      P.Steps.Append (S);
      return P;
   end Inner_Join;

   function Full_Text
     (Plan       : Logical_Plan;
      Index_Name : Wide_Wide_String;
      Query      : Wide_Wide_String) return Logical_Plan is
      P : Logical_Plan := Plan;
      S : Logical_Step;
   begin
      S.Node_Kind := Full_Text_Search;
      S.Full_Text_Index_Name := To_Unbounded_Wide_Wide_String (Index_Name);
      S.Full_Text_Query := To_Unbounded_Wide_Wide_String (Query);
      P.Steps.Append (S);
      return P;
   end Full_Text;

   function Step_Count (Plan : Logical_Plan) return Natural is
   begin
      return Natural (Plan.Steps.Length);
   end Step_Count;

   function Step (Plan : Logical_Plan; Index : Natural) return Logical_Step is
   begin
      return Plan.Steps.Element (Index);
   end Step;

   function Referenced_Columns (Plan : Logical_Plan) return Column_Vectors.Vector is
      Result : Column_Vectors.Vector;
   begin
      for S of Plan.Steps loop
         case S.Node_Kind is
            when Filter =>
               Append_Predicate_Columns (Result, S.Predicate);
            when Project =>
               for C of S.Columns loop
                  Append_Unique (Result, C);
               end loop;
            when Order =>
               Append_Unique (Result, S.Order_Column);
            when Group =>
               for C of S.Columns loop
                  Append_Unique (Result, C);
               end loop;
               for A of S.Aggregates loop
                  if A.Kind /= Database.Aggregates.Count_All then
                     Append_Unique (Result, A.Column);
                  end if;
               end loop;
            when Aggregate =>
               for A of S.Aggregates loop
                  if A.Kind /= Database.Aggregates.Count_All then
                     Append_Unique (Result, A.Column);
                  end if;
               end loop;
            when Join =>
               for C of S.Columns loop
                  Append_Unique (Result, C);
               end loop;
            when others =>
               null;
         end case;
      end loop;
      return Result;
   end Referenced_Columns;
end Database.Plans;
