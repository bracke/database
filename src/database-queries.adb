with Database.Aggregates;
with Database.Ordering;
with Database.Predicates;
with Database.Status;
with Database.Rows;
with Ada.Containers;
with Database.Types;
with Database.Values;
with Database.Full_Text;
with Database.Full_Text.Queries;
with Database.Catalog;
with Database.Foreign_Keys;
with Database.Schema;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Metrics;
with Database.Tracing;
with Database.UUIDs;

package body Database.Queries is
   use type Database.Aggregates.Aggregate_Kind;
   use type Database.Types.Value_Kind;
   use type Ada.Containers.Count_Type;

   function Empty return Query is
      Q : Query;
   begin
      return Q;
   end Empty;

   function From_Rows (Rows : Row_Vectors.Vector) return Query is
   begin
      return (Data => Rows, Use_Optimizer => True);
   end From_Rows;

   procedure Append (Q : in out Query; Row : Database.Rows.Row) is
   begin
      Q.Data.Append (Row);
   end Append;

   function Filter (Q : Query; P : Database.Predicates.Predicate) return Query is
      R : Query;
   begin
      R.Use_Optimizer := Q.Use_Optimizer;
      for Row of Q.Data loop
         if Database.Predicates.Matches (P, Row) then
            R.Data.Append (Row);
         end if;
      end loop;
      return R;
   end Filter;

   function Validate_Columns (Q : Query; Columns : Column_Vectors.Vector) return Database.Status.Result is
   begin
      for Row of Q.Data loop
         for Col of Columns loop
            if Col >= Database.Rows.Column_Count (Row) then
               return Database.Status.Failure (Database.Status.Invalid_Argument, "query column index is out of range");
            end if;
         end loop;
      end loop;
      return Database.Status.Success;
   end Validate_Columns;

   function Project (Q : Query; Columns : Column_Vectors.Vector) return Query is
      R : Query;
      Ignored : Database.Status.Result;
   begin
      Ignored := Try_Project (Q, Columns, R);
      pragma Unreferenced (Ignored);
      return R;
   end Project;

   function Try_Project
     (Q       : Query;
      Columns : Column_Vectors.Vector;
      Result  : out Query) return Database.Status.Result is
      Out_Row : Database.Rows.Row;
      S : Database.Status.Result;
   begin
      Result := Empty;
      Result.Use_Optimizer := Q.Use_Optimizer;
      S := Validate_Columns (Q, Columns);
      if not Database.Status.Is_Ok (S) then
         return S;
      end if;
      for Row of Q.Data loop
         Out_Row.Values.Clear;
         for Col of Columns loop
            Database.Rows.Append (Out_Row, Database.Rows.Get (Row, Col));
         end loop;
         Result.Data.Append (Out_Row);
      end loop;
      return Database.Status.Success;
   end Try_Project;

   function Order_By
     (Q      : Query;
      Column : Natural;
      Dir    : Database.Ordering.Direction := Database.Ordering.Ascending) return Query is
      R : Query;
      Ignored : Database.Status.Result;
   begin
      Ignored := Try_Order_By (Q, Column, R, Dir);
      pragma Unreferenced (Ignored);
      return R;
   end Order_By;

   function Try_Order_By
     (Q      : Query;
      Column : Natural;
      Result : out Query;
      Dir    : Database.Ordering.Direction := Database.Ordering.Ascending) return Database.Status.Result is
      N : constant Natural := Natural (Q.Data.Length);
      Key_Row : Database.Rows.Row;
      J : Natural;
   begin
      Result := Q;
      for Row of Result.Data loop
         if Column >= Database.Rows.Column_Count (Row) then
            Result := Empty;
            return Database.Status.Failure (Database.Status.Invalid_Argument, "order column index is out of range");
         end if;
      end loop;
      if N < 2 then
         return Database.Status.Success;
      end if;

      --  Stable insertion sort. Equal keys are never moved ahead of each other.
      for I in 1 .. N - 1 loop
         Key_Row := Result.Data.Element (I);
         J := I;
         while J > 0 loop
            declare
               Prev : constant Database.Rows.Row := Result.Data.Element (J - 1);
               Key_Value : constant Database.Values.Value := Database.Rows.Get (Key_Row, Column);
               Prev_Value : constant Database.Values.Value := Database.Rows.Get (Prev, Column);
            begin
               exit when not Database.Ordering.Less (Key_Value, Prev_Value, Dir);
               Result.Data.Replace_Element (J, Prev);
               J := J - 1;
            end;
         end loop;
         Result.Data.Replace_Element (J, Key_Row);
      end loop;
      return Database.Status.Success;
   end Try_Order_By;

   function Limit (Q : Query; Count : Natural) return Query is
      R : Query := Empty;
      N : constant Natural := Natural'Min (Count, Natural (Q.Data.Length));
   begin
      R.Use_Optimizer := Q.Use_Optimizer;
      if N = 0 then
         return R;
      end if;
      for I in 0 .. N - 1 loop
         R.Data.Append (Q.Data.Element (I));
      end loop;
      return R;
   end Limit;

   function Offset (Q : Query; Count : Natural) return Query is
      R : Query := Empty;
      N : constant Natural := Natural (Q.Data.Length);
   begin
      R.Use_Optimizer := Q.Use_Optimizer;
      if Count >= N then
         return R;
      end if;
      for I in Count .. N - 1 loop
         R.Data.Append (Q.Data.Element (I));
      end loop;
      return R;
   end Offset;

   function Slice (Q : Query; Offset_Count, Limit_Count : Natural) return Query is
   begin
      return Limit (Offset (Q, Offset_Count), Limit_Count);
   end Slice;

   function Numeric (V : Database.Values.Value; Out_Value : out Long_Float) return Boolean is
   begin
      case V.Kind is
         when Database.Types.Integer_Value => Out_Value := Long_Float (V.Int);
         return True;
         when Database.Types.Long_Integer_Value => Out_Value := Long_Float (V.Long_Int);
         return True;
         when Database.Types.Float_Value => Out_Value := V.Flt;
         return True;
         when Database.Types.Decimal_Value => Out_Value := Long_Float (V.Dec.Coefficient);
            for I in 1 .. V.Dec.Scale loop
               Out_Value := Out_Value / 10.0;
            end loop;
            return True;
         when others => return False;
      end case;
   end Numeric;

   function Aggregate
     (Q          : Query;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector;
      Result     : out Database.Rows.Row) return Database.Status.Result is
      Count_Non_Null : Natural;
      Count_All_Rows : constant Natural := Natural (Q.Data.Length);
      Have : Boolean;
      Best : Database.Values.Value;
      Sum_Value : Long_Float;
      X : Long_Float;
      V : Database.Values.Value;
   begin
      Result.Values.Clear;
      for A of Aggregates loop
         Count_Non_Null := 0;
         Have := False;
         Best := Database.Values.Null_Value;
         Sum_Value := 0.0;
         case A.Kind is
            when Database.Aggregates.Count_All =>
               Database.Rows.Append (Result, Database.Values.From_Integer (Count_All_Rows));
            when Database.Aggregates.Count_Column =>
               for Row of Q.Data loop
                  if A.Column >= Database.Rows.Column_Count (Row) then
                     return Database.Status.Failure (Database.Status.Invalid_Argument,
                       "aggregate column index is out of range");
                  end if;
                  if Database.Rows.Get (Row, A.Column).Kind /= Database.Types.Null_Value then
                     Count_Non_Null := Count_Non_Null + 1;
                  end if;
               end loop;
               Database.Rows.Append (Result, Database.Values.From_Integer (Count_Non_Null));
            when Database.Aggregates.Minimum | Database.Aggregates.Maximum =>
               for Row of Q.Data loop
                  if A.Column >= Database.Rows.Column_Count (Row) then
                     return Database.Status.Failure (Database.Status.Invalid_Argument,
                       "aggregate column index is out of range");
                  end if;
                  V := Database.Rows.Get (Row, A.Column);
                  if V.Kind /= Database.Types.Null_Value then
                        if not Have then
                           Best := V;
                           Have := True;
                        elsif (A.Kind = Database.Aggregates.Minimum and then Database.Ordering.Compare (V, Best) < 0)
                          or else  (A.Kind = Database.Aggregates.Maximum and then Database.Ordering.Compare (V,
                            Best) > 0) then
                           Best := V;
                        end if;
                     end if;
               end loop;
               Database.Rows.Append (Result, Best);
            when Database.Aggregates.Total | Database.Aggregates.Average =>
               for Row of Q.Data loop
                  if A.Column >= Database.Rows.Column_Count (Row) then
                     return Database.Status.Failure (Database.Status.Invalid_Argument,
                       "aggregate column index is out of range");
                  end if;
                  V := Database.Rows.Get (Row, A.Column);
                  if V.Kind /= Database.Types.Null_Value then
                        if not Numeric (V, X) then
                           return Database.Status.Failure (Database.Status.Invalid_Argument,
                             "aggregate requires numeric values");
                        end if;
                        Sum_Value := Sum_Value + X;
                        Count_Non_Null := Count_Non_Null + 1;
                     end if;
               end loop;
               if A.Kind = Database.Aggregates.Total then
                  Database.Rows.Append (Result, Database.Values.From_Float (Sum_Value));
               elsif Count_Non_Null = 0 then
                  Database.Rows.Append (Result, Database.Values.Null_Value);
               else
                  Database.Rows.Append
                    (Result,
                     Database.Values.From_Float
                       (Long_Float
                          (Long_Long_Integer (Sum_Value)
                           / Long_Long_Integer (Count_Non_Null))));
               end if;
         end case;
      end loop;
      return Database.Status.Success;
   end Aggregate;

   function Same_Group (L, R : Database.Rows.Row; Columns : Column_Vectors.Vector) return Boolean is
      LV, RV : Database.Values.Value;
   begin
      for C of Columns loop
         LV := (if C < Database.Rows.Column_Count (L) then Database.Rows.Get (L, C) else Database.Values.Null_Value);
         RV := (if C < Database.Rows.Column_Count (R) then Database.Rows.Get (R, C) else Database.Values.Null_Value);
         if not Database.Values.Equal (LV, RV) then
            return False;
         end if;
      end loop;
      return True;
   end Same_Group;

   function Group_By
     (Q          : Query;
      Columns    : Column_Vectors.Vector;
      Aggregates : Database.Aggregates.Aggregate_Vectors.Vector;
      Result     : out Query) return Database.Status.Result is
      Used : array (0 .. Natural'Max (Natural (Q.Data.Length), 1) - 1) of Boolean := (others => False);
      Group_Q : Query;
      Agg_Row, Out_Row : Database.Rows.Row;
      R : Database.Status.Result;
      S : Database.Status.Result;
   begin
      Result := Empty;
      Result.Use_Optimizer := Q.Use_Optimizer;
      S := Validate_Columns (Q, Columns);
      if not Database.Status.Is_Ok (S) then
         return S;
      end if;
      if Q.Data.Length = 0 then
         return Database.Status.Success;
      end if;
      for I in 0 .. Natural (Q.Data.Length) - 1 loop
         if not Used (I) then
            Group_Q := Empty;
            for J in I .. Natural (Q.Data.Length) - 1 loop
               if not Used (J) and then Same_Group (Q.Data.Element (I), Q.Data.Element (J), Columns) then
                  Used (J) := True;
                  Group_Q.Data.Append (Q.Data.Element (J));
               end if;
            end loop;
            Out_Row.Values.Clear;
            for C of Columns loop
               if C < Database.Rows.Column_Count (Q.Data.Element (I)) then
                  Database.Rows.Append (Out_Row, Database.Rows.Get (Q.Data.Element (I), C));
               else
                  Database.Rows.Append (Out_Row, Database.Values.Null_Value);
               end if;
            end loop;
            R := Aggregate (Group_Q, Aggregates, Agg_Row);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            if Database.Rows.Column_Count (Agg_Row) > 0 then
               for K in 0 .. Database.Rows.Column_Count (Agg_Row) - 1 loop
                  Database.Rows.Append (Out_Row, Database.Rows.Get (Agg_Row, K));
               end loop;
            end if;
            Result.Data.Append (Out_Row);
         end if;
      end loop;
      return Database.Status.Success;
   end Group_By;

   function Try_Full_Text_Search
     (Tx       : in out Database.Transactions.Transaction;
      Index    : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query;
      Result   : out Query) return Database.Status.Result is
      C : Database.Full_Text.Search_Cursor;
      Search_R : Database.Status.Result;
   begin
      Database.Metrics.Increment_Full_Text_Queries;
      Result := Empty;
      Search_R := Database.Full_Text.Try_Search (Tx, Index, Database.Full_Text.Queries.Text (FT_Query), C);
      if not Database.Status.Is_Ok (Search_R) then
         return Search_R;
      end if;
      while Database.Full_Text.Has_Element (C) loop
         declare
            Hit : constant Database.Full_Text.Search_Result := Database.Full_Text.Element (C);
            Row : Database.Rows.Row;
            Resolve_R : Database.Status.Result;
         begin
            --  Resolve through the full-text subsystem so persistent queries
            --  use the table heap after reopen instead of the transient
            --  catalog row cache.
            Resolve_R := Database.Full_Text.Resolve_Row (Tx, Hit, Row);
            if not Database.Status.Is_Ok (Resolve_R) then
               return Resolve_R;
            end if;
            Result.Data.Append (Row);
         end;
         Database.Full_Text.Next (C);
      end loop;
      return Database.Status.Success;
   end Try_Full_Text_Search;

   function Full_Text_Search
     (Tx    : in out Database.Transactions.Transaction;
      Index : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query) return Query is
      Result : Query;
      R : Database.Status.Result;
   begin
      R := Try_Full_Text_Search (Tx, Index, FT_Query, Result);
      pragma Unreferenced (R);
      return Result;
   end Full_Text_Search;

   function Try_Full_Text_Search_With_Score
     (Tx       : in out Database.Transactions.Transaction;
      Index    : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query;
      Result   : out Query) return Database.Status.Result is
      C : Database.Full_Text.Search_Cursor;
      Search_R : Database.Status.Result;
   begin
      Database.Metrics.Increment_Full_Text_Queries;
      Result := Empty;
      Search_R := Database.Full_Text.Try_Search (Tx, Index, Database.Full_Text.Queries.Text (FT_Query), C);
      if not Database.Status.Is_Ok (Search_R) then
         return Search_R;
      end if;
      while Database.Full_Text.Has_Element (C) loop
         declare
            Hit : constant Database.Full_Text.Search_Result := Database.Full_Text.Element (C);
            Row : Database.Rows.Row;
            Out_Row : Database.Rows.Row;
            Resolve_R : Database.Status.Result;
         begin
            Resolve_R := Database.Full_Text.Resolve_Row (Tx, Hit, Row);
            if not Database.Status.Is_Ok (Resolve_R) then
               return Resolve_R;
            end if;
            Out_Row := Row;
            Database.Rows.Append
              (Out_Row, Database.Values.From_Float (Long_Float (Hit.Score)));
            Result.Data.Append (Out_Row);
         end;
         Database.Full_Text.Next (C);
      end loop;
      return Database.Status.Success;
   end Try_Full_Text_Search_With_Score;

   function Full_Text_Search_With_Score
     (Tx       : in out Database.Transactions.Transaction;
      Index    : Wide_Wide_String;
      FT_Query : Database.Full_Text.Queries.Query) return Query is
      Result : Query;
      R : Database.Status.Result;
   begin
      R := Try_Full_Text_Search_With_Score (Tx, Index, FT_Query, Result);
      pragma Unreferenced (R);
      return Result;
   end Full_Text_Search_With_Score;

   procedure Execute (Q : Query; C : out Cursor) is
   begin
      C.Data := Q.Data;
      C.Index := 0;
      Database.Metrics.Increment_Query_Executions;
      Database.Metrics.Add_Rows_Returned (Natural (Q.Data.Length));
   end Execute;

   function Has_Element (C : Cursor) return Boolean is
   begin
      return C.Index < Natural (C.Data.Length);
   end Has_Element;

   function Element (C : Cursor) return Database.Rows.Row is
   begin
      return C.Data.Element (C.Index);
   end Element;

   procedure Next (C : in out Cursor) is
   begin
      if C.Index < Natural'Last then
         C.Index := C.Index + 1;
      end if;
   end Next;

   function Row_Count (Q : Query) return Natural is (Natural (Q.Data.Length));
   function Rows (Q : Query) return Row_Vectors.Vector is (Q.Data);

   procedure Enable_Optimizer (Q : in out Query) is
   begin
      Q.Use_Optimizer := True;
   end Enable_Optimizer;

   procedure Disable_Optimizer (Q : in out Query) is
   begin
      Q.Use_Optimizer := False;
   end Disable_Optimizer;

   function Optimizer_Enabled (Q : Query) return Boolean is
   begin
      return Q.Use_Optimizer;
   end Optimizer_Enabled;

   function Explain_Plan (Plan : Database.Execution_Plans.Physical_Plan) return Wide_Wide_String is
   begin
      return Database.Execution_Plans.Explain (Plan);
   end Explain_Plan;

   function Hex_Digit (N : Natural) return Wide_Wide_Character is
   begin
      if N < 10 then
         return Wide_Wide_Character'Val (Wide_Wide_Character'Pos ('0') + N);
      else
         return Wide_Wide_Character'Val (Wide_Wide_Character'Pos ('A') + (N - 10));
      end if;
   end Hex_Digit;

   procedure Append_Codepoint_Hex
     (S : in out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      C : Wide_Wide_Character) is
      V : Natural := Wide_Wide_Character'Pos (C);
      Hex_Buffer : Wide_Wide_String (1 .. 8);
   begin
      for I in reverse Hex_Buffer'Range loop
         Hex_Buffer (I) := Hex_Digit (V mod 16);
         V := V / 16;
      end loop;
      Ada.Strings.Wide_Wide_Unbounded.Append (S, Hex_Buffer);
   end Append_Codepoint_Hex;

   function Hex_Value (C : Wide_Wide_Character; V : out Natural) return Boolean is
   begin
      if C in '0' .. '9' then
         V := Wide_Wide_Character'Pos (C) - Wide_Wide_Character'Pos ('0');
         return True;
      elsif C in 'A' .. 'F' then
         V := 10 + Wide_Wide_Character'Pos (C) - Wide_Wide_Character'Pos ('A');
         return True;
      elsif C in 'a' .. 'f' then
         V := 10 + Wide_Wide_Character'Pos (C) - Wide_Wide_Character'Pos ('a');
         return True;
      else
         return False;
      end if;
   end Hex_Value;

   procedure Append_Field
     (S : in out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Field : Wide_Wide_String) is
   begin
      Ada.Strings.Wide_Wide_Unbounded.Append (S, Field);
      Ada.Strings.Wide_Wide_Unbounded.Append (S, "|");
   end Append_Field;

   procedure Append_Text_Field
     (S : in out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Text : Wide_Wide_String) is
   begin
      Append_Field (S, Natural'Wide_Wide_Image (Text'Length));
      for Ch of Text loop
         Append_Codepoint_Hex (S, Ch);
      end loop;
      Ada.Strings.Wide_Wide_Unbounded.Append (S, "|");
   end Append_Text_Field;

   procedure Append_Value_Image
     (S : in out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      V : Database.Values.Value) is
   begin
      Append_Field (S, Database.Types.Value_Kind'Wide_Wide_Image (V.Kind));
      case V.Kind is
         when Database.Types.Null_Value =>
            null;
         when Database.Types.Boolean_Value =>
            Append_Field (S, (if V.Bool then "1" else "0"));
         when Database.Types.Integer_Value =>
            Append_Field (S, Integer'Wide_Wide_Image (V.Int));
         when Database.Types.Long_Integer_Value =>
            Append_Field (S, Long_Long_Integer'Wide_Wide_Image (V.Long_Int));
         when Database.Types.Float_Value =>
            Append_Field (S, Long_Float'Wide_Wide_Image (V.Flt));
         when Database.Types.Decimal_Value =>
            Append_Field (S, Long_Long_Integer'Wide_Wide_Image (V.Dec.Coefficient));
            Append_Field (S, Natural'Wide_Wide_Image (V.Dec.Scale));
         when Database.Types.Text_Value =>
            Append_Text_Field (S, Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Text));
         when Database.Types.Blob_Value =>
            Append_Field (S, Natural'Wide_Wide_Image (Natural (V.Blob.Length)));
            for B of V.Blob loop
               Append_Field (S, Natural'Wide_Wide_Image (Natural (B)));
            end loop;
         when Database.Types.Timestamp_Value =>
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Year));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Month));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Day));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Hour));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Minute));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Second));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time.Nanosecond));
         when Database.Types.Enum_Value =>
            Append_Text_Field (S, Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Enum_Text));
         when Database.Types.Date_Value =>
            Append_Field (S, Natural'Wide_Wide_Image (V.Date.Year));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date.Month));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date.Day));
         when Database.Types.Time_Value =>
            Append_Field (S, Natural'Wide_Wide_Image (V.Clock_Time.Hour));
            Append_Field (S, Natural'Wide_Wide_Image (V.Clock_Time.Minute));
            Append_Field (S, Natural'Wide_Wide_Image (V.Clock_Time.Second));
            Append_Field (S, Natural'Wide_Wide_Image (V.Clock_Time.Nanosecond));
         when Database.Types.Date_Time_Value =>
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Date_Part.Year));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Date_Part.Month));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Date_Part.Day));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Time_Part.Hour));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Time_Part.Minute));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Time_Part.Second));
            Append_Field (S, Natural'Wide_Wide_Image (V.Date_Time.Time_Part.Nanosecond));
         when Database.Types.Duration_Value =>
            Append_Field (S, Long_Long_Integer'Wide_Wide_Image (V.Time_Span.Seconds));
            Append_Field (S, Natural'Wide_Wide_Image (V.Time_Span.Nanoseconds));
         when Database.Types.UUID_Value =>
            for B of V.UUID loop
               Append_Field (S, Natural'Wide_Wide_Image (Natural (B)));
            end loop;
         when Database.Types.Array_Value =>
            Append_Text_Field (S, Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Array_Text));
      end case;
   end Append_Value_Image;

   function Next_Field
     (Image : Wide_Wide_String;
      Pos   : in out Natural;
      Field : out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String) return Boolean is
      Start : Natural := Pos;
   begin
      if Pos > Image'Last + 1 then
         return False;
      end if;
      while Pos <= Image'Last loop
         if Image (Pos) = '|' then
            Field := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
              (Image (Start .. Pos - 1));
            Pos := Pos + 1;
            return True;
         end if;
         Pos := Pos + 1;
      end loop;
      return False;
   end Next_Field;

   function Next_Natural
     (Image : Wide_Wide_String;
      Pos   : in out Natural;
      V     : out Natural) return Boolean is
      F : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   begin
      if not Next_Field (Image, Pos, F) then
         return False;
      end if;
      V := Natural'Wide_Wide_Value (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (F));
      return True;
   exception
      when others =>
         return False;
   end Next_Natural;

   function Next_Integer
     (Image : Wide_Wide_String;
      Pos   : in out Natural;
      V     : out Integer) return Boolean is
      F : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   begin
      if not Next_Field (Image, Pos, F) then
         return False;
      end if;
      V := Integer'Wide_Wide_Value (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (F));
      return True;
   exception when others => return False;
   end Next_Integer;

   function Next_Long_Long_Integer
     (Image : Wide_Wide_String;
      Pos   : in out Natural;
      V     : out Long_Long_Integer) return Boolean is
      F : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   begin
      if not Next_Field (Image, Pos, F) then
         return False;
      end if;
      V := Long_Long_Integer'Wide_Wide_Value (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (F));
      return True;
   exception when others => return False;
   end Next_Long_Long_Integer;

   function Next_Text
     (Image : Wide_Wide_String;
      Pos   : in out Natural;
      Text  : out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String) return Boolean is
      Len : Natural;
      Enc : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   begin
      if not Next_Natural (Image, Pos, Len) or else not Next_Field (Image, Pos, Enc) then
         return False;
      end if;
      declare
         Raw : constant Wide_Wide_String := Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Enc);
         Out_Text : Wide_Wide_String (1 .. Len);
         P : Natural := Raw'First;
      begin
         if Raw'Length /= Len * 8 then
            return False;
         end if;
         for I in Out_Text'Range loop
            declare
               V : Natural := 0;
               N : Natural;
            begin
               for D in 1 .. 8 loop
                  if not Hex_Value (Raw (P), N) then
                     return False;
                  end if;
                  V := V * 16 + N;
                  P := P + 1;
               end loop;
               if V > Wide_Wide_Character'Pos (Wide_Wide_Character'Last) then
                  return False;
               end if;
               Out_Text (I) := Wide_Wide_Character'Val (V);
            end;
         end loop;
         Text := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Out_Text);
         return True;
      end;
   exception
      when others =>
         return False;
   end Next_Text;

   function Next_Value
     (Image : Wide_Wide_String;
      Pos   : in out Natural;
      V     : out Database.Values.Value) return Boolean is
      Kind_Field : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Kind : Database.Types.Value_Kind;
   begin
      if not Next_Field (Image, Pos, Kind_Field) then
         return False;
      end if;
      Kind := Database.Types.Value_Kind'Wide_Wide_Value
        (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Kind_Field));
      case Kind is
         when Database.Types.Null_Value =>
            V := Database.Values.Null_Value;
         when Database.Types.Boolean_Value =>
            declare
               B : Natural;
            begin
               if not Next_Natural (Image, Pos, B) or else B > 1 then
                  return False;
               end if;
               V := Database.Values.From_Boolean (B = 1);
            end;
         when Database.Types.Integer_Value =>
            declare
               I : Integer;
            begin
               if not Next_Integer (Image, Pos, I) then
                  return False;
               end if;
               V := Database.Values.From_Integer (I);
            end;
         when Database.Types.Long_Integer_Value =>
            declare
               I : Long_Long_Integer;
            begin
               if not Next_Long_Long_Integer (Image, Pos, I) then
                  return False;
               end if;
               V := Database.Values.From_Long_Integer (I);
            end;
         when Database.Types.Float_Value =>
            declare
               Fld : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
            begin
               if not Next_Field (Image, Pos, Fld) then
                  return False;
               end if;
               V  :=
                 Database.Values.From_Float (Long_Float'Wide_Wide_Value (
                   Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Fld)));
            end;
         when Database.Types.Decimal_Value =>
            declare
               C : Long_Long_Integer;
            Scale : Natural;
            begin
               if not Next_Long_Long_Integer  (Image,
                 Pos,
                 C) or else not Next_Natural (Image,
                 Pos,
                 Scale) then
                    return False;
                 end if;
               V := Database.Values.From_Decimal ((Coefficient => C, Scale => Scale));
            end;
         when Database.Types.Text_Value =>
            declare
               T : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
            begin
               if not Next_Text (Image, Pos, T) then
                  return False;
               end if;
               V := Database.Values.From_Text (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (T));
            end;
         when Database.Types.Blob_Value =>
            declare
               Len, B : Natural;
            Bytes : Database.Values.Byte_Vectors.Vector;
            begin
               if not Next_Natural (Image, Pos, Len) then
                  return False;
               end if;
               for I in 1 .. Len loop
                  if not Next_Natural (Image, Pos, B) or else B > 255 then
                     return False;
                  end if;
                  Bytes.Append (Database.Values.Byte (B));
               end loop;
               V := Database.Values.From_Blob (Bytes);
            end;
         when Database.Types.Timestamp_Value =>
            declare
               Y, Mo, D, H, Mi, S, N : Natural;
            begin
               if not Next_Natural  (Image,
                 Pos,
                 Y) or else not Next_Natural (Image,
                 Pos,
                 Mo) or else not Next_Natural (Image,
                 Pos,
                 D)
                 or else not Next_Natural  (Image,
                   Pos,
                   H) or else not Next_Natural (Image,
                   Pos,
                   Mi) or else not Next_Natural (Image,
                   Pos,
                   S)
                 or else not Next_Natural (Image, Pos, N)
               then
                  return False;
               end if;
               V := Database.Values.From_Timestamp  ((Year => Y,
                 Month => Mo,
                 Day => D,
                 Hour => H,
                 Minute => Mi,
                 Second => S,
                 Nanosecond => N));
            end;
         when Database.Types.Enum_Value =>
            declare
               T : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
            begin
               if not Next_Text (Image, Pos, T) then
                  return False;
               end if;
               V := Database.Values.From_Enum (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (T));
            end;
         when Database.Types.Date_Value =>
            declare
               Y, Mo, D : Natural;
            begin
               if not Next_Natural  (Image,
                 Pos,
                 Y) or else not Next_Natural (Image,
                 Pos,
                 Mo) or else not Next_Natural (Image,
                 Pos,
                 D) then
                    return False;
                 end if;
               V := Database.Values.From_Date ((Year => Y, Month => Mo, Day => D));
            end;
         when Database.Types.Time_Value =>
            declare
               H, Mi, S, N : Natural;
            begin
               if not Next_Natural  (Image,
                 Pos,
                 H) or else not Next_Natural (Image,
                 Pos,
                 Mi) or else not Next_Natural (Image,
                 Pos,
                 S) or else not Next_Natural (Image,
                 Pos,
                 N) then
                    return False;
                 end if;
               V := Database.Values.From_Time ((Hour => H, Minute => Mi, Second => S, Nanosecond => N));
            end;
         when Database.Types.Date_Time_Value =>
            declare
               Y, Mo, D, H, Mi, S, N : Natural;
            begin
               if not Next_Natural  (Image,
                 Pos,
                 Y) or else not Next_Natural (Image,
                 Pos,
                 Mo) or else not Next_Natural (Image,
                 Pos,
                 D)
                 or else not Next_Natural  (Image,
                   Pos,
                   H) or else not Next_Natural (Image,
                   Pos,
                   Mi) or else not Next_Natural (Image,
                   Pos,
                   S)
                 or else not Next_Natural (Image, Pos, N)
               then
                  return False;
               end if;
               V := Database.Values.From_Date_Time  ((Date_Part => (Year => Y,
                 Month => Mo,
                 Day => D),
                 Time_Part => (Hour => H,
                 Minute => Mi,
                 Second => S,
                 Nanosecond => N)));
            end;
         when Database.Types.Duration_Value =>
            declare
               Seconds : Long_Long_Integer;
            N : Natural;
            begin
               if not Next_Long_Long_Integer  (Image,
                 Pos,
                 Seconds) or else not Next_Natural (Image,
                 Pos,
                 N) then
                    return False;
                 end if;
               V := Database.Values.From_Duration ((Seconds => Seconds, Nanoseconds => N));
            end;
         when Database.Types.UUID_Value =>
            declare
               U : Database.UUIDs.UUID;
            B : Natural;
            begin
               for I in U'Range loop
                  if not Next_Natural (Image, Pos, B) or else B > 255 then
                     return False;
                  end if;
                  U (I) := Database.UUIDs.Byte (B);
               end loop;
               V := Database.Values.From_UUID (U);
            end;
         when Database.Types.Array_Value =>
            declare
               T : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
            begin
               if not Next_Text (Image, Pos, T) then
                  return False;
               end if;
               V := Database.Values.From_Array_Text (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (T));
            end;
      end case;
      return True;
   exception
      when others =>
         return False;
   end Next_Value;

   function Persistent_Image (Q : Query) return Wide_Wide_String is
      S : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String  :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("QUERY_ROWS_V2|");
   begin
      Append_Field (S, Natural'Wide_Wide_Image (Natural (Q.Data.Length)));
      for R of Q.Data loop
         Append_Field (S, Natural'Wide_Wide_Image (Database.Rows.Column_Count (R)));
         if Database.Rows.Column_Count (R) > 0 then
            for I in 0 .. Database.Rows.Column_Count (R) - 1 loop
               Append_Value_Image (S, Database.Rows.Get (R, I));
            end loop;
         end if;
      end loop;
      return Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (S);
   end Persistent_Image;

   function From_Persistent_Image
     (Image : Wide_Wide_String;
      Q     : out Query) return Database.Status.Result is
      Prefix_V1 : constant Wide_Wide_String := "QUERY_ROWS_V1:";
      Prefix_V2 : constant Wide_Wide_String := "QUERY_ROWS_V2|";
      Pos       : Natural;
      Row_Total : Natural;
   begin
      Q := Empty;
      if Image'Length >= Prefix_V1'Length
        and then Image (Image'First .. Image'First + Prefix_V1'Length - 1) = Prefix_V1
      then
         --  Backward compatibility for metadata written before query
         --  bodies were fully durable. V1 deliberately carried only an empty
         --  body marker;
         --  do not invent rows while reading old catalogs.
         return Database.Status.Success;
      end if;

      if Image'Length < Prefix_V2'Length
        or else Image (Image'First .. Image'First + Prefix_V2'Length - 1) /= Prefix_V2
      then
         return Database.Status.Failure (Database.Status.Corrupt_File, "invalid persistent query image");
      end if;

      Pos := Image'First + Prefix_V2'Length;
      if not Next_Natural (Image, Pos, Row_Total) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "missing persistent query row count");
      end if;

      for Row_Index in 1 .. Row_Total loop
         declare
            Col_Total : Natural;
            R         : Database.Rows.Row;
            V         : Database.Values.Value;
         begin
            if not Next_Natural (Image, Pos, Col_Total) then
               return Database.Status.Failure (Database.Status.Corrupt_File, "missing persistent query column count");
            end if;
            for Col_Index in 1 .. Col_Total loop
               if not Next_Value (Image, Pos, V) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "malformed persistent query value");
               end if;
               Database.Rows.Append (R, V);
            end loop;
            Append (Q, R);
         end;
      end loop;

      if Pos <= Image'Last then
         return Database.Status.Failure (Database.Status.Corrupt_File, "trailing data in persistent query image");
      end if;
      return Database.Status.Success;
   exception
      when others =>
         Q := Empty;
         return Database.Status.Failure (Database.Status.Corrupt_File, "malformed persistent query image");
   end From_Persistent_Image;

end Database.Queries;
