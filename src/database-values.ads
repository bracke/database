--  Runtime database values. Text is Unicode and rows are serialized value-by-value.
with Ada.Containers.Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Date_Time;
with Database.Types;
with Database.UUIDs;

--  Typed value representation used by rows, predicates, queries, and storage.
package Database.Values is
   use Ada.Strings.Wide_Wide_Unbounded;
   --  Byte defines a public database type used by this package.
   subtype Byte is Natural range 0 .. 255;
   --  Byte_Vectors stores ordered byte values for this package.
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Byte);

   --  Value stores the public fields for this database abstraction.
   type Value (Kind : Database.Types.Value_Kind := Database.Types.Null_Value) is record
      case Kind is
         when Database.Types.Null_Value =>
            null;
         when Database.Types.Boolean_Value =>
            Bool : Boolean := False;
         when Database.Types.Integer_Value =>
            Int : Integer := 0;
         when Database.Types.Long_Integer_Value =>
            Long_Int : Long_Long_Integer := 0;
         when Database.Types.Float_Value =>
            Flt : Long_Float := 0.0;
         when Database.Types.Decimal_Value =>
            Dec : Database.Types.Decimal;
         when Database.Types.Text_Value =>
            Text : Unbounded_Wide_Wide_String;
         when Database.Types.Blob_Value =>
            Blob : Byte_Vectors.Vector;
         when Database.Types.Timestamp_Value =>
            Time : Database.Types.Timestamp;
         when Database.Types.Enum_Value =>
            Enum_Text : Unbounded_Wide_Wide_String;
         when Database.Types.Date_Value =>
            Date : Database.Date_Time.Date;
         when Database.Types.Time_Value =>
            Clock_Time : Database.Date_Time.Time;
         when Database.Types.Date_Time_Value =>
            Date_Time : Database.Date_Time.Date_Time;
         when Database.Types.Duration_Value =>
            Time_Span : Database.Date_Time.Time_Span;
         when Database.Types.UUID_Value =>
            UUID : Database.UUIDs.UUID;
         when Database.Types.Array_Value =>
            Array_Text : Unbounded_Wide_Wide_String;
      end case;
   end record;

   --  Value_Vectors stores ordered value values for this package.
   package Value_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Value);
   --  Value_Vector defines a public database type used by this package.
   subtype Value_Vector is Value_Vectors.Vector;

   --  Return null value for the supplied database state or arguments.
   --  @return Requested value or optional value according to the package contract.
   function Null_Value return Value;
   --  Return from boolean for the supplied database state or arguments.
   --  @param B b argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Boolean (B : Boolean) return Value;
   --  Return from integer for the supplied database state or arguments.
   --  @param I i argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Integer (I : Integer) return Value;
   --  Return from long integer for the supplied database state or arguments.
   --  @param I i argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Long_Integer (I : Long_Long_Integer) return Value;
   --  Return from float for the supplied database state or arguments.
   --  @param F f argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Float (F : Long_Float) return Value;
   --  Return from decimal for the supplied database state or arguments.
   --  @param D d argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Decimal (D : Database.Types.Decimal) return Value;
   --  Return from text for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Text (S : Wide_Wide_String) return Value;
   --  Return from blob for the supplied database state or arguments.
   --  @param B b argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Blob (B : Byte_Vectors.Vector) return Value;
   --  Return from timestamp for the supplied database state or arguments.
   --  @param T t argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Timestamp (T : Database.Types.Timestamp) return Value;
   --  Return from enum for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Enum (S : Wide_Wide_String) return Value;
   --  Return from date for the supplied database state or arguments.
   --  @param D d argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Date (D : Database.Date_Time.Date) return Value;
   --  Return from time for the supplied database state or arguments.
   --  @param T t argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Time (T : Database.Date_Time.Time) return Value;
   --  Return from date time for the supplied database state or arguments.
   --  @param T t argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Date_Time (T : Database.Date_Time.Date_Time) return Value;
   --  Return from duration for the supplied database state or arguments.
   --  @param D d argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Duration (D : Database.Date_Time.Time_Span) return Value;
   --  Return from uuid for the supplied database state or arguments.
   --  @param U u argument supplied to the operation.
   --  @return Result produced by the function.
   function From_UUID (U : Database.UUIDs.UUID) return Value;
   --  Return from array text for the supplied database state or arguments.
   --  @param S s argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Array_Text (S : Wide_Wide_String) return Value;
   --  Return equal for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Equal (Left, Right : Value) return Boolean;
end Database.Values;
