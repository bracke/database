with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Containers;
with Database.Types;
with Database.Date_Time;
with Database.UUIDs;
with Database.Values;

package body Database.Indexes is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Database.Types.Value_Kind;
   use type Ada.Containers.Count_Type;

   function Supports_Key (Kind : Database.Types.Value_Kind) return Boolean is
   begin
      case Kind is
         when Database.Types.Boolean_Value | Database.Types.Integer_Value |
              Database.Types.Long_Integer_Value | Database.Types.Float_Value |
              Database.Types.Decimal_Value | Database.Types.Text_Value |
              Database.Types.Timestamp_Value | Database.Types.Enum_Value |
              Database.Types.Date_Value | Database.Types.Time_Value |
              Database.Types.Date_Time_Value | Database.Types.Duration_Value |
              Database.Types.UUID_Value =>
            return True;
         when others =>
            return False;
      end case;
   end Supports_Key;

   function Normalize_Decimal (D : Database.Types.Decimal; Target_Scale : Natural) return Long_Long_Integer is
      V : Long_Long_Integer := D.Coefficient;
   begin
      for I in D.Scale + 1 .. Target_Scale loop
         V := V * 10;
      end loop;
      return V;
   end Normalize_Decimal;

   function Compare_Timestamp (L, R : Database.Types.Timestamp) return Ordering is
   begin
      if L.Year /= R.Year then
         return (if L.Year < R.Year then
         Less else Greater);
      end if;
      if L.Month /= R.Month then
         return (if L.Month < R.Month then
         Less else Greater);
      end if;
      if L.Day /= R.Day then
         return (if L.Day < R.Day then
         Less else Greater);
      end if;
      if L.Hour /= R.Hour then
         return (if L.Hour < R.Hour then
         Less else Greater);
      end if;
      if L.Minute /= R.Minute then
         return (if L.Minute < R.Minute then
         Less else Greater);
      end if;
      if L.Second /= R.Second then
         return (if L.Second < R.Second then
         Less else Greater);
      end if;
      if L.Nanosecond /= R.Nanosecond then
         return (if L.Nanosecond < R.Nanosecond then
         Less else Greater);
      end if;
      return Equal;
   end Compare_Timestamp;

   function Compare (Left, Right : Database.Values.Value; Order : out Ordering) return Database.Status.Result is
   begin
      if Left.Kind = Database.Types.Null_Value or else Right.Kind = Database.Types.Null_Value then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "null index key");
      end if;
      if Left.Kind /= Right.Kind then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "mixed key kinds cannot be compared");
      end if;
      if not Supports_Key (Left.Kind) then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "unsupported index key type");
      end if;
      case Left.Kind is
         when Database.Types.Boolean_Value =>
            Order  :=
              (if Left.Bool = Right.Bool then Equal elsif (not Left.Bool and Right.Bool) then Less else Greater);
         when Database.Types.Integer_Value =>
            Order := (if Left.Int = Right.Int then Equal elsif Left.Int < Right.Int then Less else Greater);
         when Database.Types.Long_Integer_Value =>
            Order  :=
              (if Left.Long_Int
                = Right.Long_Int then Equal elsif Left.Long_Int < Right.Long_Int then Less else Greater);
         when Database.Types.Float_Value =>
            Order := (if Left.Flt = Right.Flt then Equal elsif Left.Flt < Right.Flt then Less else Greater);
         when Database.Types.Decimal_Value =>
            declare
               S : constant Natural := Natural'Max (Left.Dec.Scale, Right.Dec.Scale);
               L : constant Long_Long_Integer := Normalize_Decimal (Left.Dec, S);
               R : constant Long_Long_Integer := Normalize_Decimal (Right.Dec, S);
            begin
               Order := (if L = R then Equal elsif L < R then Less else Greater);
            end;
         when Database.Types.Text_Value =>
            declare
               L : constant Wide_Wide_String := To_Wide_Wide_String (Left.Text);
            R : constant Wide_Wide_String := To_Wide_Wide_String (Right.Text);
            begin
               Order := (if L = R then Equal elsif L < R then Less else Greater);
            end;
         when Database.Types.Timestamp_Value =>
            Order := Compare_Timestamp (Left.Time, Right.Time);
         when Database.Types.Enum_Value =>
            declare
               L : constant Wide_Wide_String := To_Wide_Wide_String (Left.Enum_Text);
            R : constant Wide_Wide_String := To_Wide_Wide_String (Right.Enum_Text);
            begin
               Order := (if L = R then Equal elsif L < R then Less else Greater);
            end;
         when Database.Types.Date_Value => declare C : constant Integer := Database.Date_Time.Compare  (Left.Date,
           Right.Date);
           begin Order := (if C = 0 then Equal elsif C < 0 then Less else Greater);
           end;
         when Database.Types.Time_Value => declare C : constant Integer  :=
           Database.Date_Time.Compare  (Left.Clock_Time,
           Right.Clock_Time);
           begin Order := (if C = 0 then Equal elsif C < 0 then Less else Greater);
           end;
         when Database.Types.Date_Time_Value => declare C : constant Integer  :=
           Database.Date_Time.Compare  (Left.Date_Time,
           Right.Date_Time);
           begin Order := (if C = 0 then Equal elsif C < 0 then Less else Greater);
           end;
         when Database.Types.Duration_Value => declare C : constant Integer  :=
           Database.Date_Time.Compare  (Left.Time_Span,
           Right.Time_Span);
           begin Order := (if C = 0 then Equal elsif C < 0 then Less else Greater);
           end;
         when Database.Types.UUID_Value => declare C : constant Integer := Database.UUIDs.Compare  (Left.UUID,
           Right.UUID);
           begin Order := (if C = 0 then Equal elsif C < 0 then Less else Greater);
           end;
         when others =>
            return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "unsupported index key type");
      end case;
      return Database.Status.Success;
   end Compare;

   function Validate_Key (Key : Database.Values.Value) return Database.Status.Result is
   begin
      if Key.Kind = Database.Types.Null_Value then
         return Database.Status.Failure (Database.Status.Constraint_Error, "primary key cannot be null");
      elsif not Supports_Key (Key.Kind) then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "unsupported primary key type");
      else
         return Database.Status.Success;
      end if;
   end Validate_Key;

   function Compare_Composite (Left, Right : Composite_Key; Order : out Ordering) return Database.Status.Result is
      Part_Order : Ordering := Equal;
      R : Database.Status.Result;
   begin
      if Left.Parts.Length /= Right.Parts.Length then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type,
           "composite keys must have the same arity");
      end if;
      if Left.Parts.Length = 0 then
         Order := Equal;
         return Database.Status.Success;
      end if;
      for I in 0 .. Natural (Left.Parts.Length) - 1 loop
         R := Compare (Left.Parts.Element (I), Right.Parts.Element (I), Part_Order);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         if Part_Order /= Equal then
            Order := Part_Order;
            return Database.Status.Success;
         end if;
      end loop;
      Order := Equal;
      return Database.Status.Success;
   end Compare_Composite;

   function Validate_Composite_Key (Key : Composite_Key) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if Key.Parts.Length = 0 then
         return Database.Status.Failure (Database.Status.Constraint_Error,
           "composite key must contain at least one part");
      end if;
      for P of Key.Parts loop
         R := Validate_Key (P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_Composite_Key;

   function Validate_Secondary_Key (Key : Database.Values.Value) return Database.Status.Result is
   begin
      if Key.Kind = Database.Types.Null_Value then
         return Database.Status.Success;
      elsif not Supports_Key (Key.Kind) then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "unsupported secondary index key type");
      else
         return Database.Status.Success;
      end if;
   end Validate_Secondary_Key;

   function Metadata_Name (Table_Name : Wide_Wide_String) return Unbounded_Wide_Wide_String is
   begin
      return To_Unbounded_Wide_Wide_String (Table_Name & ".primary_key");
   end Metadata_Name;

   function Validate_Row_Reference (Ref : Row_Reference) return Database.Status.Result is
   begin
      if Ref.Page = Database.Storage.Pages.Invalid_Page_Id then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "invalid row reference page");
      end if;
      return Database.Status.Success;
   end Validate_Row_Reference;

   function Validate_Index_Metadata (Index : Index_Metadata) return Database.Status.Result is
   begin
      if Index.Id = 0 then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "index has invalid id");
      end if;
      if Index.Table_Id = 0 then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "index has invalid table id");
      end if;
      if Length (Index.Name) = 0 then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "index has empty name");
      end if;
      if Index.Root_Page = Database.Storage.Pages.Invalid_Page_Id then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "index has invalid root page");
      end if;
      if Index.Column_Ids.Length = 0 and then not Supports_Key (Index.Key_Kind) then
         return Database.Status.Failure (Database.Status.Unsupported_Key_Type, "index key kind is not supported");
      end if;
      if Index.Kind = Partial_Index and then not Index.Has_Predicate then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "partial index requires a predicate");
      end if;
      if Index.Kind = Expression_Index and then not Index.Has_Expression then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "expression index requires an expression");
      end if;
      if Index.Kind = Primary_Key_Index and then not Index.Unique then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "primary index is not unique");
      end if;
      return Database.Status.Success;
   end Validate_Index_Metadata;

   function Validate_Key_Ordering
     (Previous : Database.Values.Value;
      Current  : Database.Values.Value) return Database.Status.Result is
      O : Ordering;
      R : Database.Status.Result := Compare (Previous, Current, O);
   begin
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if O = Greater then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "index keys are out of order");
      end if;
      return Database.Status.Success;
   end Validate_Key_Ordering;
end Database.Indexes;
