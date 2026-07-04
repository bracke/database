with Database.Rows;
with Database.Schema;
with Database.Storage.Pages;
with Database.Status;
with Ada.Characters.Conversions;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Constraints;
with Database.Types;
with Database.Values;
with Database.Date_Time;
with Database.UUIDs;
with Interfaces;

package body Database.Storage.Record_Format is
   use Database.Storage.Pages;
   use type Database.Types.Value_Kind;
   use type Interfaces.Unsigned_64;

   procedure Put (B : in out Byte_Vector; X : Byte) is
   begin
      B.Data (B.Last) := X;
      B.Last := B.Last + 1;
   end Put;

   procedure Put_U32 (B : in out Byte_Vector; V : Natural) is
   begin
      Put (B, Byte ((V / 16#1000000#) mod 256));
      Put (B, Byte ((V / 16#10000#) mod 256));
      Put (B, Byte ((V / 16#100#) mod 256));
      Put (B, Byte (V mod 256));
   end Put_U32;

   procedure Put_I64 (B : in out Byte_Vector; V : Long_Long_Integer) is
      U : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Mod (V);
   begin
      for Shift in reverse 0 .. 7 loop
         Put
           (B,
            Byte
              ((U / (Interfaces.Unsigned_64 (2) ** Natural (Shift * 8)))
               mod 256));
      end loop;
   end Put_I64;

   procedure Put_Text (B : in out Byte_Vector; S : Wide_Wide_String) is
   begin
      -- UTF-32BE: exact Unicode scalar storage without relying on Ada memory layout.
      Put_U32 (B, S'Length);
      for Ch of S loop
         Put_U32 (B, Wide_Wide_Character'Pos (Ch));
      end loop;
   end Put_Text;

   function Need (Pos, Count, Last : Natural) return Boolean is
   begin
      return Pos + Count <= Last;
   end Need;

   function Read_U32 (Data : Byte_Array; Pos : in out Natural; Last : Natural; V : out Natural) return Boolean is
   begin
      if not Need (Pos, 4, Last) then
         return False;
      end if;
      V := Natural (Data (Pos)) * 16#1000000# + Natural (Data (Pos + 1)) * 16#10000# + Natural (Data (Pos
        + 2)) * 16#100# + Natural (Data (Pos + 3));
      Pos := Pos + 4;
      return True;
   end Read_U32;

   function Read_I64
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      V    : out Long_Long_Integer) return Boolean is
      U : Interfaces.Unsigned_64 := 0;
      Sign_Bit : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (2) ** 63;
   begin
      if not Need (Pos, 8, Last) then
         return False;
      end if;
      for I in 0 .. 7 loop
         U := U * 256 + Interfaces.Unsigned_64 (Data (Pos + I));
      end loop;
      Pos := Pos + 8;
      if (U and Sign_Bit) = 0 then
         V := Long_Long_Integer (U);
      else
         declare
            Magnitude : constant Interfaces.Unsigned_64 := (not U) + 1;
         begin
            if Magnitude = Sign_Bit then
               V := Long_Long_Integer'First;
            else
               V := -Long_Long_Integer (Magnitude);
            end if;
         end;
      end if;
      return True;
   end Read_I64;

   function Serialize
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Result : out Byte_Vector) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      Result.Last := 0;
      Result.Data := (others => 0);
      R := Database.Constraints.Validate_Row (Schema, Row);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Put_U32 (Result, Database.Rows.Column_Count (Row));
      for I in 0 .. Database.Rows.Column_Count (Row) - 1 loop
         declare
            V : constant Database.Values.Value := Database.Rows.Get (Row, I);
         begin
            Put (Result, Byte (Database.Types.Value_Kind'Pos (V.Kind)));
            case V.Kind is
               when Database.Types.Null_Value =>
                  null;
               when Database.Types.Boolean_Value =>
                  Put (Result, (if V.Bool then 1 else 0));
               when Database.Types.Integer_Value =>
                  Put_I64 (Result, Long_Long_Integer (V.Int));
               when Database.Types.Long_Integer_Value =>
                  Put_I64 (Result, V.Long_Int);
               when Database.Types.Float_Value =>
                  Put_Text (Result, Long_Float'Wide_Wide_Image (V.Flt));
               when Database.Types.Decimal_Value =>
                  Put_I64 (Result, V.Dec.Coefficient);
                  Put_U32 (Result, V.Dec.Scale);
               when Database.Types.Text_Value =>
                  Put_Text
                    (Result,
                     Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String
                       (V.Text));
               when Database.Types.Blob_Value =>
                  Put_U32 (Result, Natural (V.Blob.Length));
                  for B of V.Blob loop
                     Put (Result, Byte (B));
                  end loop;
               when Database.Types.Timestamp_Value =>
                  Put_U32 (Result, Natural (V.Time.Year));
                  Put_U32 (Result, Natural (V.Time.Month));
                  Put_U32 (Result, Natural (V.Time.Day));
                  Put_U32 (Result, Natural (V.Time.Hour));
                  Put_U32 (Result, Natural (V.Time.Minute));
                  Put_U32 (Result, Natural (V.Time.Second));
                  Put_U32 (Result, V.Time.Nanosecond);
               when Database.Types.Enum_Value =>
                  Put_Text
                    (Result,
                     Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String
                       (V.Enum_Text));
               when Database.Types.Date_Value =>
                  Put_U32 (Result, Natural (V.Date.Year));
                  Put_U32 (Result, Natural (V.Date.Month));
                  Put_U32 (Result, Natural (V.Date.Day));
               when Database.Types.Time_Value =>
                  Put_U32 (Result, Natural (V.Clock_Time.Hour));
                  Put_U32 (Result, Natural (V.Clock_Time.Minute));
                  Put_U32 (Result, Natural (V.Clock_Time.Second));
                  Put_U32 (Result, V.Clock_Time.Nanosecond);
               when Database.Types.Date_Time_Value =>
                  Put_U32 (Result, Natural (V.Date_Time.Date_Part.Year));
                  Put_U32 (Result, Natural (V.Date_Time.Date_Part.Month));
                  Put_U32 (Result, Natural (V.Date_Time.Date_Part.Day));
                  Put_U32 (Result, Natural (V.Date_Time.Time_Part.Hour));
                  Put_U32 (Result, Natural (V.Date_Time.Time_Part.Minute));
                  Put_U32 (Result, Natural (V.Date_Time.Time_Part.Second));
                  Put_U32 (Result, V.Date_Time.Time_Part.Nanosecond);
               when Database.Types.Duration_Value =>
                  Put_I64 (Result, V.Time_Span.Seconds);
                  Put_U32 (Result, V.Time_Span.Nanoseconds);
               when Database.Types.UUID_Value =>
                  for B of V.UUID loop
                     Put (Result, Byte (B));
                  end loop;
               when Database.Types.Array_Value =>
                  Put_Text
                    (Result,
                     Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String
                       (V.Array_Text));
            end case;
         end;
      end loop;
      return Database.Status.Success;
   exception
      when others =>
         return Database.Status.Failure (Database.Status.Row_Too_Large, "serialized row exceeds page payload capacity");
   end Serialize;

   function Deserialize
     (Schema : Database.Schema.Table_Schema;
      Data   : Byte_Array;
      Row    : out Database.Rows.Row) return Database.Status.Result is
      Pos : Natural := Data'First;
      Last : constant Natural := Data'First + Data'Length;
      Count : Natural;
      function Read_Text (S : out Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String) return Boolean is
         Len : Natural;
      begin
         if not Read_U32 (Data, Pos, Last, Len) then
            return False;
         end if;
         declare
            T : Wide_Wide_String (1 .. Len);
            C : Natural;
         begin
            for I in T'Range loop
               if not Read_U32 (Data, Pos, Last, C) then
                  return False;
               end if;
               if C > Wide_Wide_Character'Pos (Wide_Wide_Character'Last) then
                  return False;
               end if;
               T (I) := Wide_Wide_Character'Val (C);
            end loop;
            S := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (T);
            return True;
         end;
      end Read_Text;
   begin
      Row.Values.Clear;
      if not Read_U32 (Data, Pos, Last, Count) then
         return Database.Status.Failure (Database.Status.Serialization_Error, "truncated record header");
      end if;
      if Count /= Database.Schema.Column_Count (Schema) then
         return Database.Status.Failure (Database.Status.Schema_Mismatch, "wrong serialized column count");
      end if;
      for I in 0 .. Count - 1 loop
         if not Need (Pos, 1, Last) then
            return Database.Status.Failure (Database.Status.Serialization_Error, "truncated value tag");
         end if;
         declare
            Tag : constant Natural := Natural (Data (Pos));
         begin
            Pos := Pos + 1;
            if Tag > Database.Types.Value_Kind'Pos (Database.Types.Value_Kind'Last) then
               return Database.Status.Failure (Database.Status.Serialization_Error, "invalid value tag");
            end if;
            case Database.Types.Value_Kind'Val (Tag) is
               when Database.Types.Null_Value => Database.Rows.Append (Row, Database.Values.Null_Value);
               when Database.Types.Boolean_Value =>
                  if not Need (Pos, 1, Last) then
                     return Database.Status.Failure (Database.Status.Serialization_Error, "truncated boolean");
                  end if;
                  Database.Rows.Append (Row, Database.Values.From_Boolean (Data (Pos) /= 0));
                  Pos := Pos + 1;
               when Database.Types.Integer_Value =>
                  declare
                     V : Long_Long_Integer;
                  begin
                     if not Read_I64 (Data, Pos, Last, V) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated integer");
                     end if;
                     Database.Rows.Append (Row, Database.Values.From_Integer (Integer (V)));
                  end;
               when Database.Types.Long_Integer_Value =>
                  declare
                     V : Long_Long_Integer;
                  begin
                     if not Read_I64 (Data, Pos, Last, V) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated long integer");
                     end if;
                     Database.Rows.Append (Row, Database.Values.From_Long_Integer (V));
                  end;
               when Database.Types.Float_Value =>
                  declare
                     S : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
                  begin
                     if not Read_Text (S) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated float");
                     end if;
                     Database.Rows.Append (Row,
                       Database.Values.From_Float (Long_Float'Wide_Wide_Value (
                         Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (S))));
                  end;
               when Database.Types.Decimal_Value =>
                  declare
                     C     : Long_Long_Integer;
                     Scale : Natural;
                     D     : Database.Types.Decimal;
                  begin
                     if not Read_I64 (Data, Pos, Last, C)
                       or else not Read_U32 (Data, Pos, Last, Scale)
                     then
                        return Database.Status.Failure
                          (Database.Status.Serialization_Error, "truncated decimal");
                     end if;
                     D := (Coefficient => C, Scale => Scale);
                     Database.Rows.Append (Row, Database.Values.From_Decimal (D));
                  end;
               when Database.Types.Text_Value =>
                  declare
                     S : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
                  begin
                     if not Read_Text (S) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated text");
                     end if;
                     Database.Rows.Append (Row,
                       Database.Values.From_Text (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (S)));
                  end;
               when Database.Types.Blob_Value =>
                  declare
                     Len : Natural;
                     B   : Database.Values.Byte_Vectors.Vector;
                  begin
                     if not Read_U32 (Data, Pos, Last, Len)
                       or else not Need (Pos, Len, Last)
                     then
                        return Database.Status.Failure
                          (Database.Status.Serialization_Error, "truncated blob");
                     end if;
                     for J in 1 .. Len loop
                        B.Append (Database.Values.Byte (Data (Pos)));
                        Pos := Pos + 1;
                     end loop;
                     Database.Rows.Append (Row, Database.Values.From_Blob (B));
                  end;
               when Database.Types.Timestamp_Value =>
                  declare
                     T                         : Database.Types.Timestamp;
                     Y, Mo, D, H, Mi, S, N    : Natural;
                  begin
                     if not Read_U32 (Data,
                       Pos,
                       Last,
                       Y) or else not Read_U32 (Data,
                       Pos,
                       Last,
                       Mo) or else not Read_U32 (Data,
                       Pos,
                       Last,
                       D) or else
                        not Read_U32 (Data,
                          Pos,
                          Last,
                          H) or else not Read_U32 (Data,
                          Pos,
                          Last,
                          Mi) or else not Read_U32 (Data,
                          Pos,
                          Last,
                          S) or else not Read_U32 (Data,
                          Pos,
                          Last,
                          N) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated timestamp");
                     end if;
                     T :=
                       (Year       => Y,
                        Month      => Mo,
                        Day        => D,
                        Hour       => H,
                        Minute     => Mi,
                        Second     => S,
                        Nanosecond => N);
                     Database.Rows.Append (Row, Database.Values.From_Timestamp (T));
                  end;
               when Database.Types.Enum_Value =>
                  declare
                     S : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
                  begin
                     if not Read_Text (S) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated enum");
                     end if;
                     Database.Rows.Append (Row,
                       Database.Values.From_Enum (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (S)));
                  end;
               when Database.Types.Date_Value =>
                  declare
                     Y, Mo, D : Natural;
                  begin
                     if not Read_U32 (Data, Pos, Last, Y)
                       or else not Read_U32 (Data, Pos, Last, Mo)
                       or else not Read_U32 (Data, Pos, Last, D)
                     then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated date");
                     end if;
                     Database.Rows.Append (Row, Database.Values.From_Date ((Year => Y, Month => Mo, Day => D)));
                  end;
               when Database.Types.Time_Value =>
                  declare
                     H, Mi, S, N : Natural;
                  begin
                     if not Read_U32 (Data, Pos, Last, H)
                       or else not Read_U32 (Data, Pos, Last, Mi)
                       or else not Read_U32 (Data, Pos, Last, S)
                       or else not Read_U32 (Data, Pos, Last, N)
                     then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated time");
                     end if;
                     Database.Rows.Append (Row,
                       Database.Values.From_Time ((Hour => H,
                       Minute => Mi,
                       Second => S,
                       Nanosecond => N)));
                  end;
               when Database.Types.Date_Time_Value =>
                  declare
                     Y, Mo, D, H, Mi, S, N : Natural;
                  begin
                     if not Read_U32 (Data, Pos, Last, Y)
                       or else not Read_U32 (Data, Pos, Last, Mo)
                       or else not Read_U32 (Data, Pos, Last, D)
                       or else not Read_U32 (Data, Pos, Last, H)
                       or else not Read_U32 (Data, Pos, Last, Mi)
                       or else not Read_U32 (Data, Pos, Last, S)
                       or else not Read_U32 (Data, Pos, Last, N)
                     then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated date_time");
                     end if;
                     Database.Rows.Append (Row,
                       Database.Values.From_Date_Time ((Date_Part => (Year => Y,
                       Month => Mo,
                       Day => D),
                       Time_Part => (Hour => H,
                       Minute => Mi,
                       Second => S,
                       Nanosecond => N))));
                  end;
               when Database.Types.Duration_Value =>
                  declare
                     S64 : Long_Long_Integer;
                     N   : Natural;
                  begin
                     if not Read_I64 (Data, Pos, Last, S64)
                       or else not Read_U32 (Data, Pos, Last, N)
                     then
                        return Database.Status.Failure
                          (Database.Status.Serialization_Error, "truncated duration");
                     end if;
                     Database.Rows.Append
                       (Row,
                        Database.Values.From_Duration
                          ((Seconds => S64, Nanoseconds => N)));
                  end;
               when Database.Types.UUID_Value =>
                  declare
                     U : Database.UUIDs.UUID;
                  begin
                     if not Need (Pos, 16, Last) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated uuid");
                     end if;
                     for J in U'Range loop
                        U (J) := Database.UUIDs.Byte (Data (Pos));
                        Pos := Pos + 1;
                     end loop;
                     Database.Rows.Append (Row, Database.Values.From_UUID (U));
                  end;
               when Database.Types.Array_Value =>
                  declare
                     S : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
                  begin
                     if not Read_Text (S) then
                        return Database.Status.Failure (Database.Status.Serialization_Error, "truncated array");
                     end if;
                     Database.Rows.Append (Row,
                       Database.Values.From_Array_Text (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (S)));
                  end;
            end case;
         end;
      end loop;
      return Database.Constraints.Validate_Row (Schema, Row);
   exception
      when others =>
         return Database.Status.Failure (Database.Status.Serialization_Error, "malformed serialized record");
   end Deserialize;
end Database.Storage.Record_Format;
