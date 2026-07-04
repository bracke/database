with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
use Ada.Strings.Wide_Wide_Unbounded;

package body Database.Execution_Plans is
   use type Ada.Containers.Count_Type;
   function Kind_Image (K : Physical_Node_Kind) return Wide_Wide_String is
   begin
      case K is
         when Heap_Scan              => return "Heap_Scan";
         when Index_Lookup           => return "Index_Lookup";
         when Index_Range_Scan       => return "Index_Range_Scan";
         when Filter_Node            => return "Filter";
         when Projection_Node        => return "Projection";
         when Sort_Node              => return "Sort";
         when Limit_Node             => return "Limit";
         when Aggregate_Node         => return "Aggregate";
         when Hash_Group_Node        => return "Hash_Group";
         when Nested_Loop_Join       => return "Nested_Loop_Join";
         when Index_Nested_Loop_Join => return "Index_Nested_Loop_Join";
         when Materialize_Node       => return "Materialize";
         when Full_Text_Index_Search => return "Full_Text_Index_Search";
         when Full_Text_Ranked_Search => return "Full_Text_Ranked_Search";
      end case;
   end Kind_Image;

   procedure Append (Plan : in out Physical_Plan; Step : Physical_Step) is
   begin
      Plan.Steps.Append (Step);
      Plan.Estimated_Cost := Plan.Estimated_Cost + Step.Estimated_Cost;
      Plan.Estimated_Rows := Step.Estimated_Rows;
   end Append;

   function Contains (Plan : Physical_Plan; Kind : Physical_Node_Kind) return Boolean is
   begin
      for S of Plan.Steps loop
         if S.Node_Kind = Kind then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Step_Count (Plan : Physical_Plan) return Natural is
   begin
      return Natural (Plan.Steps.Length);
   end Step_Count;

   function Step (Plan : Physical_Plan; Index : Natural) return Physical_Step is
   begin
      return Plan.Steps.Element (Index);
   end Step;

   function Explain (Plan : Physical_Plan) return Wide_Wide_String is
      Text : Unbounded_Wide_Wide_String := Null_Unbounded_Wide_Wide_String;
   begin
      if Plan.Steps.Length = 0 then
         return "<empty physical plan>";
      end if;
      for I in 0 .. Natural (Plan.Steps.Length) - 1 loop
         declare
            S : constant Physical_Step := Plan.Steps.Element (I);
         begin
            Append (Text, Kind_Image (S.Node_Kind));
            Append (Text, " rows=");
            Append (Text, Natural'Wide_Wide_Image (S.Estimated_Rows));
            Append (Text, " cost=");
            Append (Text, Long_Float'Wide_Wide_Image (S.Estimated_Cost));
            if Length (S.Details) > 0 then
               Append (Text, " ");
               Append (Text, S.Details);
            end if;
            if I + 1 < Natural (Plan.Steps.Length) then
               Append (Text, Wide_Wide_Character'Val (10));
            end if;
         end;
      end loop;
      return To_Wide_Wide_String (Text);
   end Explain;
end Database.Execution_Plans;
