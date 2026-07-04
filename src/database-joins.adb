with Database.Status;
with Database.Rows;
with Database.Types;
with Database.Values;

package body Database.Joins is
   use type Database.Types.Value_Kind;

   function On_Equal (Left_Column, Right_Column : Natural) return Equality_Predicate is
   begin
      return (Left_Column => Left_Column, Right_Column => Right_Column);
   end On_Equal;

   function Has_Column (Q : Database.Queries.Query; Column : Natural) return Boolean is
      Rows : constant Database.Queries.Row_Vectors.Vector := Database.Queries.Rows (Q);
   begin
      for Row of Rows loop
         if Column >= Database.Rows.Column_Count (Row) then
            return False;
         end if;
      end loop;
      return True;
   end Has_Column;

   function Inner_Join
     (Left         : Database.Queries.Query;
      Right        : Database.Queries.Query;
      Left_Column  : Natural;
      Right_Column : Natural) return Database.Queries.Query is
   begin
      return Inner_Join (Left, Right, On_Equal (Left_Column, Right_Column));
   end Inner_Join;

   function Inner_Join
     (Left  : Database.Queries.Query;
      Right : Database.Queries.Query;
      On    : Equality_Predicate) return Database.Queries.Query is
      Result : Database.Queries.Query;
      Ignored : Database.Status.Result;
   begin
      Ignored := Try_Inner_Join (Left, Right, On, Result);
      pragma Unreferenced (Ignored);
      return Result;
   end Inner_Join;

   function Try_Inner_Join
     (Left   : Database.Queries.Query;
      Right  : Database.Queries.Query;
      On     : Equality_Predicate;
      Result : out Database.Queries.Query) return Database.Status.Result is
      Out_Row : Database.Rows.Row;
      LV, RV : Database.Values.Value;
      LRows : constant Database.Queries.Row_Vectors.Vector := Database.Queries.Rows (Left);
      RRows : constant Database.Queries.Row_Vectors.Vector := Database.Queries.Rows (Right);
   begin
      Result := Database.Queries.Empty;
      if not Has_Column (Left, On.Left_Column) or else not Has_Column (Right, On.Right_Column) then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "join column index is out of range");
      end if;

      for L of LRows loop
         LV := Database.Rows.Get (L, On.Left_Column);
         if LV.Kind /= Database.Types.Null_Value then
            for R of RRows loop
               RV := Database.Rows.Get (R, On.Right_Column);
               if RV.Kind /= Database.Types.Null_Value and then Database.Values.Equal (LV, RV) then
                  Out_Row.Values.Clear;
                  if Database.Rows.Column_Count (L) > 0 then
                     for I in 0 .. Database.Rows.Column_Count (L) - 1 loop
                        Database.Rows.Append (Out_Row, Database.Rows.Get (L, I));
                     end loop;
                  end if;
                  if Database.Rows.Column_Count (R) > 0 then
                     for I in 0 .. Database.Rows.Column_Count (R) - 1 loop
                        Database.Rows.Append (Out_Row, Database.Rows.Get (R, I));
                     end loop;
                  end if;
                  Database.Queries.Append (Result, Out_Row);
               end if;
            end loop;
         end if;
      end loop;
      return Database.Status.Success;
   end Try_Inner_Join;
end Database.Joins;
