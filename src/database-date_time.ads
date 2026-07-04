--  Deterministic database date/time value support.
--  All values use explicit logical fields;
--  Ada.Calendar implementation layouts are never serialized.
package Database.Date_Time is
   --  Date stores the public fields for this database abstraction.
   type Date is record
      Year  : Integer range 1 .. 9999 := 1970;
      Month : Integer range 1 .. 12 := 1;
      Day   : Integer range 1 .. 31 := 1;
   end record;

   --  Time stores the public fields for this database abstraction.
   type Time is record
      Hour       : Integer range 0 .. 23 := 0;
      Minute     : Integer range 0 .. 59 := 0;
      Second     : Integer range 0 .. 59 := 0;
      Nanosecond : Natural range 0 .. 999_999_999 := 0;
   end record;

   --  Date_Time stores the public fields for this database abstraction.
   type Date_Time is record
      Date_Part : Date;
      Time_Part : Time;
   end record;

   --  Time_Span stores the public fields for this database abstraction.
   type Time_Span is record
      Seconds     : Long_Long_Integer := 0;
      Nanoseconds : Natural range 0 .. 999_999_999 := 0;
   end record;

   --  Return is valid for the supplied database state or arguments.
   --  @param D d argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Valid (D : Date) return Boolean;
   --  Return is valid for the supplied database state or arguments.
   --  @param T t argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Valid (T : Time) return Boolean;
   --  Return is valid for the supplied database state or arguments.
   --  @param T t argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Valid (T : Date_Time) return Boolean;
   --  Return is valid for the supplied database state or arguments.
   --  @param D d argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Valid (D : Time_Span) return Boolean;

   --  Return compare for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare (Left, Right : Date) return Integer;
   --  Return compare for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare (Left, Right : Time) return Integer;
   --  Return compare for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare (Left, Right : Date_Time) return Integer;
   --  Return compare for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Compare (Left, Right : Time_Span) return Integer;

   --  Return add for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Add (Left : Date_Time; Right : Time_Span) return Date_Time;
   --  Return difference for the supplied database state or arguments.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Difference (Left, Right : Date_Time) return Time_Span;
end Database.Date_Time;
