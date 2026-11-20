with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;
with Database.Date_Time;
with Database.Types;
with Database.UUIDs;

package body Database.Indexes.BTree.Nodes is
   use Database.Storage.Pages;
   use Database.Types;
   use type Interfaces.Unsigned_64;

   subtype Bytes is Database.Byte_Array;

   Marker      : constant Bytes := [Character'Pos ('B'), Character'Pos ('P'), Character'Pos ('T'), Character'Pos ('1')];
   Header_Size : constant := 11;
   Leaf_Type   : constant := 0;
   Inner_Type  : constant := 1;

   function To_Bits is new Ada.Unchecked_Conversion (Long_Long_Integer, Interfaces.Unsigned_64);
   function From_Bits is new Ada.Unchecked_Conversion (Interfaces.Unsigned_64, Long_Long_Integer);
   function Float_Bits is new Ada.Unchecked_Conversion (Long_Float, Interfaces.Unsigned_64);
   function Bits_Float is new Ada.Unchecked_Conversion (Interfaces.Unsigned_64, Long_Float);

   ---------------------------------------------------------------------------------------------------------------
   --  Big-endian integers
   ---------------------------------------------------------------------------------------------------------------

   function U64 (Value : Interfaces.Unsigned_64) return Bytes is
      Result : Bytes (0 .. 7);
      V      : Interfaces.Unsigned_64 := Value;
   begin
      for I in reverse Result'Range loop
         Result (I) := Database.Byte (V and 16#FF#);
         V := Interfaces.Shift_Right (V, 8);
      end loop;
      return Result;
   end U64;

   function U32 (Value : Natural) return Bytes is
     [Database.Byte (Value / 16#100_0000# mod 256), Database.Byte (Value / 16#1_0000# mod 256),
      Database.Byte (Value / 16#100# mod 256), Database.Byte (Value mod 256)];

   function U16 (Value : Natural) return Bytes is
     [Database.Byte (Value / 16#100# mod 256), Database.Byte (Value mod 256)];

   function I64 (Value : Long_Long_Integer) return Bytes is (U64 (To_Bits (Value)));

   --  A cursor over an encoded payload; reading past its end is a corrupt node.
   type Reader (Last : Integer) is record
      Data     : Bytes (0 .. Last);
      Position : Natural := 0;
   end record;

   Truncated : exception;

   function Next_Byte (R : in out Reader) return Database.Byte is
   begin
      if R.Position > R.Last then
         raise Truncated;
      end if;
      R.Position := R.Position + 1;
      return R.Data (R.Position - 1);
   end Next_Byte;

   function Read_U16 (R : in out Reader) return Natural is
      High : constant Natural := Natural (Next_Byte (R));
   begin
      return High * 256 + Natural (Next_Byte (R));
   end Read_U16;

   function Read_U32 (R : in out Reader) return Natural is
      Result : Natural := 0;
   begin
      for I in 1 .. 4 loop
         Result := Result * 256 + Natural (Next_Byte (R));
      end loop;
      return Result;
   end Read_U32;

   function Read_U64 (R : in out Reader) return Interfaces.Unsigned_64 is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for I in 1 .. 8 loop
         Result := Interfaces.Shift_Left (Result, 8) or Interfaces.Unsigned_64 (Next_Byte (R));
      end loop;
      return Result;
   end Read_U64;

   function Read_I64 (R : in out Reader) return Long_Long_Integer is (From_Bits (Read_U64 (R)));

   ---------------------------------------------------------------------------------------------------------------
   --  Keys: the kind, then a fixed encoding per kind; text is UTF-8 up to the end of the key
   ---------------------------------------------------------------------------------------------------------------

   function Text_Bytes (Text : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String) return Bytes is
      Encoded : constant String :=
        Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
          (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Text));
      Result  : Bytes (0 .. Encoded'Length - 1);
   begin
      for I in Result'Range loop
         Result (I) := Database.Byte (Character'Pos (Encoded (Encoded'First + I)));
      end loop;
      return Result;
   end Text_Bytes;

   function Date_Bytes (D : Database.Date_Time.Date) return Bytes is (U32 (D.Year) & U32 (D.Month) & U32 (D.Day));

   function Time_Bytes (T : Database.Date_Time.Time) return Bytes is
     (U32 (T.Hour) & U32 (T.Minute) & U32 (T.Second) & U32 (T.Nanosecond));

   function Encode_Key (Key : Database.Values.Value) return Bytes is
      Kind : constant Bytes := [Database.Byte (Value_Kind'Pos (Key.Kind))];
   begin
      case Key.Kind is
         when Boolean_Value => return Kind & [Database.Byte (Boolean'Pos (Key.Bool))];
         when Integer_Value => return Kind & I64 (Long_Long_Integer (Key.Int));
         when Long_Integer_Value => return Kind & I64 (Key.Long_Int);
         when Float_Value => return Kind & U64 (Float_Bits (Key.Flt));
         when Decimal_Value => return Kind & I64 (Key.Dec.Coefficient) & U32 (Key.Dec.Scale);
         when Text_Value => return Kind & Text_Bytes (Key.Text);
         when Enum_Value => return Kind & Text_Bytes (Key.Enum_Text);
         when Timestamp_Value =>
            return Kind & U32 (Key.Time.Year) & U32 (Key.Time.Month) & U32 (Key.Time.Day) & U32 (Key.Time.Hour) &
              U32 (Key.Time.Minute) & U32 (Key.Time.Second) & U32 (Key.Time.Nanosecond);
         when Date_Value => return Kind & Date_Bytes (Key.Date);
         when Time_Value => return Kind & Time_Bytes (Key.Clock_Time);
         when Date_Time_Value => return Kind & Date_Bytes (Key.Date_Time.Date_Part) &
              Time_Bytes (Key.Date_Time.Time_Part);
         when Duration_Value => return Kind & I64 (Key.Time_Span.Seconds) & U32 (Key.Time_Span.Nanoseconds);
         when UUID_Value =>
            declare
               Result : Bytes (0 .. 15);
            begin
               for I in Result'Range loop
                  Result (I) := Database.Byte (Key.UUID (I));
               end loop;
               return Kind & Result;
            end;
         when Null_Value | Blob_Value | Array_Value =>
            raise Standard.Constraint_Error with "value kind cannot be an index key";
      end case;
   end Encode_Key;

   function Key_Size (Key : Database.Values.Value) return Natural is (Encode_Key (Key)'Length);

   --  Decode the text that fills the rest of a key of Length bytes that started at Start.
   function Read_Text (R : in out Reader; Start, Length : Natural) return Wide_Wide_String is
      Count   : constant Natural := Start + Length - R.Position;
      Encoded : String (1 .. Count);
   begin
      for I in Encoded'Range loop
         Encoded (I) := Character'Val (Next_Byte (R));
      end loop;
      return Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Encoded);
   end Read_Text;

   function Read_Date (R : in out Reader) return Database.Date_Time.Date is
      Year  : constant Natural := Read_U32 (R);
      Month : constant Natural := Read_U32 (R);
   begin
      return (Year => Year, Month => Month, Day => Read_U32 (R));
   end Read_Date;

   function Read_Time (R : in out Reader) return Database.Date_Time.Time is
      Hour   : constant Natural := Read_U32 (R);
      Minute : constant Natural := Read_U32 (R);
      Second : constant Natural := Read_U32 (R);
   begin
      return (Hour => Hour, Minute => Minute, Second => Second, Nanosecond => Read_U32 (R));
   end Read_Time;

   function Decode_Key_Value (R : in out Reader; Length : Natural) return Database.Values.Value is
      Start : constant Natural := R.Position;
      Code  : constant Natural := Natural (Next_Byte (R));
   begin
      if Code > Value_Kind'Pos (Value_Kind'Last) then
         raise Truncated;
      end if;
      case Value_Kind'Val (Code) is
         when Boolean_Value => return Database.Values.From_Boolean (Next_Byte (R) /= 0);
         when Integer_Value => return Database.Values.From_Integer (Integer (Read_I64 (R)));
         when Long_Integer_Value => return Database.Values.From_Long_Integer (Read_I64 (R));
         when Float_Value => return Database.Values.From_Float (Bits_Float (Read_U64 (R)));
         when Decimal_Value =>
            declare
               Coefficient : constant Long_Long_Integer := Read_I64 (R);
            begin
               return Database.Values.From_Decimal ((Coefficient => Coefficient, Scale => Read_U32 (R)));
            end;
         when Text_Value => return Database.Values.From_Text (Read_Text (R, Start, Length));
         when Enum_Value => return Database.Values.From_Enum (Read_Text (R, Start, Length));
         when Timestamp_Value =>
            declare
               Stamp : Database.Types.Timestamp;
            begin
               Stamp.Year := Read_U32 (R);
               Stamp.Month := Read_U32 (R);
               Stamp.Day := Read_U32 (R);
               Stamp.Hour := Read_U32 (R);
               Stamp.Minute := Read_U32 (R);
               Stamp.Second := Read_U32 (R);
               Stamp.Nanosecond := Read_U32 (R);
               return Database.Values.From_Timestamp (Stamp);
            end;
         when Date_Value => return Database.Values.From_Date (Read_Date (R));
         when Time_Value => return Database.Values.From_Time (Read_Time (R));
         when Date_Time_Value =>
            declare
               Day : constant Database.Date_Time.Date := Read_Date (R);
            begin
               return Database.Values.From_Date_Time ((Date_Part => Day, Time_Part => Read_Time (R)));
            end;
         when Duration_Value =>
            declare
               Seconds : constant Long_Long_Integer := Read_I64 (R);
            begin
               return Database.Values.From_Duration ((Seconds => Seconds, Nanoseconds => Read_U32 (R)));
            end;
         when UUID_Value =>
            declare
               Id : Database.UUIDs.UUID;
            begin
               for I in Id'Range loop
                  Id (I) := Database.UUIDs.Byte (Next_Byte (R));
               end loop;
               return Database.Values.From_UUID (Id);
            end;
         when Null_Value | Blob_Value | Array_Value =>
            raise Truncated;
      end case;
   end Decode_Key_Value;

   --  Decode a key of Length bytes; a key whose encoding is shorter or longer than its length is corrupt.
   function Decode_Key (R : in out Reader; Length : Natural) return Database.Values.Value is
      Start : constant Natural := R.Position;
      Key   : constant Database.Values.Value := Decode_Key_Value (R, Length);
   begin
      if R.Position /= Start + Length then
         raise Truncated;
      end if;
      return Key;
   end Decode_Key;

   ---------------------------------------------------------------------------------------------------------------
   --  Nodes
   ---------------------------------------------------------------------------------------------------------------

   function Compare
     (Left_Key  : Database.Values.Value;
      Left_Ref  : Database.Indexes.Row_Reference;
      Right_Key : Database.Values.Value;
      Right_Ref : Database.Indexes.Row_Reference;
      Order     : out Database.Indexes.Ordering) return Database.Status.Result
   is
      R : constant Database.Status.Result := Database.Indexes.Compare (Left_Key, Right_Key, Order);
   begin
      if Database.Status.Is_Ok (R) and then Order = Database.Indexes.Equal then
         Order :=
           (if Left_Ref.Page /= Right_Ref.Page
            then (if Left_Ref.Page < Right_Ref.Page then Database.Indexes.Less else Database.Indexes.Greater)
            elsif Left_Ref.Slot_Offset /= Right_Ref.Slot_Offset
            then (if Left_Ref.Slot_Offset < Right_Ref.Slot_Offset then Database.Indexes.Less
                  else Database.Indexes.Greater)
            else Database.Indexes.Equal);
      end if;
      return R;
   end Compare;

   function Item_Size (N : Node; Entry_Item : Item) return Natural is
     (2 + Entry_Item.Key_Length + 8 + (if N.Leaf then 0 else 4));

   function Fits (N : Node) return Boolean is
      Total : Natural := Header_Size;
   begin
      for Entry_Item of N.Items loop
         Total := Total + Item_Size (N, Entry_Item);
         if Total > Payload_Capacity then
            return False;
         end if;
      end loop;
      return True;
   end Fits;

   function Encode (N : Node) return Bytes is
      Result   : Bytes (0 .. Payload_Capacity - 1);
      Position : Natural := 0;

      procedure Put (Data : Bytes) is
      begin
         Result (Position .. Position + Data'Length - 1) := Data;
         Position := Position + Data'Length;
      end Put;
   begin
      Put (Marker);
      Put ([Database.Byte (if N.Leaf then Leaf_Type else Inner_Type)]);
      Put (U16 (Natural (N.Items.Length)));
      Put (U32 (Natural (N.First)));
      for Entry_Item of N.Items loop
         declare
            Key : constant Bytes := Encode_Key (Entry_Item.Key);
         begin
            Put (U16 (Key'Length));
            Put (Key);
            Put (U32 (Natural (Entry_Item.Ref.Page)));
            Put (U32 (Entry_Item.Ref.Slot_Offset));
            if not N.Leaf then
               Put (U32 (Natural (Entry_Item.Child)));
            end if;
         end;
      end loop;
      return Result (0 .. Position - 1);
   end Encode;

   --  Read a node page, which is either kind; the cached read of the right kind is the common case.
   function Read_Node_Page
     (F    : in out Database.Storage.File_IO.File_Handle;
      Id   : Page_Id;
      Page : out Database.Storage.Pages.Page) return Database.Status.Result
   is
      R : constant Database.Status.Result := Database.Storage.File_IO.Read_Page (F, Id, BTree_Leaf_Page, Page);
   begin
      if Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Database.Storage.File_IO.Read_Page (F, Id, BTree_Internal_Page, Page);
   end Read_Node_Page;

   function Is_Built (F : in out Database.Storage.File_IO.File_Handle; Id : Page_Id) return Boolean is
      Page : Database.Storage.Pages.Page;
   begin
      if Id = Invalid_Page_Id or else not Database.Status.Is_Ok (Read_Node_Page (F, Id, Page)) then
         return False;
      end if;
      declare
         Data : constant Bytes := Payload (Page);
      begin
         return Data'Length >= Header_Size and then Data (Data'First .. Data'First + 3) = Marker;
      end;
   end Is_Built;

   function Load
     (F  : in out Database.Storage.File_IO.File_Handle;
      Id : Page_Id;
      N  : out Node) return Database.Status.Result
   is
      Page : Database.Storage.Pages.Page;
      R    : constant Database.Status.Result := Read_Node_Page (F, Id, Page);
   begin
      N := (Id => Id, others => <>);
      if not Database.Status.Is_Ok (R) then
         return Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree node page is invalid");
      end if;
      declare
         Data   : constant Bytes := Payload (Page);
         Cursor : Reader (Data'Length - 1);
      begin
         Cursor.Data := Data;
         if Data'Length < Header_Size or else Data (Data'First .. Data'First + 3) /= Marker then
            return Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree node has no format marker");
         end if;
         Cursor.Position := 4;
         N.Leaf := Next_Byte (Cursor) = Leaf_Type;
         if N.Leaf /= (Get_Kind (Page) = BTree_Leaf_Page) then
            return Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree node type contradicts its page");
         end if;
         declare
            Count : constant Natural := Read_U16 (Cursor);
         begin
            N.First := Page_Id (Read_U32 (Cursor));
            N.Next := (if N.Leaf then Get_Next (Page) else Invalid_Page_Id);
            for I in 1 .. Count loop
               declare
                  Length     : constant Natural := Read_U16 (Cursor);
                  Entry_Item : Item;
               begin
                  Entry_Item.Key := Decode_Key (Cursor, Length);
                  Entry_Item.Key_Length := Length;
                  Entry_Item.Ref.Page := Page_Id (Read_U32 (Cursor));
                  Entry_Item.Ref.Slot_Offset := Read_U32 (Cursor);
                  if not N.Leaf then
                     Entry_Item.Child := Page_Id (Read_U32 (Cursor));
                  end if;
                  N.Items.Append (Entry_Item);
               end;
            end loop;
         end;
      end;
      return Database.Status.Success;
   exception
      when Truncated | Standard.Constraint_Error | Ada.Strings.UTF_Encoding.Encoding_Error =>
         return Database.Status.Failure (Database.Status.Corrupt_Index, "B+ tree node encoding is invalid");
   end Load;

   function Store
     (Tx : in out Database.Transactions.Transaction;
      N  : Node) return Database.Status.Result
   is
      Page : Database.Storage.Pages.Page;
   begin
      Initialize (Page, N.Id, (if N.Leaf then BTree_Leaf_Page else BTree_Internal_Page),
                  (if N.Leaf then N.Next else Invalid_Page_Id));
      Set_Payload (Page, Encode (N));
      return Database.Transactions.Write_Page (Tx, Page);
   end Store;
end Database.Indexes.BTree.Nodes;
