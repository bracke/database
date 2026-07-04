with Database.Transactions;
with Database.Status;
with Database.Catalog;
with Database.Schema;
with Database.Values;
with Database.UUIDs;
with Database.Types;
with Database.Indexes;
with Database.Storage.Table_Heap;
with Database.Storage.File_IO;
with Database.Storage.Pages;
with Database.Rows;
with Ada.Characters.Conversions;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
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

package body Database.Export is
   use Ada.Streams;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Interfaces.Unsigned_64;

   Magic : constant Wide_Wide_String := "DATABASE_LOGICAL_EXPORT_26";

   procedure Write_Byte (F : in out Ada.Streams.Stream_IO.File_Type; B : Natural) is
      S : Stream_Element_Array (1 .. 1);
   begin
      S (1) := Stream_Element (B mod 256);
      Ada.Streams.Stream_IO.Write (F, S);
   end Write_Byte;

   procedure Write_U32 (F : in out Ada.Streams.Stream_IO.File_Type; V : Natural) is
   begin
      Write_Byte (F, (V / 16#1000000#) mod 256);
      Write_Byte (F, (V / 16#10000#) mod 256);
      Write_Byte (F, (V / 16#100#) mod 256);
      Write_Byte (F, V mod 256);
   end Write_U32;

   procedure Write_I64 (F : in out Ada.Streams.Stream_IO.File_Type; V : Long_Long_Integer) is
      --  Store signed integers in fixed-width two's-complement big-endian form.
      --  This preserves negative Decimal coefficients and Long_Integer values
      --  without relying on implementation-specific text images.
      U : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Mod (V);
   begin
      for Shift in reverse 0 .. 7 loop
         Write_Byte
           (F, Natural
              ((U / (Interfaces.Unsigned_64 (2) ** Natural (Shift * 8))) mod 256));
      end loop;
   end Write_I64;

   procedure Write_Boolean (F : in out Ada.Streams.Stream_IO.File_Type; B : Boolean) is
   begin
      Write_Byte (F, (if B then 1 else 0));
   end Write_Boolean;

   procedure Write_Text (F : in out Ada.Streams.Stream_IO.File_Type; S : Wide_Wide_String) is
   begin
      Write_U32 (F, S'Length);
      for Ch of S loop
         Write_U32 (F, Wide_Wide_Character'Pos (Ch));
      end loop;
   end Write_Text;

   procedure Write_Value (F : in out Ada.Streams.Stream_IO.File_Type; V : Database.Values.Value) is
   begin
      Write_Byte (F, Database.Types.Value_Kind'Pos (V.Kind));
      case V.Kind is
         when Database.Types.Null_Value =>
            null;
         when Database.Types.Boolean_Value =>
            Write_Boolean (F, V.Bool);
         when Database.Types.Integer_Value =>
            Write_I64 (F, Long_Long_Integer (V.Int));
         when Database.Types.Long_Integer_Value =>
            Write_I64 (F, V.Long_Int);
         when Database.Types.Float_Value =>
            Write_Text (F, Long_Float'Wide_Wide_Image (V.Flt));
         when Database.Types.Decimal_Value =>
            Write_I64 (F, V.Dec.Coefficient);
            Write_U32 (F, V.Dec.Scale);
         when Database.Types.Text_Value =>
            Write_Text (F, To_Wide_Wide_String (V.Text));
         when Database.Types.Blob_Value =>
            Write_U32 (F, Natural (V.Blob.Length));
            for B of V.Blob loop
               Write_Byte (F, Natural (B));
            end loop;
         when Database.Types.Timestamp_Value =>
            Write_U32 (F, Natural (V.Time.Year));
            Write_U32 (F, Natural (V.Time.Month));
            Write_U32 (F, Natural (V.Time.Day));
            Write_U32 (F, Natural (V.Time.Hour));
            Write_U32 (F, Natural (V.Time.Minute));
            Write_U32 (F, Natural (V.Time.Second));
            Write_U32 (F, V.Time.Nanosecond);
         when Database.Types.Enum_Value =>
            Write_Text (F, To_Wide_Wide_String (V.Enum_Text));
         when Database.Types.Date_Value => Write_U32  (F,
           Natural (V.Date.Year));
           Write_U32 (F,
           Natural (V.Date.Month));
           Write_U32 (F,
           Natural (V.Date.Day));
         when Database.Types.Time_Value => Write_U32  (F,
           Natural (V.Clock_Time.Hour));
           Write_U32 (F,
           Natural (V.Clock_Time.Minute));
           Write_U32 (F,
           Natural (V.Clock_Time.Second));
           Write_U32 (F,
           V.Clock_Time.Nanosecond);
         when Database.Types.Date_Time_Value => Write_U32  (F,
           Natural (V.Date_Time.Date_Part.Year));
           Write_U32 (F,
           Natural (V.Date_Time.Date_Part.Month));
           Write_U32 (F,
           Natural (V.Date_Time.Date_Part.Day));
           Write_U32 (F,
           Natural (V.Date_Time.Time_Part.Hour));
           Write_U32 (F,
           Natural (V.Date_Time.Time_Part.Minute));
           Write_U32 (F,
           Natural (V.Date_Time.Time_Part.Second));
           Write_U32 (F,
           V.Date_Time.Time_Part.Nanosecond);
         when Database.Types.Duration_Value => Write_I64  (F,
           V.Time_Span.Seconds);
           Write_U32 (F,
           V.Time_Span.Nanoseconds);
         when Database.Types.UUID_Value => for B of V.UUID loop Write_Byte (F, Natural (B));
         end loop;
         when Database.Types.Array_Value => Write_Text (F, To_Wide_Wide_String (V.Array_Text));
      end case;
   end Write_Value;

   procedure Write_Row (F : in out Ada.Streams.Stream_IO.File_Type; R : Database.Rows.Row) is
   begin
      Write_U32 (F, Database.Rows.Column_Count (R));
      if Database.Rows.Column_Count (R) > 0 then
         for I in 0 .. Database.Rows.Column_Count (R) - 1 loop
            Write_Value (F, Database.Rows.Get (R, I));
         end loop;
      end if;
   end Write_Row;

   procedure Write_Index (F : in out Ada.Streams.Stream_IO.File_Type; IX : Database.Indexes.Index_Metadata) is
   begin
      Write_U32 (F, Natural (IX.Id));
      Write_U32 (F, IX.Table_Id);
      Write_Text (F, To_Wide_Wide_String (IX.Name));
      Write_Byte (F, Database.Indexes.Index_Kind'Pos (IX.Kind));
      Write_Boolean (F, IX.Unique);
      Write_U32 (F, IX.Column_Id);
      Write_Byte (F, Database.Types.Value_Kind'Pos (IX.Key_Kind));
      Write_U32 (F, Natural (IX.Column_Ids.Length));
      for C of IX.Column_Ids loop
         Write_U32 (F, C);
      end loop;
      Write_Boolean (F, IX.Has_Predicate);
      Write_Boolean (F, IX.Has_Expression);
   end Write_Index;

   procedure Write_Relational_Metadata (F : in out Ada.Streams.Stream_IO.File_Type) is
      FK_Total : Natural := 0;
   begin
      Write_Text (F, "RELATIONAL_METADATA_V1");
      for T in 0 .. Database.Catalog.Table_Count - 1 loop
         FK_Total := FK_Total + Natural (Database.Catalog.Foreign_Keys_For_Referencing_Table
           (Database.Catalog.Table_At (T).Table_Id).Length);
      end loop;
      Write_U32 (F, FK_Total);
      for T in 0 .. Database.Catalog.Table_Count - 1 loop
         declare
            FKs : constant Database.Foreign_Keys.Foreign_Key_Vectors.Vector  :=
              Database.Catalog.Foreign_Keys_For_Referencing_Table
                (Database.Catalog.Table_At (T).Table_Id);
         begin
            for FK of FKs loop
               Write_Text (F, To_Wide_Wide_String (FK.Name));
               Write_U32 (F, FK.Referencing_Table);
               Write_U32 (F, FK.Referenced_Table);
               Write_U32 (F, Natural (FK.Referencing_Cols.Length));
               for C of FK.Referencing_Cols loop
                  Write_U32 (F, C);
               end loop;
               Write_U32 (F, Natural (FK.Referenced_Cols.Length));
               for C of FK.Referenced_Cols loop
                  Write_U32 (F, C);
               end loop;
               Write_U32 (F, Database.Foreign_Keys.Foreign_Key_Action'Pos (FK.On_Delete));
               Write_U32 (F, Database.Foreign_Keys.Foreign_Key_Action'Pos (FK.On_Update));
               Write_Boolean (F, FK.Deferred);
            end loop;
         end;
      end loop;

      Write_U32 (F, Database.Catalog.Table_Count);
      for T in 0 .. Database.Catalog.Table_Count - 1 loop
         declare
            S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (T);
            Checks : constant Database.Check_Constraints.Check_Constraint_Vectors.Vector  :=
              Database.Catalog.Check_Constraints_For_Table (S.Table_Id);
            Gens : constant Database.Generated_Columns.Generated_Column_Vectors.Vector  :=
              Database.Catalog.Generated_Columns_For_Table (S.Table_Id);
         begin
            Write_U32 (F, S.Table_Id);
            Write_U32 (F, Natural (Checks.Length));
            for C of Checks loop
               Write_Text (F, To_Wide_Wide_String (C.Name));
               Write_Text (F, Database.Expressions.Persistent_Image (C.Expression));
               Write_Boolean (F, C.Deferred);
            end loop;
            Write_U32 (F, Natural (Gens.Length));
            for G of Gens loop
               Write_U32 (F, G.Column_Id);
               Write_Text (F, To_Wide_Wide_String (G.Name));
               Write_Text (F, Database.Expressions.Persistent_Image (G.Expression));
               Write_U32 (F, Database.Generated_Columns.Generated_Column_Kind'Pos (G.Kind));
            end loop;
         end;
      end loop;

      Write_U32 (F, Database.Catalog.View_Count);
      for I in 0 .. Database.Catalog.View_Count - 1 loop
         declare
            V : constant Database.Views.View_Definition := Database.Catalog.View_At (I);
         begin
            Write_U32 (F, Natural (V.Id));
            Write_Text (F, To_Wide_Wide_String (V.Name));
            Write_Text (F, Database.Queries.Persistent_Image (V.Query));
         end;
      end loop;

      Write_U32 (F, Database.Catalog.Materialized_View_Count);
      for I in 0 .. Database.Catalog.Materialized_View_Count - 1 loop
         declare MV : constant Database.Materialized_Views.Materialized_View_Definition  :=
           Database.Catalog.Materialized_View_At (I);
         begin
            Write_U32 (F, Natural (MV.Id));
            Write_Text (F, To_Wide_Wide_String (MV.Name));
            Write_Text (F, Database.Queries.Persistent_Image (MV.Query));
            Write_U32 (F, MV.Storage_Table);
            Write_U32 (F, MV.Last_Refresh_Commit);
         end;
      end loop;

      declare Deps : constant Database.Extension_Metadata.Dependency_Vectors.Vector  :=
        Database.Extensions.Dependencies;
      begin
         Write_U32 (F, Natural (Deps.Length));
         for D of Deps loop
            Write_U32 (F, Database.Extension_Metadata.Extension_Object_Kind'Pos (D.Object_Kind));
            Write_Text (F, To_Wide_Wide_String (D.Object_Name));
            Write_U32 (F, D.Required_Version);
            Write_Text (F, To_Wide_Wide_String (D.Compatibility_Id));
         end loop;
      end;
   end Write_Relational_Metadata;

   procedure Write_Schema (F : in out Ada.Streams.Stream_IO.File_Type; S : Database.Schema.Table_Schema) is
   begin
      Write_U32 (F, S.Table_Id);
      Write_U32 (F, S.Schema_Version);
      Write_U32 (F, S.Next_Column_Id);
      Write_Text (F, To_Wide_Wide_String (S.Name));
      Write_U32 (F, Database.Schema.Column_Count (S));
      if Database.Schema.Column_Count (S) > 0 then
         for I in 0 .. Database.Schema.Column_Count (S) - 1 loop
            declare
               C : constant Database.Schema.Column := S.Columns.Element (I);
            begin
               Write_U32 (F, C.Id);
               Write_Text (F, To_Wide_Wide_String (C.Name));
               Write_Byte (F, Database.Types.Value_Kind'Pos (C.Kind));
               Write_Boolean (F, C.Nullable);
               Write_Boolean (F, C.Primary_Key);
            end;
         end loop;
      end if;
      Write_U32 (F, Natural (S.Primary_Key_Columns.Length));
      for C of S.Primary_Key_Columns loop
         Write_U32 (F, C);
      end loop;
      Write_U32 (F, Natural (S.Indexes.Length));
      for IX of S.Indexes loop
         Write_Index (F, IX);
      end loop;
   end Write_Schema;

   function Export_Database
     (Tx          : in out Database.Transactions.Transaction;
      Destination : Wide_Wide_String) return Database.Status.Result
   is
   begin
      return Export_Database (Tx, Destination, (others => <>));
   end Export_Database;

   function Export_Database
     (Tx          : in out Database.Transactions.Transaction;
      Destination : Wide_Wide_String;
      Options     : Export_Options) return Database.Status.Result
   is
      DB : constant access Database.Handle := Database.Transactions.Owning_Database (Tx);
      F  : Ada.Streams.Stream_IO.File_Type;
      R  : Database.Status.Result;
   begin
      if Database.Fault_Hooks.Should_Crash (Database.Fault_Hooks.During_Export) then
         return Database.Status.Failure (Database.Status.Fault_Injection_Error, "deterministic crash during export");
      end if;
      if not Database.Transactions.Can_Read (Tx) or else DB = null then
         return Database.Status.Failure
           (Database.Status.Export_Error, "export requires an active transaction");
      end if;
      if DB.Kind /= Persistent_Backend then
         return Database.Status.Failure
           (Database.Status.Export_Error, "logical export requires a persistent database");
      end if;

      R := Database.Storage.File_IO.Flush (DB.File);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      Ada.Streams.Stream_IO.Create
        (F, Ada.Streams.Stream_IO.Out_File,
         Ada.Characters.Conversions.To_String (Destination));
      Write_Text (F, Magic);
      Write_U32 (F, 26);
      Write_U32 (F, Database.Catalog.Table_Count);
      if Database.Catalog.Table_Count > 0 then
      for T in 0 .. Database.Catalog.Table_Count - 1 loop
         declare
            S : constant Database.Schema.Table_Schema := Database.Catalog.Table_At (T);
            C : Database.Storage.Table_Heap.Heap_Cursor;
            Row_Count : Natural := 0;
         begin
            Write_Schema (F, S);

            R := Database.Storage.Table_Heap.Scan_First (Tx, DB.File,
              Database.Storage.Pages.Page_Id (S.Heap_First_Page), S, C);
            if not Database.Status.Is_Ok (R) then
               Ada.Streams.Stream_IO.Close (F);
               return R;
            end if;
            while C.Has_Row loop
               Row_Count := Row_Count + 1;
               R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, S, C);
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (F);
                  return R;
               end if;
            end loop;

            Write_U32 (F, Row_Count);
            R := Database.Storage.Table_Heap.Scan_First (Tx, DB.File,
              Database.Storage.Pages.Page_Id (S.Heap_First_Page), S, C);
            if not Database.Status.Is_Ok (R) then
               Ada.Streams.Stream_IO.Close (F);
               return R;
            end if;
            while C.Has_Row loop
               Write_Row (F, C.Row);
               R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, S, C);
               if not Database.Status.Is_Ok (R) then
                  Ada.Streams.Stream_IO.Close (F);
                  return R;
               end if;
            end loop;
         end;
      end loop;
      end if;
      Write_Relational_Metadata (F);
      Ada.Streams.Stream_IO.Close (F);
      if Options.Verify_After_Write and then
        not Ada.Directories.Exists
          (Ada.Characters.Conversions.To_String (Destination))
      then
         return Database.Status.Failure
           (Database.Status.Export_Error, "logical export verification failed");
      end if;
      Database.Metrics.Increment_Exports;
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
           (Database.Status.Export_Error, "logical export failed");
   end Export_Database;
end Database.Export;
