package body Database.Full_Text.Queries is
   function Make (K : Query_Kind) return Query is
   begin
      return  (Node => new Query_Node'(K => K,
        Value => Null_Unbounded_Wide_Wide_String,
        Values => Term_Vectors.Empty_Vector,
        L => (Node => null),
        R => (Node => null),
        Distance_Value => 0));
   end Make;

   function Match_Everything return Query is (Make (Match_All));
   function Term (Text : Wide_Wide_String) return Query is
      Q : Query := Make (Term_Query);
   begin Q.Node.Value := To_Unbounded_Wide_Wide_String (Text);
   return Q;
   end Term;
   function Prefix (Text : Wide_Wide_String) return Query is
      Q : Query := Make (Prefix_Query);
   begin Q.Node.Value := To_Unbounded_Wide_Wide_String (Text);
   return Q;
   end Prefix;
   function Phrase (Terms : Term_Vectors.Vector) return Query is
      Q : Query := Make (Phrase_Query);
   begin Q.Node.Values := Terms;
   return Q;
   end Phrase;
   function Phrase (A, B : Wide_Wide_String) return Query is
      V : Term_Vectors.Vector;
   begin V.Append (To_Unbounded_Wide_Wide_String (A));
   V.Append (To_Unbounded_Wide_Wide_String (B));
   return Phrase (V);
   end Phrase;
   function Near
     (Left, Right : Wide_Wide_String;
      Max_Distance : Positive := 5) return Query is
      Q : Query := Make (Near_Query);
   begin
      Q.Node.L := Term (Left);
      Q.Node.R := Term (Right);
      Q.Node.Distance_Value := Max_Distance;
      return Q;
   end Near;

   function Fuzzy
     (Text : Wide_Wide_String;
      Max_Edit_Distance : Natural := 1) return Query is
      Q : Query := Make (Fuzzy_Query);
   begin
      Q.Node.Value := To_Unbounded_Wide_Wide_String (Text);
      Q.Node.Distance_Value := Max_Edit_Distance;
      return Q;
   end Fuzzy;

   function And_Query_Node (Left, Right : Query) return Query is
      Q : Query := Make (And_Query);
   begin Q.Node.L := Left;
   Q.Node.R := Right;
   return Q;
   end And_Query_Node;
   function Or_Query_Node (Left, Right : Query) return Query is
      Q : Query := Make (Or_Query);
   begin Q.Node.L := Left;
   Q.Node.R := Right;
   return Q;
   end Or_Query_Node;
   function Not_Query_Node (Child : Query) return Query is
      Q : Query := Make (Not_Query);
   begin Q.Node.L := Child;
   return Q;
   end Not_Query_Node;

   function Kind (Q : Query) return Query_Kind is
   begin
      if Q.Node = null then
         return Match_All;
      else
         return Q.Node.K;
      end if;
   end Kind;
   function Text (Q : Query) return Wide_Wide_String is
   begin
      if Q.Node = null then
         return "";
      else
         return To_Wide_Wide_String (Q.Node.Value);
      end if;
   end Text;
   function Terms (Q : Query) return Term_Vectors.Vector is
   begin
      if Q.Node = null then
         return Term_Vectors.Empty_Vector;
      else
         return Q.Node.Values;
      end if;
   end Terms;
   function Left (Q : Query) return Query is
   begin
      if Q.Node = null then
         return Match_Everything;
      else
         return Q.Node.L;
      end if;
   end Left;
   function Right (Q : Query) return Query is
   begin
      if Q.Node = null then
         return Match_Everything;
      else
         return Q.Node.R;
      end if;
   end Right;
   function Child (Q : Query) return Query is (Left (Q));
   function Distance (Q : Query) return Natural is
   begin
      if Q.Node = null then
         return 0;
      else
         return Q.Node.Distance_Value;
      end if;
   end Distance;
end Database.Full_Text.Queries;
