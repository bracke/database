--  Strongly typed full-text query objects. No SQL-like query parser is required.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;

--  Public specification for this database subsystem.
package Database.Full_Text.Queries is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Query_Kind defines a public database type used by this package.
   type Query_Kind is
     (Match_All,
      Term_Query,
      And_Query,
      Or_Query,
      Not_Query,
      Phrase_Query,
      Prefix_Query,
      Near_Query,
      Fuzzy_Query);
   --  Query defines a public database type used by this package.
   type Query is private;

   --  Term_Vectors stores ordered term values for this package.
   package Term_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Unbounded_Wide_Wide_String);

   --  Return match everything for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Match_Everything return Query;
   --  Return term for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @return Result produced by the function.
   function Term (Text : Wide_Wide_String) return Query;
   --  Return prefix for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @return Result produced by the function.
   function Prefix (Text : Wide_Wide_String) return Query;
   --  Return phrase for the supplied database state or arguments.
   --  @param Terms terms argument supplied to the operation.
   --  @return Result produced by the function.
   function Phrase (Terms : Term_Vectors.Vector) return Query;
   --  Return phrase for the supplied database state or arguments.
   --  @param A a argument supplied to the operation.
   --  @param B b argument supplied to the operation.
   --  @return Result produced by the function.
   function Phrase (A, B : Wide_Wide_String) return Query;
   --  Return near for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Max_Distance max distance argument supplied to the operation.
   --  @return Result produced by the function.
   function Near
     (Left, Right : Wide_Wide_String;
      Max_Distance : Positive := 5) return Query;
   --  Return fuzzy for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @param Max_Edit_Distance max edit distance argument supplied to the operation.
   --  @return Result produced by the function.
   function Fuzzy
     (Text : Wide_Wide_String;
      Max_Edit_Distance : Natural := 1) return Query;
   --  Return and  for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function And_Query_Node (Left, Right : Query) return Query;
   --  Return or  for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Or_Query_Node (Left, Right : Query) return Query;
   --  Return not  for the supplied database state or arguments.
   --  @param Child child argument supplied to the operation.
   --  @return Result produced by the function.
   function Not_Query_Node (Child : Query) return Query;

   --  Return kind for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Kind (Q : Query) return Query_Kind;
   --  Return text for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Text (Q : Query) return Wide_Wide_String;
   --  Return terms for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Terms (Q : Query) return Term_Vectors.Vector;
   --  Return left for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Left (Q : Query) return Query;
   --  Return right for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Right (Q : Query) return Query;
   --  Return child for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Child (Q : Query) return Query;
   --  Return distance for the supplied database state or arguments.
   --  @param Q q argument supplied to the operation.
   --  @return Result produced by the function.
   function Distance (Q : Query) return Natural;

private
   --  Query_Node defines a public database type used by this package.
   type Query_Node;
   --  Query_Access defines a public database type used by this package.
   type Query_Access is access Query_Node;
   --  Query stores the public fields for this database abstraction.
   type Query is record
      Node : Query_Access := null;
   end record;
   --  Query_Node stores the public fields for this database abstraction.
   type Query_Node is record
      K : Query_Kind := Match_All;
      Value : Unbounded_Wide_Wide_String;
      Values : Term_Vectors.Vector;
      L : Query;
      R : Query;
      Distance_Value : Natural := 0;
   end record;
end Database.Full_Text.Queries;
