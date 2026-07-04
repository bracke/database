with Ada.Strings.Wide_Wide_Unbounded;
with Database.Date_Time;
with Database.UUIDs;
package body Database.Values is
   use type Database.Types.Decimal;
   use type Database.Types.Timestamp;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Database.Types.Value_Kind;
   use type Byte_Vectors.Vector;

   function Null_Value return Value is
   begin
      return (Kind => Database.Types.Null_Value);
   end Null_Value;
   function From_Boolean (B : Boolean) return Value is
   begin
      return (Kind => Database.Types.Boolean_Value, Bool => B);
   end From_Boolean;
   function From_Integer (I : Integer) return Value is
   begin
      return (Kind => Database.Types.Integer_Value, Int => I);
   end From_Integer;
   function From_Long_Integer (I : Long_Long_Integer) return Value is
   begin
      return (Kind => Database.Types.Long_Integer_Value, Long_Int => I);
   end From_Long_Integer;
   function From_Float (F : Long_Float) return Value is
   begin
      return (Kind => Database.Types.Float_Value, Flt => F);
   end From_Float;
   function From_Decimal (D : Database.Types.Decimal) return Value is
   begin
      return (Kind => Database.Types.Decimal_Value, Dec => D);
   end From_Decimal;
   function From_Text (S : Wide_Wide_String) return Value is
   begin
      return (Kind => Database.Types.Text_Value, Text => To_Unbounded_Wide_Wide_String (S));
   end From_Text;
   function From_Blob (B : Byte_Vectors.Vector) return Value is
   begin
      return (Kind => Database.Types.Blob_Value, Blob => B);
   end From_Blob;
   function From_Timestamp (T : Database.Types.Timestamp) return Value is
   begin
      return (Kind => Database.Types.Timestamp_Value, Time => T);
   end From_Timestamp;
   function From_Enum (S : Wide_Wide_String) return Value is
   begin
      return (Kind => Database.Types.Enum_Value, Enum_Text => To_Unbounded_Wide_Wide_String (S));
   end From_Enum;
   function From_Date (D : Database.Date_Time.Date) return Value is
   begin
      return (Kind => Database.Types.Date_Value, Date => D);
   end From_Date;
   function From_Time (T : Database.Date_Time.Time) return Value is
   begin
      return (Kind => Database.Types.Time_Value, Clock_Time => T);
   end From_Time;
   function From_Date_Time (T : Database.Date_Time.Date_Time) return Value is
   begin
      return (Kind => Database.Types.Date_Time_Value, Date_Time => T);
   end From_Date_Time;
   function From_Duration (D : Database.Date_Time.Time_Span) return Value is
   begin
      return (Kind => Database.Types.Duration_Value, Time_Span => D);
   end From_Duration;
   function From_UUID (U : Database.UUIDs.UUID) return Value is
   begin
      return (Kind => Database.Types.UUID_Value, UUID => U);
   end From_UUID;
   function From_Array_Text (S : Wide_Wide_String) return Value is
   begin
      return (Kind => Database.Types.Array_Value, Array_Text => To_Unbounded_Wide_Wide_String (S));
   end From_Array_Text;

   function Equal (Left, Right : Value) return Boolean is
   begin
      if Left.Kind /= Right.Kind then
         return False;
      end if;
      case Left.Kind is
         when Database.Types.Null_Value => return True;
         when Database.Types.Boolean_Value => return Left.Bool = Right.Bool;
         when Database.Types.Integer_Value => return Left.Int = Right.Int;
         when Database.Types.Long_Integer_Value => return Left.Long_Int = Right.Long_Int;
         when Database.Types.Float_Value => return Left.Flt = Right.Flt;
         when Database.Types.Decimal_Value => return Left.Dec = Right.Dec;
         when Database.Types.Text_Value => return To_Wide_Wide_String (Left.Text) = To_Wide_Wide_String (Right.Text);
         when Database.Types.Blob_Value => return Left.Blob = Right.Blob;
         when Database.Types.Timestamp_Value => return Left.Time = Right.Time;
         when Database.Types.Enum_Value =>
           return To_Wide_Wide_String (Left.Enum_Text) = To_Wide_Wide_String (Right.Enum_Text);
         when Database.Types.Date_Value => return Database.Date_Time.Compare (Left.Date, Right.Date) = 0;
         when Database.Types.Time_Value => return Database.Date_Time.Compare (Left.Clock_Time, Right.Clock_Time) = 0;
         when Database.Types.Date_Time_Value => return Database.Date_Time.Compare (Left.Date_Time, Right.Date_Time) = 0;
         when Database.Types.Duration_Value => return Database.Date_Time.Compare (Left.Time_Span, Right.Time_Span) = 0;
         when Database.Types.UUID_Value => return Database.UUIDs.Compare (Left.UUID, Right.UUID) = 0;
         when Database.Types.Array_Value =>
           return To_Wide_Wide_String (Left.Array_Text) = To_Wide_Wide_String (Right.Array_Text);
      end case;
   end Equal;
end Database.Values;
