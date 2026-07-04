with Database.Indexes;
with Database.Status;
package body Database.Predicates is
   use type Database.Indexes.Ordering;
   function True_Predicate return Predicate is
   begin
      return (Kind => Always_True, others => <>);
   end True_Predicate;

   function Column_Equals (Index : Natural; Value : Database.Values.Value) return Predicate is
   begin
      return (Kind => Equals, Index => Index, Value => Value, others => <>);
   end Column_Equals;

   function Column_Not_Equals (Index : Natural; Value : Database.Values.Value) return Predicate is
   begin
      return (Kind => Not_Equals, Index => Index, Value => Value, others => <>);
   end Column_Not_Equals;

   function Column_Less_Than (Index : Natural; Value : Database.Values.Value) return Predicate is
   begin
      return (Kind => Less_Than, Index => Index, Value => Value, others => <>);
   end Column_Less_Than;

   function Column_Less_Or_Equal (Index : Natural; Value : Database.Values.Value) return Predicate is
   begin
      return (Kind => Less_Or_Equal, Index => Index, Value => Value, others => <>);
   end Column_Less_Or_Equal;

   function Column_Greater_Than (Index : Natural; Value : Database.Values.Value) return Predicate is
   begin
      return (Kind => Greater_Than, Index => Index, Value => Value, others => <>);
   end Column_Greater_Than;

   function Column_Greater_Or_Equal (Index : Natural; Value : Database.Values.Value) return Predicate is
   begin
      return (Kind => Greater_Or_Equal, Index => Index, Value => Value, others => <>);
   end Column_Greater_Or_Equal;

   function "and" (L, R : Predicate) return Predicate is
   begin
      return (Kind => And_Predicate, Left => new Predicate'(L), Right => new Predicate'(R), others => <>);
   end "and";

   function "or" (L, R : Predicate) return Predicate is
   begin
      return (Kind => Or_Predicate, Left => new Predicate'(L), Right => new Predicate'(R), others => <>);
   end "or";

   function Matches (P : Predicate; Row : Database.Rows.Row) return Boolean is
   begin
      case P.Kind is
         when Always_True => return True;
         when Equals =>
            return P.Index < Database.Rows.Column_Count (Row) and then
              Database.Values.Equal (Database.Rows.Get (Row, P.Index), P.Value);
         when Not_Equals =>
            return P.Index < Database.Rows.Column_Count (Row) and then
              not Database.Values.Equal (Database.Rows.Get (Row, P.Index), P.Value);
         when Less_Than | Less_Or_Equal | Greater_Than | Greater_Or_Equal =>
            if P.Index >= Database.Rows.Column_Count (Row) then
               return False;
            end if;
            declare
               Order : Database.Indexes.Ordering;
               R : constant Database.Status.Result := Database.Indexes.Compare  (Database.Rows.Get (Row,
                 P.Index),
                 P.Value,
                 Order);
            begin
               if not Database.Status.Is_Ok (R) then
                  return False;
               end if;
               case P.Kind is
                  when Less_Than => return Order = Database.Indexes.Less;
                  when Less_Or_Equal => return Order in Database.Indexes.Less | Database.Indexes.Equal;
                  when Greater_Than => return Order = Database.Indexes.Greater;
                  when Greater_Or_Equal => return Order in Database.Indexes.Greater | Database.Indexes.Equal;
                  when others => return False;
               end case;
            end;
         when And_Predicate =>
            return P.Left /= null and then
              P.Right /= null and then
              Matches (P.Left.all, Row) and then
              Matches (P.Right.all, Row);
         when Or_Predicate =>
            return P.Left /= null and then
              P.Right /= null and then
              (Matches (P.Left.all, Row) or else Matches (P.Right.all, Row));
      end case;
   end Matches;

   function Kind (P : Predicate) return Predicate_Kind is
   begin
      return P.Kind;
   end Kind;

   function Is_Column_Comparison (P : Predicate) return Boolean is
   begin
      return P.Kind in Equals | Not_Equals | Less_Than | Less_Or_Equal | Greater_Than | Greater_Or_Equal;
   end Is_Column_Comparison;

   function Column_Index (P : Predicate) return Natural is
   begin
      return P.Index;
   end Column_Index;

   function Literal_Value (P : Predicate) return Database.Values.Value is
   begin
      return P.Value;
   end Literal_Value;

   function Left (P : Predicate) return Predicate is
   begin
      if P.Left = null then
         return True_Predicate;
      end if;
      return P.Left.all;
   end Left;

   function Right (P : Predicate) return Predicate is
   begin
      if P.Right = null then
         return True_Predicate;
      end if;
      return P.Right.all;
   end Right;
end Database.Predicates;
