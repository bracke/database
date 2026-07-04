with Ada.Containers;
with Database.Transactions;
with Database.Status;
with Database.Catalog;
with Database.Schema;
with Database.Values;
with Database.UUIDs;
with Database.Rows;
with Database.Types;
with Database.Indexes;
with Database.Indexes.BTree;
with Database.Storage.Table_Heap;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Pages;
with Database.Check;
with Database.Full_Text;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Characters.Conversions;
with Ada.Strings.Wide_Wide_Unbounded;
with Interfaces;
with Database.Metrics;
with Database.Fault_Hooks;
with Database.Foreign_Keys;
with Database.Check_Constraints;
with Database.Generated_Columns;
with Database.Views;
with Database.Materialized_Views;
with Database.Expressions;
with Database.Extensions;
with Database.Extension_Metadata;
with Database.Queries;

package body Database.Import is
   use type Database.Types.Value_Kind;
   use Ada.Streams;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Interfaces.Unsigned_64;

   Magic_20 : constant Wide_Wide_String := "DATABASE_LOGICAL_EXPORT_20";
   Magic_26 : constant Wide_Wide_String := "DATABASE_LOGICAL_EXPORT_26";
   Current_Relational_Metadata_Section : constant Wide_Wide_String :=
     "RELATIONAL_METADATA_V1";
   Legacy_Relational_Metadata_Section : constant Wide_Wide_String :=
     "PHASE18_METADATA_V1";

   function Read_Byte (F : in out Ada.Streams.Stream_IO.File_Type; B : out Natural) return Boolean is
      S : Stream_Element_Array (1 .. 1);
      Last : Stream_Element_Offset;
   begin
      Ada.Streams.Stream_IO.Read (F, S, Last);
      if Last /= 1 then
         return False;
      end if;
      B := Natural (S (1));
      return True;
   exception
      when others =>
         return False;
   end Read_Byte;

   function Read_U32 (F : in out Ada.Streams.Stream_IO.File_Type; V : out Natural) return Boolean is
      B0, B1, B2, B3 : Natural;
   begin
      if not Read_Byte (F, B0) or else not Read_Byte (F, B1)
        or else not Read_Byte (F, B2) or else not Read_Byte (F, B3)
      then
         return False;
      end if;
      V := B0 * 16#1000000# + B1 * 16#10000# + B2 * 16#100# + B3;
      return True;
   end Read_U32;

   function Read_I64 (F : in out Ada.Streams.Stream_IO.File_Type; V : out Long_Long_Integer) return Boolean is
      U : Interfaces.Unsigned_64 := 0;
      B : Natural;
      Sign_Bit : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (2) ** 63;
   begin
      for I in 1 .. 8 loop
         if not Read_Byte (F, B) then
            return False;
         end if;
         U := U * 256 + Interfaces.Unsigned_64 (B);
      end loop;

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
   exception
      when others =>
         return False;
   end Read_I64;

   function Read_Boolean (F : in out Ada.Streams.Stream_IO.File_Type; B : out Boolean) return Boolean is
      N : Natural;
   begin
      if not Read_Byte (F, N) then
         return False;
      end if;
      if N > 1 then
         return False;
      end if;
      B := N = 1;
      return True;
   end Read_Boolean;

   function Read_Text
     (F : in out Ada.Streams.Stream_IO.File_Type;
      S : out Unbounded_Wide_Wide_String) return Boolean
   is
      Len : Natural;
      Code : Natural;
   begin
      if not Read_U32 (F, Len) then
         return False;
      end if;
      declare
         T : Wide_Wide_String (1 .. Len);
      begin
         for I in T'Range loop
            if not Read_U32 (F, Code) then
               return False;
            end if;
            if Code > Wide_Wide_Character'Pos (Wide_Wide_Character'Last) then
               return False;
            end if;
            T (I) := Wide_Wide_Character'Val (Code);
         end loop;
         S := To_Unbounded_Wide_Wide_String (T);
         return True;
      end;
   exception
      when others =>
         return False;
   end Read_Text;

   function Read_Value
     (F : in out Ada.Streams.Stream_IO.File_Type;
      V : out Database.Values.Value) return Boolean
   is
      Tag : Natural;
   begin
      if not Read_Byte (F, Tag) then
         return False;
      end if;
      if Tag > Database.Types.Value_Kind'Pos (Database.Types.Value_Kind'Last) then
         return False;
      end if;
      case Database.Types.Value_Kind'Val (Tag) is
         when Database.Types.Null_Value =>
            V := Database.Values.Null_Value;
         when Database.Types.Boolean_Value =>
            declare
               B : Boolean;
            begin
               if not Read_Boolean (F, B) then
                  return False;
               end if;
               V := Database.Values.From_Boolean (B);
            end;
         when Database.Types.Integer_Value =>
            declare
               I : Long_Long_Integer;
            begin
               if not Read_I64 (F, I) then
                  return False;
               end if;
               V := Database.Values.From_Integer (Integer (I));
            end;
         when Database.Types.Long_Integer_Value =>
            declare
               I : Long_Long_Integer;
            begin
               if not Read_I64 (F, I) then
                  return False;
               end if;
               V := Database.Values.From_Long_Integer (I);
            end;
         when Database.Types.Float_Value =>
            declare
               S : Unbounded_Wide_Wide_String;
            begin
               if not Read_Text (F, S) then
                  return False;
               end if;
               V := Database.Values.From_Float
                 (Long_Float'Wide_Wide_Value (To_Wide_Wide_String (S)));
            end;
         when Database.Types.Decimal_Value =>
            declare
               C : Long_Long_Integer;
            Scale : Natural;
            begin
               if not Read_I64 (F, C) or else not Read_U32 (F, Scale) then
                  return False;
               end if;
               V := Database.Values.From_Decimal ((Coefficient => C, Scale => Scale));
            end;
         when Database.Types.Text_Value =>
            declare
               S : Unbounded_Wide_Wide_String;
            begin
               if not Read_Text (F, S) then
                  return False;
               end if;
               V := Database.Values.From_Text (To_Wide_Wide_String (S));
            end;
         when Database.Types.Blob_Value =>
            declare
               Len, B : Natural;
            Bytes : Database.Values.Byte_Vectors.Vector;
            begin
               if not Read_U32 (F, Len) then
                  return False;
               end if;
               for I in 1 .. Len loop
                  if not Read_Byte (F, B) then
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
               if not Read_U32 (F, Y) or else not Read_U32 (F, Mo)
                 or else not Read_U32 (F, D) or else not Read_U32 (F, H)
                 or else not Read_U32 (F, Mi) or else not Read_U32 (F, S)
                 or else not Read_U32 (F, N)
               then
                  return False;
               end if;
               V := Database.Values.From_Timestamp
                 ((Year => Y, Month => Mo, Day => D,
                   Hour => H, Minute => Mi, Second => S, Nanosecond => N));
            end;
         when Database.Types.Enum_Value =>
            declare
               S : Unbounded_Wide_Wide_String;
            begin
               if not Read_Text (F, S) then
                  return False;
               end if;
               V := Database.Values.From_Enum (To_Wide_Wide_String (S));
            end;
         when Database.Types.Date_Value =>
            declare
               Y, Mo, D : Natural;
         begin
            if not Read_U32  (F,
           Y) or else not Read_U32 (F,
           Mo) or else not Read_U32 (F,
           D) then
              return False;
           end if;
           V := Database.Values.From_Date ((Year => Y,
           Month => Mo,
           Day => D));
           end;
         when Database.Types.Time_Value =>
            declare
               H, Mi, S2, N : Natural;
         begin
            if not Read_U32  (F,
           H) or else not Read_U32 (F,
           Mi) or else not Read_U32 (F,
           S2) or else not Read_U32 (F,
           N) then
              return False;
           end if;
           V := Database.Values.From_Time ((Hour => H,
           Minute => Mi,
           Second => S2,
           Nanosecond => N));
           end;
         when Database.Types.Date_Time_Value =>
            declare
               Y, Mo, D, H, Mi, S2, N : Natural;
         begin
            if not Read_U32  (F,
           Y) or else not Read_U32 (F,
           Mo) or else not Read_U32 (F,
           D) or else not Read_U32 (F,
           H) or else not Read_U32 (F,
           Mi) or else not Read_U32 (F,
           S2) or else not Read_U32 (F,
           N) then
              return False;
           end if;
           V := Database.Values.From_Date_Time ((Date_Part => (Year => Y,
           Month => Mo,
           Day => D),
           Time_Part => (Hour => H,
           Minute => Mi,
           Second => S2,
           Nanosecond => N)));
           end;
         when Database.Types.Duration_Value =>
            declare
               S64 : Long_Long_Integer;
         N : Natural;
         begin
            if not Read_I64  (F,
           S64) or else not Read_U32 (F,
           N) then
              return False;
           end if;
           V := Database.Values.From_Duration ((Seconds => S64,
           Nanoseconds => N));
           end;
         when Database.Types.UUID_Value =>
            declare
               Uuid : Database.UUIDs.UUID;
         B : Natural;
         begin for J in Uuid'Range loop if not Read_Byte  (F,
           B) then
              return False;
           end if;
           Uuid (J) := Database.UUIDs.Byte (B);
           end loop;
           V := Database.Values.From_UUID (Uuid);
           end;
         when Database.Types.Array_Value =>
            declare
               S : Unbounded_Wide_Wide_String;
         begin
            if not Read_Text  (F,
           S) then
              return False;
           end if;
           V := Database.Values.From_Array_Text (To_Wide_Wide_String (S));
           end;
      end case;
      return True;
   exception
      when others =>
         return False;
   end Read_Value;

   function Read_Row
     (F : in out Ada.Streams.Stream_IO.File_Type;
      Row : out Database.Rows.Row) return Boolean
   is
      Count : Natural;
      V : Database.Values.Value;
   begin
      Row.Values.Clear;
      if not Read_U32 (F, Count) then
         return False;
      end if;
      for I in 1 .. Count loop
         if not Read_Value (F, V) then
            return False;
         end if;
         Database.Rows.Append (Row, V);
      end loop;
      return True;
   end Read_Row;

   function Read_Index
     (F : in out Ada.Streams.Stream_IO.File_Type;
      IX : out Database.Indexes.Index_Metadata) return Boolean
   is
      N, Count : Natural;
      B : Boolean;
      Name : Unbounded_Wide_Wide_String;
   begin
      IX := (others => <>);
      if not Read_U32 (F, N) then
         return False;
      end if;
      IX.Id := Database.Indexes.Index_Id (N);
      if not Read_U32 (F, IX.Table_Id) then
         return False;
      end if;
      if not Read_Text (F, Name) then
         return False;
      end if;
      IX.Name := Name;
      if not Read_Byte  (F,
        N) or else N > Database.Indexes.Index_Kind'Pos (Database.Indexes.Index_Kind'Last) then
           return False;
        end if;
      IX.Kind := Database.Indexes.Index_Kind'Val (N);
      if not Read_Boolean (F, IX.Unique) then
         return False;
      end if;
      if not Read_U32 (F, IX.Column_Id) then
         return False;
      end if;
      if not Read_Byte  (F,
        N) or else N > Database.Types.Value_Kind'Pos (Database.Types.Value_Kind'Last) then
           return False;
        end if;
      IX.Key_Kind := Database.Types.Value_Kind'Val (N);
      if not Read_U32 (F, Count) then
         return False;
      end if;
      for I in 1 .. Count loop
         if not Read_U32 (F, N) then
            return False;
         end if;
         IX.Column_Ids.Append (N);
      end loop;
      if not Read_Boolean (F, B) then
         return False;
      end if;
      IX.Has_Predicate := B;
      if not Read_Boolean (F, B) then
         return False;
      end if;
      IX.Has_Expression := B;
      IX.Root_Page := Database.Storage.Pages.Invalid_Page_Id;
      return True;
   end Read_Index;

   function Read_Schema
     (F : in out Ada.Streams.Stream_IO.File_Type;
      S : out Database.Schema.Table_Schema) return Boolean
   is
      N, Count : Natural;
      Name : Unbounded_Wide_Wide_String;
      B : Boolean;
      IX : Database.Indexes.Index_Metadata;
   begin
      S := (others => <>);
      if not Read_U32 (F, S.Table_Id) then
         return False;
      end if;
      if not Read_U32 (F, S.Schema_Version) then
         return False;
      end if;
      if not Read_U32 (F, S.Next_Column_Id) then
         return False;
      end if;
      if not Read_Text (F, Name) then
         return False;
      end if;
      S.Name := Name;
      if not Read_U32 (F, Count) then
         return False;
      end if;
      for I in 1 .. Count loop
         declare
            C : Database.Schema.Column;
         begin
            if not Read_U32 (F, C.Id) then
               return False;
            end if;
            if not Read_Text (F, C.Name) then
               return False;
            end if;
            if not Read_Byte  (F,
              N) or else N > Database.Types.Value_Kind'Pos (Database.Types.Value_Kind'Last) then
                 return False;
              end if;
            C.Kind := Database.Types.Value_Kind'Val (N);
            if not Read_Boolean (F, B) then
               return False;
            end if;
            C.Nullable := B;
            if not Read_Boolean (F, B) then
               return False;
            end if;
            C.Primary_Key := B;
            S.Columns.Append (C);
         end;
      end loop;
      if not Read_U32 (F, Count) then
         return False;
      end if;
      for I in 1 .. Count loop
         if not Read_U32 (F, N) then
            return False;
         end if;
         S.Primary_Key_Columns.Append (N);
      end loop;
      if not Read_U32 (F, Count) then
         return False;
      end if;
      for I in 1 .. Count loop
         if not Read_Index (F, IX) then
            return False;
         end if;
         S.Indexes.Append (IX);
      end loop;
      S.Heap_First_Page := 0;
      S.Primary_Index_Root := 0;
      return True;
   end Read_Schema;

   function Read_Relational_Metadata
     (F  : in out Ada.Streams.Stream_IO.File_Type;
      DB : in out Database.Handle) return Database.Status.Result
   is
      Section : Unbounded_Wide_Wide_String;
      Count, N, Table_Id : Natural;
      Name, Image, Compat : Unbounded_Wide_Wide_String;
      R : Database.Status.Result;
   begin
      if not Read_Text (F, Section)
        or else
          (To_Wide_Wide_String (Section) /= Current_Relational_Metadata_Section
           and then To_Wide_Wide_String (Section) /= Legacy_Relational_Metadata_Section)
      then
         return Database.Status.Failure (Database.Status.Import_Error, "missing relational metadata section");
      end if;

      if not Read_U32 (F, Count) then
         return Database.Status.Failure (Database.Status.Import_Error, "missing foreign-key metadata count");
      end if;
      for I in 1 .. Count loop
         declare
            FK : Database.Foreign_Keys.Foreign_Key_Definition;
            Col_Count, Action : Natural;
         begin
            if not Read_Text  (F,
              Name) or else not Read_U32 (F,
              FK.Referencing_Table) or else not Read_U32 (F,
              FK.Referenced_Table) or else not Read_U32 (F,
              Col_Count) then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed foreign-key metadata");
            end if;
            FK.Name := Name;
            for C in 1 .. Col_Count loop
               if not Read_U32 (F, N) then
                  return Database.Status.Failure (Database.Status.Import_Error, "malformed foreign-key columns");
               end if;
               FK.Referencing_Cols.Append (N);
            end loop;
            if not Read_U32 (F, Col_Count) then
               return Database.Status.Failure (Database.Status.Import_Error,
                 "malformed foreign-key referenced columns");
            end if;
            for C in 1 .. Col_Count loop
               if not Read_U32 (F, N) then
                  return Database.Status.Failure (Database.Status.Import_Error, "malformed foreign-key columns");
               end if;
               FK.Referenced_Cols.Append (N);
            end loop;
            if not Read_U32 (F, Action)

                         or else Action >
                          Database.Foreign_Keys.Foreign_Key_Action'Pos
                            (Database.Foreign_Keys.Foreign_Key_Action'Last)
                     then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed foreign-key delete action");
            end if;
            FK.On_Delete := Database.Foreign_Keys.Foreign_Key_Action'Val (Action);
            if not Read_U32 (F, Action)

                         or else Action >
                          Database.Foreign_Keys.Foreign_Key_Action'Pos
                            (Database.Foreign_Keys.Foreign_Key_Action'Last)
                     then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed foreign-key update action");
            end if;
            FK.On_Update := Database.Foreign_Keys.Foreign_Key_Action'Val (Action);
            if not Read_Boolean (F, FK.Deferred) then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed foreign-key deferred flag");
            end if;
            R := Database.Catalog.Add_Foreign_Key (DB, FK);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end;
      end loop;

      if not Read_U32 (F, Count) then
         return Database.Status.Failure (Database.Status.Import_Error, "missing table metadata count");
      end if;
      for T in 1 .. Count loop
         if not Read_U32 (F, Table_Id) or else not Read_U32 (F, N) then
            return Database.Status.Failure (Database.Status.Import_Error, "malformed table metadata");
         end if;
         for C in 1 .. N loop
            declare
               CC : Database.Check_Constraints.Check_Constraint;
            Expr : Database.Expressions.Expression;
            Deferred : Boolean;
            begin
               if not Read_Text (F, Name) or else not Read_Text (F, Image) or else not Read_Boolean (F, Deferred) then
                  return Database.Status.Failure (Database.Status.Import_Error, "malformed check metadata");
               end if;
               R := Database.Expressions.From_Persistent_Image  (To_Wide_Wide_String (Image),
                 Expr);
                 if not Database.Status.Is_Ok (R) then
                    return R;
                 end if;
               CC := Database.Check_Constraints.Create (To_Wide_Wide_String (Name), Expr, Deferred);
               R := Database.Catalog.Add_Check_Constraint  (DB,
                 Table_Id,
                 CC);
                 if not Database.Status.Is_Ok (R) then
                    return R;
                 end if;
            end;
         end loop;
         if not Read_U32 (F, N) then
            return Database.Status.Failure (Database.Status.Import_Error, "missing generated metadata count");
         end if;
         for G in 1 .. N loop
            declare
               GC : Database.Generated_Columns.Generated_Column;
            Expr : Database.Expressions.Expression;
            Kind_N : Natural;
            begin
               if not Read_U32  (F,
                 GC.Column_Id) or else not Read_Text (F,
                 Name) or else not Read_Text (F,
                 Image) or else not Read_U32 (F,
                 Kind_N)

                         or else Kind_N >
                          Database.Generated_Columns.Generated_Column_Kind'Pos
                            (Database.Generated_Columns.Generated_Column_Kind'Last)
                     then
                  return Database.Status.Failure (Database.Status.Import_Error, "malformed generated metadata");
               end if;
               R := Database.Expressions.From_Persistent_Image  (To_Wide_Wide_String (Image),
                 Expr);
                 if not Database.Status.Is_Ok (R) then
                    return R;
                 end if;
               GC := Database.Generated_Columns.Create  (GC.Column_Id,
                 To_Wide_Wide_String (Name),
                 Expr,
                 Database.Generated_Columns.Generated_Column_Kind'Val (Kind_N));
               R := Database.Catalog.Add_Generated_Column  (DB,
                 Table_Id,
                 GC);
                 if not Database.Status.Is_Ok (R) then
                    return R;
                 end if;
            end;
         end loop;
      end loop;

      if not Read_U32 (F, Count) then
         return Database.Status.Failure (Database.Status.Import_Error, "missing view count");
      end if;
      for VNum in 1 .. Count loop
         declare
            V : Database.Views.View_Definition;
         Q : Database.Queries.Query;
         Id_N : Natural;
         begin
            if not Read_U32 (F, Id_N) or else not Read_Text (F, Name) or else not Read_Text (F, Image) then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed view metadata");
            end if;
            R := Database.Queries.From_Persistent_Image  (To_Wide_Wide_String (Image),
              Q);
              if not Database.Status.Is_Ok (R) then
                 return R;
              end if;
            V := Database.Views.Create (To_Wide_Wide_String (Name), Q);
            R := Database.Catalog.Add_View (DB, V);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end;
      end loop;

      if not Read_U32 (F, Count) then
         return Database.Status.Failure (Database.Status.Import_Error, "missing materialized view count");
      end if;
      for VNum in 1 .. Count loop
         declare
            MV : Database.Materialized_Views.Materialized_View_Definition;
         Q : Database.Queries.Query;
         Id_N, Storage_Table, Last_Commit : Natural;
         begin
            if not Read_U32 (F, Id_N) or else not Read_Text (F, Name) or else not Read_Text (F, Image)
              or else not Read_U32 (F, Storage_Table) or else not Read_U32 (F, Last_Commit) then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed materialized-view metadata");
            end if;
            R := Database.Queries.From_Persistent_Image  (To_Wide_Wide_String (Image),
              Q);
              if not Database.Status.Is_Ok (R) then
                 return R;
              end if;
            MV := Database.Materialized_Views.Create (To_Wide_Wide_String (Name), Q, Storage_Table);
            MV.Last_Refresh_Commit := Last_Commit;
            R := Database.Catalog.Add_Materialized_View  (DB,
              MV);
              if not Database.Status.Is_Ok (R) then
                 return R;
              end if;
         end;
      end loop;

      if not Read_U32 (F, Count) then
         return Database.Status.Failure (Database.Status.Import_Error, "missing extension dependency count");
      end if;
      for DNum in 1 .. Count loop
         declare
            D : Database.Extension_Metadata.Dependency;
         Kind_N : Natural;
         begin
            if not Read_U32  (F,
              Kind_N)

                         or else Kind_N >
                          Database.Extension_Metadata.Extension_Object_Kind'Pos
                            (Database.Extension_Metadata.Extension_Object_Kind'Last)
                       or else not Read_Text (F,
              Name) or else not Read_U32 (F,
              D.Required_Version) or else not Read_Text (F,
              Compat) then
               return Database.Status.Failure (Database.Status.Import_Error, "malformed extension dependency metadata");
            end if;
            D.Object_Kind := Database.Extension_Metadata.Extension_Object_Kind'Val (Kind_N);
            D.Object_Name := Name;
            D.Compatibility_Id := Compat;
            R := Database.Extensions.Add_Dependency (DB, D);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end;
      end loop;
      return Database.Status.Success;
   end Read_Relational_Metadata;

   function Key_For_Row
     (S : Database.Schema.Table_Schema;
      Row : Database.Rows.Row) return Database.Values.Value
   is
      Pos : constant Natural := Database.Schema.Primary_Key_Index (S);
   begin
      if Pos = Natural'Last then
         return Database.Values.Null_Value;
      end if;
      return Database.Rows.Get (Row, Pos);
   end Key_For_Row;

   function Index_Value
     (S : Database.Schema.Table_Schema;
      Row : Database.Rows.Row;
      Column_Id : Natural) return Database.Values.Value
   is
      Pos : constant Natural := Database.Schema.Find_Column_Id_Position (S, Column_Id);
   begin
      if Pos = Natural'Last then
         return Database.Values.Null_Value;
      end if;
      return Database.Rows.Get (Row, Pos);
   end Index_Value;

   function Import_Database
     (Tx     : in out Database.Transactions.Transaction;
      Source : Wide_Wide_String) return Database.Status.Result
   is
   begin
      return Import_Database (Tx, Source, (others => <>));
   end Import_Database;

   function Import_Database
     (Tx      : in out Database.Transactions.Transaction;
      Source  : Wide_Wide_String;
      Options : Import_Options) return Database.Status.Result
   is
      DB : constant access Database.Handle := Database.Transactions.Owning_Database (Tx);
      F : Ada.Streams.Stream_IO.File_Type;
      Header : Unbounded_Wide_Wide_String;
      Version, Table_Count, Row_Count : Natural;
      R : Database.Status.Result;
   begin
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Fail_Import_Read) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Fail_Import_Read);
      end if;
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Import) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error, "deterministic crash during import");
      end if;
      if not Database.Transactions.Can_Write (Tx) or else DB = null then
         return Database.Status.Failure
           (Database.Status.Import_Error, "import requires an active write transaction");
      end if;
      if DB.Kind /= Persistent_Backend then
         return Database.Status.Failure
           (Database.Status.Import_Error, "logical import requires persistent database");
      end if;

      Ada.Streams.Stream_IO.Open
        (F, Ada.Streams.Stream_IO.In_File,
         Ada.Characters.Conversions.To_String (Source));
      if not Read_Text (F, Header)
        or else (To_Wide_Wide_String (Header) /= Magic_20 and then To_Wide_Wide_String (Header) /= Magic_26)
        or else not Read_U32 (F, Version)
        or else (Version /= 20 and then Version /= 26)
        or else not Read_U32 (F, Table_Count)
      then
         Ada.Streams.Stream_IO.Close (F);
         return Database.Status.Failure
           (Database.Status.Import_Error, "invalid database-native logical export");
      end if;

      Database.Catalog.Select_Database (Database.Catalog_State_Key (DB.all));
      if Database.Catalog.Table_Count /= 0 then
         Ada.Streams.Stream_IO.Close (F);
         return Database.Status.Failure
           (Database.Status.Import_Error, "logical import destination must be empty");
      end if;

      Database.Catalog.Clear;
      Database.Full_Text.Select_Database (Database.Full_Text_State_Key (DB.all));
      Database.Full_Text.Clear;

      for T in 1 .. Table_Count loop
         declare
            S : Database.Schema.Table_Schema;
            First : Database.Storage.Pages.Page_Id;
            Root : Database.Storage.Pages.Page_Id;
            Ref : Database.Indexes.Row_Reference;
            Row : Database.Rows.Row;
            Key : Database.Values.Value;
         begin
            if not Read_Schema (F, S) then
               Ada.Streams.Stream_IO.Close (F);
               return Database.Status.Failure
                 (Database.Status.Import_Error, "malformed schema in logical export");
            end if;

            declare
               Imported_Id : constant Natural := S.Table_Id;
               Imported_Indexes : constant Database.Indexes.Index_Metadata_Vectors.Vector := S.Indexes;
               Imported_PK_Columns : constant Database.Indexes.Column_Id_Vectors.Vector := S.Primary_Key_Columns;
            begin
               S.Table_Id := 0;
               S.Heap_First_Page := 0;
               S.Primary_Index_Root := 0;
               S.Indexes.Clear;
               S.Primary_Key_Columns := Imported_PK_Columns;
               R := Database.Catalog.Register (DB.all, S);
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (F);
                  return R;
               end if;
               First := Database.Storage.Pages.Page_Id (S.Heap_First_Page);
               Root := Database.Storage.Pages.Invalid_Page_Id;
               if Database.Schema.Primary_Key_Index (S) /= Natural'Last then
                  R := Database.Indexes.BTree.Create (Tx, DB.File, DB.Page_Allocator, Root);
                  if not Database.Status.Is_Ok (R) then
                     Ada.Streams.Stream_IO.Close (F);
                     return R;
                  end if;
                  S.Primary_Index_Root := Natural (Root);
               end if;

               for Old_IX of Imported_Indexes loop
                  declare
                     New_IX : Database.Indexes.Index_Metadata := Old_IX;
                     IX_Root : Database.Storage.Pages.Page_Id := Database.Storage.Pages.Invalid_Page_Id;
                  begin
                     New_IX.Table_Id := S.Table_Id;
                     New_IX.Root_Page := Database.Storage.Pages.Invalid_Page_Id;
                     R := Database.Indexes.BTree.Create (Tx, DB.File, DB.Page_Allocator, IX_Root);
                     if not Database.Status.Is_Ok (R) then
                        Ada.Streams.Stream_IO.Close (F);
                        return R;
                     end if;
                     New_IX.Root_Page := IX_Root;
                     S.Indexes.Append (New_IX);
                  end;
               end loop;
               pragma Unreferenced (Imported_Id);
               R := Database.Catalog.Update_Table (DB.all, S);
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (F);
                  return R;
               end if;
            end;

            if not Read_U32 (F, Row_Count) then
               Ada.Streams.Stream_IO.Close (F);
               return Database.Status.Failure
                 (Database.Status.Import_Error, "missing row count in logical export");
            end if;

            for Rownum in 1 .. Row_Count loop
               if not Read_Row (F, Row) then
                  Ada.Streams.Stream_IO.Close (F);
                  return Database.Status.Failure
                    (Database.Status.Import_Error, "malformed row in logical export");
               end if;
               R := Database.Storage.Table_Heap.Append_Row
                 (Tx, DB.File, DB.Page_Allocator, First, S, Row, Ref);
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (F);
                  return R;
               end if;
               if Database.Schema.Primary_Key_Index (S) /= Natural'Last then
                  Key := Key_For_Row (S, Row);
                  R := Database.Indexes.BTree.Insert_Duplicate
                    (Tx, DB.File, DB.Page_Allocator, Root, Key, Ref);
                  if not Database.Status.Is_Ok (R) then
                     Ada.Streams.Stream_IO.Close (F);
                     return R;
                  end if;
               end if;
               for IX of S.Indexes loop
                  declare
                     K : constant Database.Values.Value := Index_Value (S, Row, IX.Column_Id);
                     IX_Root : Database.Storage.Pages.Page_Id := IX.Root_Page;
                  begin
                     if K.Kind /= Database.Types.Null_Value then
                        R := Database.Indexes.BTree.Insert_Duplicate
                          (Tx, DB.File, DB.Page_Allocator, IX_Root, K, Ref);
                        if not Database.Status.Is_Ok (R) then
                           Ada.Streams.Stream_IO.Close (F);
                           return R;
                        end if;
                     end if;
                  end;
               end loop;
               Database.Catalog.Register_Row (S.Table_Id, Row);
            end loop;

            if Natural (First) /= S.Heap_First_Page then
               S.Heap_First_Page := Natural (First);
               R := Database.Catalog.Update_Table (DB.all, S);
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (F);
                  return R;
               end if;
            end if;
         end;
      end loop;

      if Version >= 26 then
         R := Read_Relational_Metadata (F, DB.all);
         if not Database.Status.Is_Ok (R) then
            Ada.Streams.Stream_IO.Close (F);
            return R;
         end if;
      end if;
      Ada.Streams.Stream_IO.Close (F);
      R := Database.Catalog.Save (DB.all);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Storage.File_IO.Flush (DB.File);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Options.Verify_After_Import then
         declare
            Check_Result : constant Database.Check.Check_Result  :=
              Database.Check.Check_Database (Tx);
         begin
            if not Check_Result.Success then
               return Database.Status.Failure
                 (Database.Status.Import_Error, "import verification failed");
            end if;
         end;
      end if;
      Database.Metrics.Increment_Imports;
      return Database.Status.Success;
   exception
      when others =>
         begin
            if Ada.Streams.Stream_IO.Is_Open (F) then
               Ada.Streams.Stream_IO.Close (F);
            end if;
         exception
            when others => null;
         end;
         return Database.Status.Failure
           (Database.Status.Import_Error, "logical import failed");
   end Import_Database;
end Database.Import;
