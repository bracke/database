with Ada.Strings.Wide_Wide_Unbounded;
with Database.Date_Time;
with Database.Status;
with Database.Type_Metadata;
with Database.Types;
with Database.Values;

package body Database.Constraints is
   use Ada.Strings.Wide_Wide_Unbounded;

   function Digit_Count (V : Long_Long_Integer) return Natural is
      N : Long_Long_Integer := (if V < 0 then -V else V);
      C : Natural := 1;
   begin
      while N >= 10 loop
         N := N / 10;
         C := C + 1;
      end loop;
      return C;
   end Digit_Count;

   function Validate_Row
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Database.Status.Result is
      use type Database.Types.Value_Kind;
      R : Database.Status.Result;
   begin
      if Database.Rows.Column_Count (Row) /= Database.Schema.Column_Count (Schema) then
         return Database.Status.Failure (Database.Status.Schema_Mismatch, "wrong column count");
      end if;

      if Database.Schema.Column_Count (Schema) > 0 then
         for I in 0 .. Database.Schema.Column_Count (Schema) - 1 loop
            declare
               Col : constant Database.Schema.Column := Schema.Columns.Element (I);
               Val : constant Database.Values.Value := Database.Rows.Get (Row, I);
            begin
               R := Database.Type_Metadata.Validate_Type (Col.Type_Info);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               if Val.Kind = Database.Types.Null_Value then
                  if not Col.Nullable then
                     return Database.Status.Failure (Database.Status.Constraint_Error, "null in non-null column");
                  end if;
               elsif Val.Kind /= Col.Kind then
                  return Database.Status.Failure (Database.Status.Schema_Mismatch, "column type mismatch");
               else
                  case Val.Kind is
                     when Database.Types.Date_Value =>
                        if not Database.Date_Time.Is_Valid (Val.Date) then
                           return Database.Status.Failure (Database.Status.Invalid_Date, "invalid date value");
                        end if;
                     when Database.Types.Time_Value =>
                        if not Database.Date_Time.Is_Valid (Val.Clock_Time) then
                           return Database.Status.Failure (Database.Status.Invalid_Time, "invalid time value");
                        end if;
                     when Database.Types.Date_Time_Value =>
                        if not Database.Date_Time.Is_Valid (Val.Date_Time) then
                           return Database.Status.Failure (Database.Status.Invalid_Date, "invalid date_time value");
                        end if;
                     when Database.Types.Duration_Value =>
                        if not Database.Date_Time.Is_Valid (Val.Time_Span) then
                           return Database.Status.Failure (Database.Status.Invalid_Time, "invalid duration value");
                        end if;
                     when Database.Types.Decimal_Value =>
                        if Col.Type_Info.Precision > 0
                          and then Digit_Count (Val.Dec.Coefficient) > Col.Type_Info.Precision
                        then
                           return Database.Status.Failure (Database.Status.Decimal_Overflow,
                             "decimal precision exceeded");
                        end if;
                        if Col.Type_Info.Scale > 0 and then Val.Dec.Scale /= Col.Type_Info.Scale then
                           return Database.Status.Failure (Database.Status.Decimal_Overflow, "decimal scale mismatch");
                        end if;
                     when Database.Types.Text_Value =>
                        if Col.Type_Info.Maximum_Length > 0
                          and then Length (Val.Text) > Col.Type_Info.Maximum_Length
                        then
                           return Database.Status.Failure (Database.Status.Bounded_Text_Overflow,
                             "bounded text maximum length exceeded");
                        end if;
                     when others => null;
                  end case;
               end if;
            end;
         end loop;
      end if;
      return Database.Status.Success;
   end Validate_Row;
end Database.Constraints;
