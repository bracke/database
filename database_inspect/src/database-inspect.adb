with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;

with Database.Catalog;
with Database.Date_Time;
with Database.Indexes;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Storage.Pages;
with Database.Storage.Table_Heap;
with Database.Transactions;
with Database.Types;
with Database.UUIDs;
with Database.Values;

package body Database.Inspect is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;

   function Int_Image (Value : Integer) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Integer'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Int_Image;

   function Nat_Image (Value : Natural) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Natural'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Nat_Image;

   function Long_Image (Value : Long_Long_Integer) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Long_Long_Integer'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Long_Image;

   function Float_Image (Value : Long_Float) return Wide_Wide_String is
      Raw : constant Wide_Wide_String := Long_Float'Wide_Wide_Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Float_Image;

   function Kind_Image (Kind : Database.Types.Value_Kind) return Wide_Wide_String is
   begin
      case Kind is
         when Database.Types.Null_Value         => return "null";
         when Database.Types.Boolean_Value      => return "boolean";
         when Database.Types.Integer_Value      => return "integer";
         when Database.Types.Long_Integer_Value => return "long_integer";
         when Database.Types.Float_Value        => return "float";
         when Database.Types.Decimal_Value      => return "decimal";
         when Database.Types.Text_Value         => return "text";
         when Database.Types.Blob_Value         => return "blob";
         when Database.Types.Timestamp_Value    => return "timestamp";
         when Database.Types.Enum_Value         => return "enum";
         when Database.Types.Date_Value         => return "date";
         when Database.Types.Time_Value         => return "time";
         when Database.Types.Date_Time_Value    => return "date_time";
         when Database.Types.Duration_Value     => return "duration";
         when Database.Types.UUID_Value         => return "uuid";
         when Database.Types.Array_Value        => return "array";
      end case;
   end Kind_Image;

   function Index_Kind_Image
     (Kind : Database.Indexes.Index_Kind) return Wide_Wide_String is
   begin
      case Kind is
         when Database.Indexes.Primary_Key_Index => return "primary_key";
         when Database.Indexes.Unique_Index      => return "unique";
         when Database.Indexes.Secondary_Index   => return "secondary";
         when Database.Indexes.Partial_Index     => return "partial";
         when Database.Indexes.Expression_Index  => return "expression";
      end case;
   end Index_Kind_Image;

   function Bool_Image (Value : Boolean) return Wide_Wide_String is
   begin
      if Value then
         return "true";
      end if;
      return "false";
   end Bool_Image;

   function Date_Image (Value : Database.Date_Time.Date) return Wide_Wide_String is
   begin
      return Nat_Image (Natural (Value.Year)) & "-"
        & Nat_Image (Natural (Value.Month)) & "-"
        & Nat_Image (Natural (Value.Day));
   end Date_Image;

   function Time_Image (Value : Database.Date_Time.Time) return Wide_Wide_String is
   begin
      return Nat_Image (Natural (Value.Hour)) & ":"
        & Nat_Image (Natural (Value.Minute)) & ":"
        & Nat_Image (Natural (Value.Second)) & "."
        & Nat_Image (Value.Nanosecond);
   end Time_Image;

   function Value_Image (Value : Database.Values.Value) return Wide_Wide_String is
      use Database.Types;
   begin
      case Value.Kind is
         when Null_Value =>
            return "NULL";
         when Boolean_Value =>
            return Bool_Image (Value.Bool);
         when Integer_Value =>
            return Int_Image (Value.Int);
         when Long_Integer_Value =>
            return Long_Image (Value.Long_Int);
         when Float_Value =>
            return Float_Image (Value.Flt);
         when Decimal_Value =>
            return Long_Image (Value.Dec.Coefficient) & "e-" & Nat_Image (Value.Dec.Scale);
         when Text_Value =>
            return """" & To_Wide_Wide_String (Value.Text) & """";
         when Blob_Value =>
            return "<blob " & Nat_Image (Natural (Value.Blob.Length)) & " bytes>";
         when Timestamp_Value =>
            return Nat_Image (Natural (Value.Time.Year)) & "-"
              & Nat_Image (Natural (Value.Time.Month)) & "-"
              & Nat_Image (Natural (Value.Time.Day)) & "T"
              & Nat_Image (Natural (Value.Time.Hour)) & ":"
              & Nat_Image (Natural (Value.Time.Minute)) & ":"
              & Nat_Image (Natural (Value.Time.Second)) & "."
              & Nat_Image (Value.Time.Nanosecond);
         when Enum_Value =>
            return To_Wide_Wide_String (Value.Enum_Text);
         when Date_Value =>
            return Date_Image (Value.Date);
         when Time_Value =>
            return Time_Image (Value.Clock_Time);
         when Date_Time_Value =>
            return Date_Image (Value.Date_Time.Date_Part) & "T"
              & Time_Image (Value.Date_Time.Time_Part);
         when Duration_Value =>
            return Long_Image (Value.Time_Span.Seconds) & "."
              & Nat_Image (Value.Time_Span.Nanoseconds) & "s";
         when UUID_Value =>
            return Database.UUIDs.UUID_To_String (Value.UUID);
         when Array_Value =>
            return To_Wide_Wide_String (Value.Array_Text);
      end case;
   end Value_Image;

   function Row_Image (Row : Database.Rows.Row) return Wide_Wide_String is
      Text : Unbounded_Wide_Wide_String := To_Unbounded_Wide_Wide_String ("");
   begin
      for I in 0 .. Natural (Row.Values.Length) - 1 loop
         if I > 0 then
            Append (Text, " | ");
         end if;
         Append (Text, Value_Image (Database.Rows.Get (Row, I)));
      end loop;
      return To_Wide_Wide_String (Text);
   end Row_Image;

   procedure Put_Schema
     (Schema : Database.Schema.Table_Schema;
      Put    : not null Output_Procedure) is
   begin
      Put
        ("table " & To_Wide_Wide_String (Schema.Name)
         & " id=" & Nat_Image (Schema.Table_Id)
         & " version=" & Nat_Image (Schema.Schema_Version)
         & " heap_first_page=" & Nat_Image (Schema.Heap_First_Page));

      if Schema.Columns.Length = 0 then
         Put ("  columns: none");
      else
         Put ("  columns:");
         for I in 0 .. Natural (Schema.Columns.Length) - 1 loop
            declare
               Column : constant Database.Schema.Column := Schema.Columns.Element (I);
            begin
               Put
                 ("    " & Nat_Image (Column.Id)
                  & " " & To_Wide_Wide_String (Column.Name)
                  & " " & Kind_Image (Column.Kind)
                  & " nullable=" & Bool_Image (Column.Nullable)
                  & " primary_key=" & Bool_Image (Column.Primary_Key));
            end;
         end loop;
      end if;

      if Schema.Indexes.Length > 0 then
         Put ("  indexes:");
         for I in 0 .. Natural (Schema.Indexes.Length) - 1 loop
            declare
               Index : constant Database.Indexes.Index_Metadata :=
                 Schema.Indexes.Element (I);
            begin
               Put
                 ("    " & Nat_Image (Natural (Index.Id))
                  & " " & To_Wide_Wide_String (Index.Name)
                  & " " & Index_Kind_Image (Index.Kind)
                  & " root_page=" & Nat_Image (Natural (Index.Root_Page))
                  & " unique=" & Bool_Image (Index.Unique));
            end;
         end loop;
      end if;
   end Put_Schema;

   function List_Schemas
     (DB  : in out Database.Handle;
      Put : not null Output_Procedure) return Database.Status.Result is
      pragma Unreferenced (DB);
   begin
      for I in 0 .. Database.Catalog.Table_Count - 1 loop
         Put_Schema (Database.Catalog.Table_At (I), Put);
      end loop;

      if Database.Catalog.Table_Count = 0 then
         Put ("no tables");
      end if;

      return Database.Status.Success;
   end List_Schemas;

   procedure Put_Indexes
     (Schema : Database.Schema.Table_Schema;
      Put    : not null Output_Procedure) is
   begin
      Put ("table " & To_Wide_Wide_String (Schema.Name));

      if Schema.Indexes.Length = 0 then
         Put ("  no indexes");
      else
         for I in 0 .. Natural (Schema.Indexes.Length) - 1 loop
            declare
               Index : constant Database.Indexes.Index_Metadata :=
                 Schema.Indexes.Element (I);
            begin
               Put
                 ("  " & Nat_Image (Natural (Index.Id))
                  & " " & To_Wide_Wide_String (Index.Name)
                  & " " & Index_Kind_Image (Index.Kind)
                  & " root_page=" & Nat_Image (Natural (Index.Root_Page))
                  & " unique=" & Bool_Image (Index.Unique));
            end;
         end loop;
      end if;
   end Put_Indexes;

   function List_Indexes
     (DB  : in out Database.Handle;
      Put : not null Output_Procedure) return Database.Status.Result is
      pragma Unreferenced (DB);
   begin
      if Database.Catalog.Table_Count = 0 then
         Put ("no tables");
         return Database.Status.Success;
      end if;

      for I in 0 .. Database.Catalog.Table_Count - 1 loop
         Put_Indexes (Database.Catalog.Table_At (I), Put);
      end loop;

      return Database.Status.Success;
   end List_Indexes;

   function Dump_Schema
     (DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema;
      Put    : not null Output_Procedure;
      Limit  : Natural) return Database.Status.Result is
      Tx     : Database.Transactions.Transaction;
      Cursor : Database.Storage.Table_Heap.Heap_Cursor;
      R      : Database.Status.Result;
      Count  : Natural := 0;
   begin
      Put ("table " & To_Wide_Wide_String (Schema.Name));

      if Schema.Columns.Length > 0 then
         declare
            Header : Unbounded_Wide_Wide_String :=
              To_Unbounded_Wide_Wide_String ("");
         begin
            for I in 0 .. Natural (Schema.Columns.Length) - 1 loop
               if I > 0 then
                  Append (Header, " | ");
               end if;
               Append (Header, To_Wide_Wide_String (Schema.Columns.Element (I).Name));
            end loop;
            Put (To_Wide_Wide_String (Header));
         end;
      end if;

      if Schema.Heap_First_Page =
        Natural (Database.Storage.Pages.Invalid_Page_Id)
      then
         Put ("rows=0");
         return Database.Status.Success;
      end if;

      Database.Transactions.Begin_Read (DB, Tx);
      R := Database.Transactions.Result (Tx);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      R := Database.Storage.Table_Heap.Scan_First
        (Tx,
         DB.File,
         Database.Storage.Pages.Page_Id (Schema.Heap_First_Page),
         Schema,
         Cursor);
      if not Database.Status.Is_Ok (R) then
         Database.Transactions.Rollback (Tx);
         return R;
      end if;

      while Cursor.Has_Row and then Count < Limit loop
         Put (Row_Image (Cursor.Row));
         Count := Count + 1;
         R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Schema, Cursor);
         if not Database.Status.Is_Ok (R) then
            Database.Transactions.Rollback (Tx);
            return R;
         end if;
      end loop;

      Database.Transactions.Commit (Tx);
      Put ("rows=" & Nat_Image (Count));
      return Database.Status.Success;
   end Dump_Schema;

   function Dump_Table
     (DB         : in out Database.Handle;
      Table_Name : Wide_Wide_String;
      Put        : not null Output_Procedure;
      Limit      : Natural := Natural'Last) return Database.Status.Result is
      Schema : Database.Schema.Table_Schema;
      R      : Database.Status.Result;
   begin
      R := Database.Catalog.Find_By_Name (Table_Name, Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Dump_Schema (DB, Schema, Put, Limit);
   end Dump_Table;

   function Dump_All
     (DB    : in out Database.Handle;
      Put   : not null Output_Procedure;
      Limit : Natural := Natural'Last) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      if Database.Catalog.Table_Count = 0 then
         Put ("no tables");
         return Database.Status.Success;
      end if;

      for I in 0 .. Database.Catalog.Table_Count - 1 loop
         if I > 0 then
            Put ("");
         end if;
         R := Dump_Schema (DB, Database.Catalog.Table_At (I), Put, Limit);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end loop;
      return Database.Status.Success;
   end Dump_All;
end Database.Inspect;
