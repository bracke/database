package body Database.Date_Time is
   function Leap (Y : Integer) return Boolean is
   begin
      return (Y mod 4 = 0 and then Y mod 100 /= 0) or else (Y mod 400 = 0);
   end Leap;

   function Days_In_Month (Y, M : Integer) return Integer is
   begin
      case M is
         when 1 | 3 | 5 | 7 | 8 | 10 | 12 => return 31;
         when 4 | 6 | 9 | 11 => return 30;
         when 2 => return (if Leap (Y) then 29 else 28);
         when others => return 0;
      end case;
   end Days_In_Month;

   function Is_Valid (D : Date) return Boolean is
   begin
      return D.Day <= Days_In_Month (D.Year, D.Month);
   end Is_Valid;

   function Is_Valid (T : Time) return Boolean is
      pragma Unreferenced (T);
   begin
      return True;
   end Is_Valid;

   function Is_Valid (T : Date_Time) return Boolean is
   begin
      return Is_Valid (T.Date_Part) and then Is_Valid (T.Time_Part);
   end Is_Valid;

   function Is_Valid (D : Time_Span) return Boolean is
      pragma Unreferenced (D);
   begin
      return True;
   end Is_Valid;

   function Compare (Left, Right : Date) return Integer is
   begin
      if Left.Year /= Right.Year then
         return (if Left.Year < Right.Year then
         -1 else 1);
      end if;
      if Left.Month /= Right.Month then
         return (if Left.Month < Right.Month then
         -1 else 1);
      end if;
      if Left.Day /= Right.Day then
         return (if Left.Day < Right.Day then
         -1 else 1);
      end if;
      return 0;
   end Compare;

   function Compare (Left, Right : Time) return Integer is
   begin
      if Left.Hour /= Right.Hour then
         return (if Left.Hour < Right.Hour then
         -1 else 1);
      end if;
      if Left.Minute /= Right.Minute then
         return (if Left.Minute < Right.Minute then
         -1 else 1);
      end if;
      if Left.Second /= Right.Second then
         return (if Left.Second < Right.Second then
         -1 else 1);
      end if;
      if Left.Nanosecond /= Right.Nanosecond then
         return (if Left.Nanosecond < Right.Nanosecond then
         -1 else 1);
      end if;
      return 0;
   end Compare;

   function Compare (Left, Right : Date_Time) return Integer is
      C : constant Integer := Compare (Left.Date_Part, Right.Date_Part);
   begin
      if C /= 0 then
         return C;
      end if;
      return Compare (Left.Time_Part, Right.Time_Part);
   end Compare;

   function Compare (Left, Right : Time_Span) return Integer is
   begin
      if Left.Seconds /= Right.Seconds then
         return (if Left.Seconds < Right.Seconds then
         -1 else 1);
      end if;
      if Left.Nanoseconds /= Right.Nanoseconds then
         return (if Left.Nanoseconds < Right.Nanoseconds then
         -1 else 1);
      end if;
      return 0;
   end Compare;

   function Day_Number (D : Date) return Long_Long_Integer is
      N : Long_Long_Integer := 0;
   begin
      for Y in 1 .. D.Year - 1 loop
         N := N + (if Leap (Y) then 366 else 365);
      end loop;
      for M in 1 .. D.Month - 1 loop
         N := N + Long_Long_Integer (Days_In_Month (D.Year, M));
      end loop;
      return N + Long_Long_Integer (D.Day - 1);
   end Day_Number;

   function From_Day_Number (N : Long_Long_Integer) return Date is
      Rest : Long_Long_Integer := N;
      Y : Integer := 1;
      M : Integer := 1;
      DY : Integer;
      DM : Integer;
   begin
      while Y < 9999 loop
         DY := (if Leap (Y) then 366 else 365);
         exit when Rest < Long_Long_Integer (DY);
         Rest := Rest - Long_Long_Integer (DY);
         Y := Y + 1;
      end loop;
      while M < 12 loop
         DM := Days_In_Month (Y, M);
         exit when Rest < Long_Long_Integer (DM);
         Rest := Rest - Long_Long_Integer (DM);
         M := M + 1;
      end loop;
      return (Year => Y, Month => M, Day => Integer (Rest) + 1);
   end From_Day_Number;

   function To_Nanos (T : Time) return Long_Long_Integer is
   begin
      return (((Long_Long_Integer (T.Hour) * 60 + Long_Long_Integer (T.Minute)) * 60
        + Long_Long_Integer (T.Second)) * 1_000_000_000) + Long_Long_Integer (T.Nanosecond);
   end To_Nanos;

   function Add (Left : Date_Time; Right : Time_Span) return Date_Time is
      Day_Nanos : constant Long_Long_Integer := 86_400_000_000_000;
      Total : Long_Long_Integer := To_Nanos (Left.Time_Part) + Right.Seconds * 1_000_000_000
        + Long_Long_Integer (Right.Nanoseconds);
      Days : Long_Long_Integer := Day_Number (Left.Date_Part);
   begin
      while Total < 0 loop
         Total := Total + Day_Nanos;
         Days := Days - 1;
      end loop;
      while Total >= Day_Nanos loop
         Total := Total - Day_Nanos;
         Days := Days + 1;
      end loop;
      return (Date_Part => From_Day_Number (Days),
              Time_Part => (Hour => Integer (Total / 3_600_000_000_000),
                            Minute => Integer ((Total / 60_000_000_000) mod 60),
                            Second => Integer ((Total / 1_000_000_000) mod 60),
                            Nanosecond => Natural (Total mod 1_000_000_000)));
   end Add;

   function Difference (Left, Right : Date_Time) return Time_Span is
      N : Long_Long_Integer := (Day_Number (Left.Date_Part) - Day_Number (Right.Date_Part)) * 86_400_000_000_000
        + To_Nanos (Left.Time_Part) - To_Nanos (Right.Time_Part);
      S : Long_Long_Integer := N / 1_000_000_000;
      R : Long_Long_Integer := N mod 1_000_000_000;
   begin
      if R < 0 then
         S := S - 1;
         R := R + 1_000_000_000;
      end if;
      return (Seconds => S, Nanoseconds => Natural (R));
   end Difference;
end Database.Date_Time;
