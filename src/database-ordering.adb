with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Types;
with Database.Date_Time;
with Database.UUIDs;

package body Database.Ordering is
   use type Database.Types.Value_Kind;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;

   function Decimal_Compare (L, R : Database.Types.Decimal) return Integer is
      LC : Long_Long_Integer := L.Coefficient;
      RC : Long_Long_Integer := R.Coefficient;
   begin
      if L.Scale < R.Scale then
         for I in 1 .. R.Scale - L.Scale loop
            LC := LC * 10;
         end loop;
      elsif R.Scale < L.Scale then
         for I in 1 .. L.Scale - R.Scale loop
            RC := RC * 10;
         end loop;
      end if;
      if LC < RC then
         return -1;
      elsif LC > RC then
         return 1;
         else
            return 0;
      end if;
   end Decimal_Compare;

   function Timestamp_Compare (L, R : Database.Types.Timestamp) return Integer is
   begin
      if L.Year /= R.Year then
         return (if L.Year < R.Year then
         -1 else 1);
      end if;
      if L.Month /= R.Month then
         return (if L.Month < R.Month then
         -1 else 1);
      end if;
      if L.Day /= R.Day then
         return (if L.Day < R.Day then
         -1 else 1);
      end if;
      if L.Hour /= R.Hour then
         return (if L.Hour < R.Hour then
         -1 else 1);
      end if;
      if L.Minute /= R.Minute then
         return (if L.Minute < R.Minute then
         -1 else 1);
      end if;
      if L.Second /= R.Second then
         return (if L.Second < R.Second then
         -1 else 1);
      end if;
      if L.Nanosecond /= R.Nanosecond then
         return (if L.Nanosecond < R.Nanosecond then
         -1 else 1);
      end if;
      return 0;
   end Timestamp_Compare;

   function Base_Compare (Left, Right : Database.Values.Value) return Integer is
   begin
      if Left.Kind = Database.Types.Null_Value and then Right.Kind = Database.Types.Null_Value then
         return 0;
      elsif Left.Kind = Database.Types.Null_Value then
         return 1;
      elsif Right.Kind = Database.Types.Null_Value then
         return -1;
      elsif Left.Kind /= Right.Kind then
         return Database.Types.Value_Kind'Pos (Left.Kind) - Database.Types.Value_Kind'Pos (Right.Kind);
      end if;

      case Left.Kind is
         when Database.Types.Null_Value => return 0;
         when Database.Types.Boolean_Value =>
            if Left.Bool = Right.Bool then
               return 0;
            elsif not Left.Bool and then Right.Bool then
               return -1;
               else
                  return 1;
            end if;
         when Database.Types.Integer_Value =>
            if Left.Int < Right.Int then
               return -1;
            elsif Left.Int > Right.Int then
               return 1;
               else
                  return 0;
            end if;
         when Database.Types.Long_Integer_Value =>
            if Left.Long_Int < Right.Long_Int then
               return -1;
            elsif Left.Long_Int > Right.Long_Int then
               return 1;
               else
                  return 0;
            end if;
         when Database.Types.Float_Value =>
            if Left.Flt < Right.Flt then
               return -1;
            elsif Left.Flt > Right.Flt then
               return 1;
               else
                  return 0;
            end if;
         when Database.Types.Decimal_Value =>
            return Decimal_Compare (Left.Dec, Right.Dec);
         when Database.Types.Text_Value =>
            if To_Wide_Wide_String (Left.Text) < To_Wide_Wide_String (Right.Text) then
               return -1;
            elsif To_Wide_Wide_String (Left.Text) > To_Wide_Wide_String (Right.Text) then
               return 1;
               else
                  return 0;
               end if;
         when Database.Types.Blob_Value =>
            if Left.Blob.Length < Right.Blob.Length then
               return -1;
            elsif Left.Blob.Length > Right.Blob.Length then
               return 1;
               else
                  return 0;
            end if;
         when Database.Types.Timestamp_Value =>
            return Timestamp_Compare (Left.Time, Right.Time);
         when Database.Types.Enum_Value =>
            if To_Wide_Wide_String (Left.Enum_Text) < To_Wide_Wide_String (Right.Enum_Text) then
               return -1;
            elsif To_Wide_Wide_String (Left.Enum_Text) > To_Wide_Wide_String (Right.Enum_Text) then
               return 1;
               else
                  return 0;
               end if;
         when Database.Types.Date_Value => return Database.Date_Time.Compare (Left.Date, Right.Date);
         when Database.Types.Time_Value => return Database.Date_Time.Compare (Left.Clock_Time, Right.Clock_Time);
         when Database.Types.Date_Time_Value => return Database.Date_Time.Compare (Left.Date_Time, Right.Date_Time);
         when Database.Types.Duration_Value => return Database.Date_Time.Compare (Left.Time_Span, Right.Time_Span);
         when Database.Types.UUID_Value => return Database.UUIDs.Compare (Left.UUID, Right.UUID);
         when Database.Types.Array_Value =>
            if To_Wide_Wide_String (Left.Array_Text) < To_Wide_Wide_String (Right.Array_Text) then
               return -1;
            elsif To_Wide_Wide_String (Left.Array_Text) > To_Wide_Wide_String (Right.Array_Text) then
               return 1;
               else
                  return 0;
               end if;
      end case;
   end Base_Compare;

   function Compare (Left, Right : Database.Values.Value) return Integer is
   begin
      return Base_Compare (Left, Right);
   end Compare;

   function Less
     (Left, Right : Database.Values.Value;
      Dir         : Direction := Ascending) return Boolean is
      C : constant Integer := Base_Compare (Left, Right);
   begin
      if Dir = Ascending then
         return C < 0;
      else
         if Left.Kind = Database.Types.Null_Value or else Right.Kind = Database.Types.Null_Value then
            return C < 0;
         end if;
         return C > 0;
      end if;
   end Less;
end Database.Ordering;
