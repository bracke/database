with Database.Date_Time;
with Database.Schema;
with Database.Types;
with Database.Values;
with Database.UUIDs;
with Ada.Strings.Wide_Wide_Unbounded;
with Interfaces;

package body Database.Randomized is
   use type Interfaces.Unsigned_64;

   Multiplier : constant Interfaces.Unsigned_64 := 6364136223846793005;
   Increment  : constant Interfaces.Unsigned_64 := 1442695040888963407;

   function Natural_Image (Value : Natural) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Natural'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Natural_Image;

   procedure Step (G : in out Generator) is
   begin
      G.State := G.State * Multiplier + Increment;
   end Step;

   procedure Reset (G : out Generator; Seed : Natural) is
   begin
      G.Initial_Seed := Seed;
      G.State := Interfaces.Unsigned_64 (Seed);
      if G.State = 0 then
         G.State := 1;
      end if;
   end Reset;

   function Seed (G : Generator) return Natural is (G.Initial_Seed);

   function Next_Natural (G : in out Generator; Upper_Bound : Positive) return Natural is
   begin
      Step (G);
      return Natural (G.State mod Interfaces.Unsigned_64 (Upper_Bound));
   end Next_Natural;

   function Next_Boolean (G : in out Generator) return Boolean is
   begin
      return Next_Natural (G, 2) = 1;
   end Next_Boolean;

   function Next_Operation (G : in out Generator) return Operation_Kind is
      N : constant Natural := Next_Natural (G, Operation_Kind'Pos (Operation_Kind'Last) + 1);
   begin
      return Operation_Kind'Val (N);
   end Next_Operation;

   function Next_Integer_Value (G : in out Generator) return Database.Values.Value is
   begin
      return Database.Values.From_Integer (Integer (Next_Natural (G, 1_000_000)) - 500_000);
   end Next_Integer_Value;

   function Next_Unicode_String (G : in out Generator; Max_Length : Natural) return Wide_Wide_String is
      Len : constant Natural := (if Max_Length = 0 then 0 else Next_Natural (G, Max_Length + 1));
      Result : Wide_Wide_String (1 .. Len);
      Alphabet : constant Wide_Wide_String := "Ada-DB-äöü-東京-🙂";
   begin
      for I in Result'Range loop
         Result (I) := Alphabet (Alphabet'First + Next_Natural (G, Alphabet'Length));
      end loop;
      return Result;
   end Next_Unicode_String;

   function Next_Value_Kind (G : in out Generator) return Database.Types.Value_Kind is
      --  Exclude Null_Value here;
      --  fuzzers can still generate NULL explicitly.
      First : constant Natural := Database.Types.Value_Kind'Pos (Database.Types.Boolean_Value);
      Last  : constant Natural := Database.Types.Value_Kind'Pos (Database.Types.Array_Value);
   begin
      return Database.Types.Value_Kind'Val (First + Next_Natural (G, Last - First + 1));
   end Next_Value_Kind;

   function Next_Blob (G : in out Generator; Max_Length : Natural) return Database.Values.Byte_Vectors.Vector is
      Len : constant Natural := (if Max_Length = 0 then 0 else Next_Natural (G, Max_Length + 1));
      V : Database.Values.Byte_Vectors.Vector;
   begin
      for I in 1 .. Len loop
         V.Append (Database.Values.Byte (Next_Natural (G, 256)));
      end loop;
      return V;
   end Next_Blob;

   function Next_Date (G : in out Generator) return Database.Date_Time.Date is
      Year : constant Integer := 1970 + Integer (Next_Natural (G, 130));
      Month : constant Integer := 1 + Integer (Next_Natural (G, 12));
      Day : constant Integer := 1 + Integer (Next_Natural (G, 28));
   begin
      return (Year => Year, Month => Month, Day => Day);
   end Next_Date;

   function Next_Time (G : in out Generator) return Database.Date_Time.Time is
   begin
      return
        (Hour       => Integer (Next_Natural (G, 24)),
         Minute     => Integer (Next_Natural (G, 60)),
         Second     => Integer (Next_Natural (G, 60)),
         Nanosecond => Next_Natural (G, 1_000_000_000));
   end Next_Time;

   function Next_Date_Time (G : in out Generator) return Database.Date_Time.Date_Time is
   begin
      return (Date_Part => Next_Date (G), Time_Part => Next_Time (G));
   end Next_Date_Time;

   function Next_UUID (G : in out Generator) return Database.UUIDs.UUID is
      U : Database.UUIDs.UUID := (others => 0);
   begin
      for I in U'Range loop
         U (I) := Database.UUIDs.Byte (Next_Natural (G, 256));
      end loop;
      --  Set version/variant bits for deterministic RFC-4122-shaped values.
      U (6) := (U (6) mod 16) + 16#40#;
      U (8) := (U (8) mod 64) + 16#80#;
      return U;
   end Next_UUID;

   function Next_Decimal (G : in out Generator) return Database.Types.Decimal is
   begin
      return
        (Coefficient => Long_Long_Integer (Integer (Next_Natural (G, 2_000_001)) - 1_000_000),
         Scale       => Natural (Next_Natural (G, 6)));
   end Next_Decimal;

   function Next_Enum_Literal (G : in out Generator) return Wide_Wide_String is
      N : constant Natural := Next_Natural (G, 8);
   begin
      return "Enum_" & Natural_Image (N);
   end Next_Enum_Literal;

   function Next_Bounded_Text
     (G          : in out Generator;
      Max_Length : Natural) return Database.Values.Value is
   begin
      return Database.Values.From_Text (Next_Unicode_String (G, Max_Length));
   end Next_Bounded_Text;

   function Next_Value_For_Kind
     (G    : in out Generator;
      Kind : Database.Types.Value_Kind) return Database.Values.Value is
   begin
      case Kind is
         when Database.Types.Null_Value =>
            return Database.Values.Null_Value;
         when Database.Types.Boolean_Value =>
            return Database.Values.From_Boolean (Next_Boolean (G));
         when Database.Types.Integer_Value =>
            return Next_Integer_Value (G);
         when Database.Types.Long_Integer_Value =>
            return Database.Values.From_Long_Integer
              (Long_Long_Integer (Integer (Next_Natural (G, 1_000_000)) - 500_000));
         when Database.Types.Float_Value =>
            return Database.Values.From_Float
              (Long_Float (Integer (Next_Natural (G, 100_000))) / 100.0);
         when Database.Types.Decimal_Value =>
            return Database.Values.From_Decimal (Next_Decimal (G));
         when Database.Types.Text_Value =>
            return Database.Values.From_Text (Next_Unicode_String (G, 32));
         when Database.Types.Blob_Value =>
            return Database.Values.From_Blob (Next_Blob (G, 32));
         when Database.Types.Timestamp_Value =>
            return Database.Values.From_Timestamp
              ((Year       => 1970 + Integer (Next_Natural (G, 130)),
                Month      => 1 + Integer (Next_Natural (G, 12)),
                Day        => 1 + Integer (Next_Natural (G, 28)),
                Hour       => Integer (Next_Natural (G, 24)),
                Minute     => Integer (Next_Natural (G, 60)),
                Second     => Integer (Next_Natural (G, 60)),
                Nanosecond => Next_Natural (G, 1_000_000_000)));
         when Database.Types.Enum_Value =>
            return Database.Values.From_Enum (Next_Enum_Literal (G));
         when Database.Types.Date_Value =>
            return Database.Values.From_Date (Next_Date (G));
         when Database.Types.Time_Value =>
            return Database.Values.From_Time (Next_Time (G));
         when Database.Types.Date_Time_Value =>
            return Database.Values.From_Date_Time (Next_Date_Time (G));
         when Database.Types.Duration_Value =>
            return Database.Values.From_Duration
              ((Seconds => Long_Long_Integer (Integer (Next_Natural (G, 1_000_000)) - 500_000),
                Nanoseconds => Next_Natural (G, 1_000_000_000)));
         when Database.Types.UUID_Value =>
            return Database.Values.From_UUID (Next_UUID (G));
         when Database.Types.Array_Value =>
            return Database.Values.From_Array_Text ("[" & Next_Unicode_String (G, 12) & "]");
      end case;
   end Next_Value_For_Kind;

   function Next_Schema
     (G           : in out Generator;
      Name        : Wide_Wide_String;
      Max_Columns : Positive) return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
      Count : constant Positive := Positive (1 + Next_Natural (G, Max_Columns));
   begin
      S.Name := Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String (Name);
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, Nullable => False, Primary_Key => True);
      for I in 2 .. Count loop
         declare
            K : constant Database.Types.Value_Kind := Next_Value_Kind (G);
         begin
            Database.Schema.Add_Column
              (S,
               "c" & Natural_Image (I),
               K,
               Nullable => Next_Boolean (G),
               Primary_Key => False);
         end;
      end loop;
      return S;
   end Next_Schema;

   function Next_Predicate_Kind (G : in out Generator) return Predicate_Kind is
      N : constant Natural := Next_Natural (G, Predicate_Kind'Pos (Predicate_Kind'Last) + 1);
   begin
      return Predicate_Kind'Val (N);
   end Next_Predicate_Kind;

   function Next_Index_Definition
     (G            : in out Generator;
      Column_Count : Positive) return Index_Definition is
   begin
      return
        (Column_Id => 1 + Next_Natural (G, Column_Count),
         Unique    => Next_Boolean (G),
         Partial   => Next_Boolean (G));
   end Next_Index_Definition;

   function Next_Foreign_Key_Graph
     (G             : in out Generator;
      Table_Count   : Positive;
      Edges         : Positive) return Foreign_Key_Graph is
      Result : Foreign_Key_Graph (1 .. Edges);
   begin
      for I in Result'Range loop
         Result (I)  :=
           (From_Table  => 1 + Next_Natural (G, Table_Count),
            To_Table    => 1 + Next_Natural (G, Table_Count),
            From_Column => 1 + Next_Natural (G, 4),
            To_Column   => 1 + Next_Natural (G, 4));
      end loop;
      return Result;
   end Next_Foreign_Key_Graph;
end Database.Randomized;
