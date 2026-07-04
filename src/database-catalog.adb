with Database.Schema;
with Database.Status;
with Database.Fault_Hooks;
with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Unchecked_Deallocation;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Storage.Pages;
with Database.Storage.Record_Format;
with Database.Storage.Table_Heap;
with Database.Storage.File_IO;
with Database.Types;
with Database.Indexes;
with Database.Foreign_Keys;
with Database.Check_Constraints;
with Database.Generated_Columns;
with Database.Views;
with Database.Materialized_Views;
with Database.Rows;
with Database.Values;
with Database.Full_Text.Indexes;
with Database.Expressions;
with Database.Queries;

package body Database.Catalog is
   use type Database.Materialized_Views.Materialized_View_Id;
   use type Database.Full_Text.Indexes.Full_Text_Index_Id;
   use type Database.Schema.Table_Schema;
   use type Ada.Containers.Count_Type;
   use Ada.Strings.Wide_Wide_Unbounded;
   package Schema_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Database.Schema.Table_Schema);

   type Table_Checks is record
      Table_Id : Natural := 0;
      Checks   : Database.Check_Constraints.Check_Constraint_Vectors.Vector;
   end record;
   package Table_Check_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Table_Checks);

   type Table_Generated is record
      Table_Id : Natural := 0;
      Columns  : Database.Generated_Columns.Generated_Column_Vectors.Vector;
   end record;
   package Table_Generated_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Table_Generated);

   type Catalog_Row is record
      Table_Id : Natural := 0;
      Row      : Database.Rows.Row;
   end record;
   package Catalog_Row_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Catalog_Row);

   type Catalog_State is record
      Tables               : Schema_Vectors.Vector;
      Foreign_Keys         : Database.Foreign_Keys.Foreign_Key_Vectors.Vector;
      Table_Checks_List    : Table_Check_Vectors.Vector;
      Table_Generated_List : Table_Generated_Vectors.Vector;
      Views                : Database.Views.View_Vectors.Vector;
      Materialized_Views   : Database.Materialized_Views.Materialized_View_Vectors.Vector;
      Full_Text_Indexes    : Database.Full_Text.Indexes.Metadata_Vectors.Vector;
      Cached_Rows          : Catalog_Row_Vectors.Vector;
   end record;

   type Catalog_State_Access is access all Catalog_State;

   type Catalog_State_Entry is record
      Key   : Natural := 0;
      State : Catalog_State_Access := null;
   end record;

   package Catalog_State_Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Catalog_State_Entry);

   procedure Free_State is new Ada.Unchecked_Deallocation
     (Object => Catalog_State, Name => Catalog_State_Access);

   States : Catalog_State_Entry_Vectors.Vector;
   Current_Key : Natural := 0;
   Default_State : aliased Catalog_State;

   function Current_State return Catalog_State_Access is
   begin
      if Current_Key = 0 then
         return Default_State'Access;
      end if;
      if States.Length > 0 then
         for I in 0 .. Natural (States.Length) - 1 loop
            if States.Element (I).Key = Current_Key then
               return States.Element (I).State;
            end if;
         end loop;
      end if;
      declare
         E : Catalog_State_Entry;
      begin
         E.Key := Current_Key;
         E.State := new Catalog_State;
         States.Append (E);
         return E.State;
      end;
   end Current_State;

   procedure Select_Database (State_Key : Natural) is
   begin
      Current_Key := State_Key;
      if State_Key /= 0 then
         declare
            Ignore : constant Catalog_State_Access := Current_State;
         begin
            null;
         end;
      end if;
   end Select_Database;

   procedure Drop_Database (State_Key : Natural) is
   begin
      if State_Key = 0 then
         return;
      end if;
      if States.Length > 0 then
         for I in reverse 0 .. Natural (States.Length) - 1 loop
            if States.Element (I).Key = State_Key then
               declare
                  E : Catalog_State_Entry := States.Element (I);
               begin
                  if E.State /= null then
                     Free_State (E.State);
                  end if;
                  States.Delete (I);
               end;
            end if;
         end loop;
      end if;
      if Current_Key = State_Key then
         Current_Key := 0;
      end if;
   end Drop_Database;

   procedure Clear is
   begin
      Current_State.all.Tables.Clear;
      Current_State.all.Foreign_Keys.Clear;
      Current_State.all.Table_Checks_List.Clear;
      Current_State.all.Table_Generated_List.Clear;
      Current_State.all.Views.Clear;
      Current_State.all.Materialized_Views.Clear;
      Current_State.all.Full_Text_Indexes.Clear;
      Current_State.all.Cached_Rows.Clear;
   end Clear;

   function Register
     (DB     : in out Database.Handle;
      Schema : in out Database.Schema.Table_Schema) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      for S of Current_State.all.Tables loop
         if To_Wide_Wide_String (S.Name) = To_Wide_Wide_String (Schema.Name) then
            return Database.Status.Failure (Database.Status.Already_Exists, "table already registered");
         end if;
      end loop;
      Schema.Table_Id := Natural (Current_State.all.Tables.Length) + 1;
      if Database.Backend (DB) = Database.Persistent_Backend and then Schema.Heap_First_Page = 0 then
         declare
            First : Database.Storage.Pages.Page_Id;
         R : Database.Status.Result;
         begin
            R := Database.Storage.Table_Heap.Create_Heap (DB.File, DB.Page_Allocator, First);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Schema.Heap_First_Page := Natural (First);
         end;
      end if;
      Current_State.all.Tables.Append (Schema);
      return Save (DB);
   end Register;

   function Find_By_Name
     (Name   : Wide_Wide_String;
      Schema : out Database.Schema.Table_Schema) return Database.Status.Result is
   begin
      for S of Current_State.all.Tables loop
         if To_Wide_Wide_String (S.Name) = Name then
            Schema := S;
            return Database.Status.Success;
         end if;
      end loop;
      return Database.Status.Failure (Database.Status.Not_Found, "table not found");
   end Find_By_Name;

   function Find_By_Id
     (Table_Id : Natural;
      Schema   : out Database.Schema.Table_Schema) return Database.Status.Result is
   begin
      for S of Current_State.all.Tables loop
         if S.Table_Id = Table_Id then
            Schema := S;
            return Database.Status.Success;
         end if;
      end loop;
      return Database.Status.Failure (Database.Status.Not_Found, "table id not found");
   end Find_By_Id;

   function Update_Table
     (DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema) return Database.Status.Result is
      R : Database.Status.Result;
   begin
      R := Stage_Update_Table (DB, Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      return Save (DB);
   end Update_Table;

   function Stage_Update_Table
     (DB     : in out Database.Handle;
      Schema : Database.Schema.Table_Schema) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      if Current_State.all.Tables.Length > 0 then
         for I in 0 .. Natural (Current_State.all.Tables.Length) - 1 loop
            if Current_State.all.Tables.Element (I).Table_Id = Schema.Table_Id then
               Current_State.all.Tables.Replace_Element (I, Schema);
               return Database.Status.Success;
            end if;
         end loop;
      end if;
      return Database.Status.Failure (Database.Status.Not_Found, "table not found");
   end Stage_Update_Table;

   procedure Put_U32 (B : in out Database.Storage.Pages.Byte_Array; Pos : in out Natural; V : Natural) is
   begin
      B (Pos) := Database.Storage.Pages.Byte ((V/16#1000000#)mod 256);
      B (Pos + 1) := Database.Storage.Pages.Byte ((V/16#10000#)mod 256);
      B (Pos + 2) := Database.Storage.Pages.Byte ((V/16#100#)mod 256);
      B (Pos + 3) := Database.Storage.Pages.Byte (V mod 256);
      Pos := Pos + 4;
   end Put_U32;
   procedure Put_Text (B : in out Database.Storage.Pages.Byte_Array; Pos : in out Natural; S : Wide_Wide_String) is
   begin
      Put_U32 (B,Pos,S'Length);
      for Ch of S loop Put_U32 (B,Pos,Wide_Wide_Character'Pos (Ch));
      end loop;
   end Put_Text;
   function Get_U32
     (B    : Database.Storage.Pages.Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      V    : out Natural) return Boolean is
   begin
      if Pos + 4>Last then
         return False;
      end if;
      V := Natural (B (Pos))*16#1000000#+Natural (B (Pos + 1))*16#10000#+Natural (B (Pos
        + 2))*16#100#+Natural (B (Pos + 3));
      Pos := Pos + 4;
      return True;
   end Get_U32;
   function Get_Text
     (B    : Database.Storage.Pages.Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      S    : out Unbounded_Wide_Wide_String) return Boolean is
      Len, C : Natural;
   begin
      if not Get_U32 (B,Pos,Last,Len) then
         return False;
      end if;
      declare
         T : Wide_Wide_String(1..Len);
      begin
         for I in T'Range loop
            if not Get_U32 (B,Pos,Last,C) then
               return False;
            end if;
            T(I) := Wide_Wide_Character'Val(C);
         end loop;
         S := To_Unbounded_Wide_Wide_String(T);
         return True;
      end;
   end Get_Text;

   function Save (DB : in out Database.Handle) return Database.Status.Result is
      use Database.Storage.Pages;
      P : Page;
      B : Byte_Array (0 .. Payload_Capacity - 1) := (others => 0);
      Pos : Natural := 0;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      if Database.Backend (DB) /= Database.Persistent_Backend then
         return Database.Status.Success;
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Partial_Metadata_Persistence) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Partial_Metadata_Persistence);
      end if;
      if Database.Fault_Hooks.Should_Fail (Database.Fault_Hooks.Allocation_Failure) then
         return Database.Fault_Hooks.Injected_Failure (Database.Fault_Hooks.Allocation_Failure);
      end if;
      Initialize (P, 1, Catalog_Page);
      Put_U32 (B, Pos, Natural (Current_State.all.Tables.Length));
      for S of Current_State.all.Tables loop
         Put_U32  (B,
           Pos,
           S.Table_Id);
           Put_U32 (B,
           Pos,
           S.Schema_Version);
           Put_U32 (B,
           Pos,
           Database.Schema.Next_Id (S));
           Put_Text (B,
           Pos,
           To_Wide_Wide_String (S.Name));
           Put_U32 (B,
           Pos,
           S.Heap_First_Page);
           Put_U32 (B,
           Pos,
           S.Primary_Index_Root);
         Put_U32 (B, Pos, Natural (S.Indexes.Length));
         for IX of S.Indexes loop
            Put_U32  (B,
              Pos,
              Natural (IX.Id));
              Put_U32 (B,
              Pos,
              IX.Table_Id);
              Put_Text (B,
              Pos,
              To_Wide_Wide_String (IX.Name));
            Put_U32  (B,
              Pos,
              Database.Indexes.Index_Kind'Pos (IX.Kind));
              Put_U32 (B,
              Pos,
              Natural (IX.Root_Page));
              Put_U32 (B,
              Pos,
              (if IX.Unique then 1 else 0));
            Put_U32 (B, Pos, IX.Column_Id);
            Put_U32 (B, Pos, Database.Types.Value_Kind'Pos (IX.Key_Kind));
         end loop;
         Put_U32 (B, Pos, Database.Schema.Column_Count (S));
         for C of S.Columns loop
            Put_U32  (B,
              Pos,
              C.Id);
              Put_Text (B,
              Pos,
              To_Wide_Wide_String (C.Name));
              Put_U32 (B,
              Pos,
              Database.Types.Value_Kind'Pos (C.Kind));
              Put_U32 (B,
              Pos,
              (if C.Nullable then 1 else 0));
              Put_U32 (B,
              Pos,
              (if C.Primary_Key then 1 else 0));
         end loop;
      end loop;
      Put_U32 (B, Pos, Natural (Current_State.all.Full_Text_Indexes.Length));
      for FTX of Current_State.all.Full_Text_Indexes loop
         Put_U32 (B, Pos, Natural (FTX.Id));
         Put_Text (B, Pos, To_Wide_Wide_String (FTX.Name));
         Put_U32 (B, Pos, FTX.Table_Id);
         Put_Text (B, Pos, To_Wide_Wide_String (FTX.Table_Name));
         Put_U32 (B, Pos, FTX.Column_Id);
      end loop;
      --  Durable relational metadata is stored after
      --  the pre-existing catalog sections so older catalog payloads remain
      --  loadable. Every definition is encoded explicitly;
      --  no Ada record memory
      --  layout is persisted.
      Put_U32 (B, Pos, Natural (Current_State.all.Foreign_Keys.Length));
      for FK of Current_State.all.Foreign_Keys loop
         Put_Text (B, Pos, To_Wide_Wide_String (FK.Name));
         Put_U32 (B, Pos, FK.Referencing_Table);
         Put_U32 (B, Pos, FK.Referenced_Table);
         Put_U32 (B, Pos, Natural (FK.Referencing_Cols.Length));
         for C of FK.Referencing_Cols loop
            Put_U32 (B, Pos, C);
         end loop;
         Put_U32 (B, Pos, Natural (FK.Referenced_Cols.Length));
         for C of FK.Referenced_Cols loop
            Put_U32 (B, Pos, C);
         end loop;
         Put_U32 (B, Pos, Database.Foreign_Keys.Foreign_Key_Action'Pos (FK.On_Delete));
         Put_U32 (B, Pos, Database.Foreign_Keys.Foreign_Key_Action'Pos (FK.On_Update));
         Put_U32 (B, Pos, (if FK.Deferred then 1 else 0));
      end loop;

      Put_U32 (B, Pos, Natural (Current_State.all.Table_Checks_List.Length));
      for TC of Current_State.all.Table_Checks_List loop
         Put_U32 (B, Pos, TC.Table_Id);
         Put_U32 (B, Pos, Natural (TC.Checks.Length));
         for C of TC.Checks loop
            Put_Text (B, Pos, To_Wide_Wide_String (C.Name));
            Put_Text (B, Pos, Database.Expressions.Persistent_Image (C.Expression));
            Put_U32 (B, Pos, (if C.Deferred then 1 else 0));
         end loop;
      end loop;

      Put_U32 (B, Pos, Natural (Current_State.all.Table_Generated_List.Length));
      for TG of Current_State.all.Table_Generated_List loop
         Put_U32 (B, Pos, TG.Table_Id);
         Put_U32 (B, Pos, Natural (TG.Columns.Length));
         for C of TG.Columns loop
            Put_U32 (B, Pos, C.Column_Id);
            Put_Text (B, Pos, To_Wide_Wide_String (C.Name));
            Put_Text (B, Pos, Database.Expressions.Persistent_Image (C.Expression));
            Put_U32 (B, Pos, Database.Generated_Columns.Generated_Column_Kind'Pos (C.Kind));
         end loop;
      end loop;

      Put_U32 (B, Pos, Natural (Current_State.all.Views.Length));
      for V of Current_State.all.Views loop
         Put_U32 (B, Pos, Natural (V.Id));
         Put_Text (B, Pos, To_Wide_Wide_String (V.Name));
         Put_Text (B, Pos, Database.Queries.Persistent_Image (V.Query));
      end loop;

      Put_U32 (B, Pos, Natural (Current_State.all.Materialized_Views.Length));
      for MV of Current_State.all.Materialized_Views loop
         Put_U32 (B, Pos, Natural (MV.Id));
         Put_Text (B, Pos, To_Wide_Wide_String (MV.Name));
         Put_Text (B, Pos, Database.Queries.Persistent_Image (MV.Query));
         Put_U32 (B, Pos, MV.Storage_Table);
         Put_U32 (B, Pos, MV.Last_Refresh_Commit);
      end loop;

      --  Extended index metadata for composite/partial/expression
      --  index descriptors that were added after the original one-page catalog
      --  index record. Stored out-of-line by table/id to preserve compatibility
      --  with older catalog readers.
      declare
         Extra_Count : Natural := 0;
      begin
         for S of Current_State.all.Tables loop
            for IX of S.Indexes loop
               if IX.Column_Ids.Length > 0 or else IX.Has_Predicate or else IX.Has_Expression then
                  Extra_Count := Extra_Count + 1;
               end if;
            end loop;
         end loop;
         Put_U32 (B, Pos, Extra_Count);
         for S of Current_State.all.Tables loop
            for IX of S.Indexes loop
               if IX.Column_Ids.Length > 0 or else IX.Has_Predicate or else IX.Has_Expression then
                  Put_U32 (B, Pos, S.Table_Id);
                  Put_U32 (B, Pos, Natural (IX.Id));
                  Put_U32 (B, Pos, Natural (IX.Column_Ids.Length));
                  for CID of IX.Column_Ids loop
                     Put_U32 (B, Pos, CID);
                  end loop;
                  Put_U32 (B, Pos, (if IX.Has_Predicate then 1 else 0));
                  Put_U32 (B, Pos, (if IX.Has_Expression then 1 else 0));
               end if;
            end loop;
         end loop;
      end;
      if Pos = 0 then
         declare
            Empty : Byte_Array (1 .. 0);
         begin
            Set_Payload (P, Empty);
         end;
      else
         declare
            D : Byte_Array (0 .. Pos - 1);
         begin
            for I in D'Range loop
               D (I) := B (I);
            end loop;
            Set_Payload (P, D);
         end;
      end if;
      return Database.Storage.File_IO.Write_Page (DB.File, P);
   exception
      when others => return Database.Status.Failure (Database.Status.Row_Too_Large, "catalog exceeds one page");
   end Save;

   function Load (DB : in out Database.Handle) return Database.Status.Result is
      use Database.Storage.Pages;
      P : Page;
      R : Database.Status.Result;
      Count, Cols, Tmp, Index_Count : Natural;
      Pos : Natural;
      Last : Natural;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Clear;
      if Database.Backend (DB) /= Database.Persistent_Backend then
         return Database.Status.Success;
      end if;
      R := Database.Storage.File_IO.Read_Page (DB.File, 1, Catalog_Page, P);
      if not Database.Status.Is_Ok (R) then
         -- Newly-created files may not yet have a catalog page.
         Initialize (P, 1, Catalog_Page);
         return Database.Storage.File_IO.Write_Page (DB.File, P);
      end if;
      declare
         B : constant Byte_Array := Payload (P);
      begin
         if B'Length = 0 then
            return Database.Status.Success;
         end if;
         Pos := B'First;
         Last := B'First + B'Length;
         if not Get_U32 (B,Pos,Last,Count) then
            return Database.Status.Failure(Database.Status.Corrupt_File,"bad catalog");
         end if;
         for T in 1 .. Count loop
            declare
               S : Database.Schema.Table_Schema;
            Name : Unbounded_Wide_Wide_String;
            begin
               if not Get_U32 (B,
                 Pos,
                 Last,
                 S.Table_Id) or else not Get_U32 (B,
                 Pos,
                 Last,
                 S.Schema_Version) or else not Get_U32 (B,
                 Pos,
                 Last,
                 S.Next_Column_Id) or else not Get_Text (B,
                 Pos,
                 Last,
                 Name) or else not Get_U32 (B,
                 Pos,
                 Last,
                 S.Heap_First_Page) or else not Get_U32 (B,
                 Pos,
                 Last,
                 S.Primary_Index_Root) or else not Get_U32 (B,
                 Pos,
                 Last,
                 Index_Count) then
                  return Database.Status.Failure(Database.Status.Corrupt_File,"truncated table catalog");
               end if;
               S.Name := Name;
               for J in 1 .. Index_Count loop
                  declare
                     IX : Database.Indexes.Index_Metadata;
                  IX_Name : Unbounded_Wide_Wide_String;
                  Kind, Unique_Flag, Key_Kind : Natural;
                  Root_Page_N : Natural;
                  Id_N : Natural;
                  begin
                     if not Get_U32 (B,
                       Pos,
                       Last,
                       Id_N) or else not Get_U32 (B,
                       Pos,
                       Last,
                       IX.Table_Id) or else not Get_Text (B,
                       Pos,
                       Last,
                       IX_Name) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Kind) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Root_Page_N) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Unique_Flag) or else not Get_U32 (B,
                       Pos,
                       Last,
                       IX.Column_Id) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Key_Kind) then
                        return Database.Status.Failure(Database.Status.Corrupt_File,"truncated index catalog");
                     end if;
                     IX.Id := Database.Indexes.Index_Id (Id_N);
                     IX.Name := IX_Name;
                     IX.Kind := Database.Indexes.Index_Kind'Val (Kind);
                     IX.Root_Page := Database.Storage.Pages.Page_Id (Root_Page_N);
                     IX.Unique := Unique_Flag /= 0;
                     IX.Key_Kind := Database.Types.Value_Kind'Val (Key_Kind);
                     S.Indexes.Append (IX);
                  end;
               end loop;
               if not Get_U32 (B,Pos,Last,Cols) then
                  return Database.Status.Failure(Database.Status.Corrupt_File,"truncated table catalog");
               end if;
               for I in 1 .. Cols loop
                  declare
                     C : Database.Schema.Column;
                  CName : Unbounded_Wide_Wide_String;
                  Kind : Natural;
                  N, PK : Natural;
                  begin
                     if not Get_U32 (B,
                       Pos,
                       Last,
                       C.Id) or else not Get_Text (B,
                       Pos,
                       Last,
                       CName) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Kind) or else not Get_U32 (B,
                       Pos,
                       Last,
                       N) or else not Get_U32 (B,
                       Pos,
                       Last,
                       PK) then
                        return Database.Status.Failure(Database.Status.Corrupt_File,"truncated column catalog");
                     end if;
                     C.Name := CName;
                     C.Kind := Database.Types.Value_Kind'Val(Kind);
                     C.Nullable := N/=0;
                     C.Primary_Key := PK/=0;
                     S.Columns.Append(C);
                  end;
               end loop;
               Current_State.all.Tables.Append(S);
            end;
         end loop;
         --  Full-text definitions are optional for
         --  backward compatibility with older one-page catalogs. If absent, no
         --  definitions are registered and indexes can still be recreated by user
         --  code.
         if Pos < Last then
            declare
               FT_Count : Natural;
            begin
               if Get_U32 (B, Pos, Last, FT_Count) then
                  for K in 1 .. FT_Count loop
                     declare
                        M : Database.Full_Text.Indexes.Full_Text_Index_Metadata;
                        Name, Table_Name : Unbounded_Wide_Wide_String;
                        Id_N : Natural;
                     begin
                        if not Get_U32 (B, Pos, Last, Id_N)
                          or else not Get_Text (B, Pos, Last, Name)
                          or else not Get_U32 (B, Pos, Last, M.Table_Id)
                          or else not Get_Text (B, Pos, Last, Table_Name)
                          or else not Get_U32 (B, Pos, Last, M.Column_Id)
                        then
                           return Database.Status.Failure (Database.Status.Corrupt_File, "truncated full-text catalog");
                        end if;
                        M.Id := Database.Full_Text.Indexes.Full_Text_Index_Id (Id_N);
                        M.Name := Name;
                        M.Table_Name := Table_Name;
                        Current_State.all.Full_Text_Indexes.Append (M);
                     end;
                  end loop;
               end if;
            end;
         end if;
         --  Durable advanced relational metadata.
         --  The whole section is optional for old catalogs;
         --  once present,
         --  truncation or malformed expression metadata is reported as
         --  Corrupt_File rather than silently ignored.
         if Pos < Last then
            declare
               FK_Count : Natural;
            begin
               if not Get_U32 (B, Pos, Last, FK_Count) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "truncated foreign-key catalog");
               end if;
               for K in 1 .. FK_Count loop
                  declare
                     FK : Database.Foreign_Keys.Foreign_Key_Definition;
                     Name : Unbounded_Wide_Wide_String;
                     Ref_Count, Target_Count, Action, Flag : Natural;
                  begin
                     if not Get_Text (B, Pos, Last, Name)
                       or else not Get_U32 (B, Pos, Last, FK.Referencing_Table)
                       or else not Get_U32 (B, Pos, Last, FK.Referenced_Table)
                       or else not Get_U32 (B, Pos, Last, Ref_Count)
                     then
                        return Database.Status.Failure (Database.Status.Corrupt_File, "truncated foreign-key catalog");
                     end if;
                     FK.Name := Name;
                     for I in 1 .. Ref_Count loop
                        declare
                           C : Natural;
                        begin
                           if not Get_U32 (B, Pos, Last, C) then
                              return Database.Status.Failure (Database.Status.Corrupt_File,
                                "truncated foreign-key columns");
                           end if;
                           FK.Referencing_Cols.Append (C);
                        end;
                     end loop;
                     if not Get_U32 (B, Pos, Last, Target_Count) then
                        return Database.Status.Failure (Database.Status.Corrupt_File, "truncated foreign-key catalog");
                     end if;
                     for I in 1 .. Target_Count loop
                        declare
                           C : Natural;
                        begin
                           if not Get_U32 (B, Pos, Last, C) then
                              return Database.Status.Failure (Database.Status.Corrupt_File,
                                "truncated foreign-key columns");
                           end if;
                           FK.Referenced_Cols.Append (C);
                        end;
                     end loop;
                     if not Get_U32  (B,
                       Pos,
                       Last,
                       Action)

                         or else Action >
                          Database.Foreign_Keys.Foreign_Key_Action'Pos
                            (Database.Foreign_Keys.Foreign_Key_Action'Last)
                       or else not Get_U32  (B,
                         Pos,
                         Last,
                         Flag)

                         or else Flag >
                          Database.Foreign_Keys.Foreign_Key_Action'Pos
                            (Database.Foreign_Keys.Foreign_Key_Action'Last)
                       or else not Get_U32 (B, Pos, Last, Ref_Count)
                       or else Ref_Count > 1
                     then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "malformed foreign-key action metadata");
                     end if;
                     FK.On_Delete := Database.Foreign_Keys.Foreign_Key_Action'Val (Action);
                     FK.On_Update := Database.Foreign_Keys.Foreign_Key_Action'Val (Flag);
                     FK.Deferred := Ref_Count /= 0;
                     Current_State.all.Foreign_Keys.Append (FK);
                  end;
               end loop;
            end;
         end if;

         if Pos < Last then
            declare
               Group_Count : Natural;
            begin
               if not Get_U32 (B, Pos, Last, Group_Count) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "truncated check catalog");
               end if;
               for G in 1 .. Group_Count loop
                  declare
                     TC : Table_Checks;
                  Check_Count : Natural;
                  begin
                     if not Get_U32 (B, Pos, Last, TC.Table_Id) or else not Get_U32 (B, Pos, Last, Check_Count) then
                        return Database.Status.Failure (Database.Status.Corrupt_File, "truncated check catalog");
                     end if;
                     for I in 1 .. Check_Count loop
                        declare
                           C : Database.Check_Constraints.Check_Constraint;
                           Name, Image : Unbounded_Wide_Wide_String;
                           Flag : Natural;
                           Expr : Database.Expressions.Expression;
                           ER : Database.Status.Result;
                        begin
                           if not Get_Text  (B,
                             Pos,
                             Last,
                             Name) or else not Get_Text (B,
                             Pos,
                             Last,
                             Image) or else not Get_U32 (B,
                             Pos,
                             Last,
                             Flag) then
                              return Database.Status.Failure (Database.Status.Corrupt_File,
                                "truncated check constraint metadata");
                           end if;
                           ER := Database.Expressions.From_Persistent_Image (To_Wide_Wide_String (Image), Expr);
                           if not Database.Status.Is_Ok (ER) then
                              return Database.Status.Failure (Database.Status.Corrupt_File,
                                "malformed check expression metadata");
                           end if;
                           C.Name := Name;
                           C.Expression := Expr;
                           C.Deferred := Flag /= 0;
                           TC.Checks.Append (C);
                        end;
                     end loop;
                     Current_State.all.Table_Checks_List.Append (TC);
                  end;
               end loop;
            end;
         end if;

         if Pos < Last then
            declare
               Group_Count : Natural;
            begin
               if not Get_U32 (B, Pos, Last, Group_Count) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "truncated generated-column catalog");
               end if;
               for G in 1 .. Group_Count loop
                  declare
                     TG : Table_Generated;
                  Column_Count : Natural;
                  begin
                     if not Get_U32 (B, Pos, Last, TG.Table_Id) or else not Get_U32 (B, Pos, Last, Column_Count) then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "truncated generated-column catalog");
                     end if;
                     for I in 1 .. Column_Count loop
                        declare
                           C : Database.Generated_Columns.Generated_Column;
                           Name, Image : Unbounded_Wide_Wide_String;
                           Kind : Natural;
                           Expr : Database.Expressions.Expression;
                           ER : Database.Status.Result;
                        begin
                           if not Get_U32  (B,
                             Pos,
                             Last,
                             C.Column_Id) or else not Get_Text (B,
                             Pos,
                             Last,
                             Name) or else not Get_Text (B,
                             Pos,
                             Last,
                             Image) or else not Get_U32 (B,
                             Pos,
                             Last,
                             Kind)

                         or else Kind >
                          Database.Generated_Columns.Generated_Column_Kind'Pos
                            (Database.Generated_Columns.Generated_Column_Kind'Last)
                           then
                              return Database.Status.Failure (Database.Status.Corrupt_File,
                                "malformed generated-column metadata");
                           end if;
                           ER := Database.Expressions.From_Persistent_Image (To_Wide_Wide_String (Image), Expr);
                           if not Database.Status.Is_Ok (ER) then
                              return Database.Status.Failure (Database.Status.Corrupt_File,
                                "malformed generated-column expression metadata");
                           end if;
                           C.Name := Name;
                           C.Expression := Expr;
                           C.Kind := Database.Generated_Columns.Generated_Column_Kind'Val (Kind);
                           TG.Columns.Append (C);
                        end;
                     end loop;
                     Current_State.all.Table_Generated_List.Append (TG);
                  end;
               end loop;
            end;
         end if;

         if Pos < Last then
            declare
               View_Count : Natural;
            begin
               if not Get_U32 (B, Pos, Last, View_Count) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "truncated view catalog");
               end if;
               for I in 1 .. View_Count loop
                  declare
                     V : Database.Views.View_Definition;
                  Name : Unbounded_Wide_Wide_String;
                  Id_N : Natural;
                  Image : Unbounded_Wide_Wide_String;
                  QR : Database.Status.Result;
                  begin
                     if not Get_U32 (B, Pos, Last, Id_N) or else not Get_Text (B, Pos, Last, Name) then
                        return Database.Status.Failure (Database.Status.Corrupt_File, "truncated view metadata");
                     end if;
                     if Pos < Last then
                        if not Get_Text (B, Pos, Last, Image) then
                           return Database.Status.Failure (Database.Status.Corrupt_File,
                             "truncated view query metadata");
                        end if;
                        QR := Database.Queries.From_Persistent_Image (To_Wide_Wide_String (Image), V.Query);
                        if not Database.Status.Is_Ok (QR) then
                           return QR;
                        end if;
                     else
                        V.Query := Database.Queries.Empty;
                     end if;
                     V.Id := Database.Views.View_Id (Id_N);
                     V.Name := Name;
                     Current_State.all.Views.Append (V);
                  end;
               end loop;
            end;
         end if;

         if Pos < Last then
            declare
               View_Count : Natural;
            begin
               if not Get_U32 (B, Pos, Last, View_Count) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "truncated materialized-view catalog");
               end if;
               for I in 1 .. View_Count loop
                  declare
                     MV : Database.Materialized_Views.Materialized_View_Definition;
                  Name : Unbounded_Wide_Wide_String;
                  Id_N : Natural;
                  Image : Unbounded_Wide_Wide_String;
                  QR : Database.Status.Result;
                  begin
                     if not Get_U32 (B, Pos, Last, Id_N) or else not Get_Text (B, Pos, Last, Name) then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "truncated materialized-view metadata");
                     end if;
                     if not Get_Text (B, Pos, Last, Image) then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "truncated materialized-view query metadata");
                     end if;
                     QR := Database.Queries.From_Persistent_Image (To_Wide_Wide_String (Image), MV.Query);
                     if not Database.Status.Is_Ok (QR) then
                        return QR;
                     end if;
                     if not Get_U32  (B,
                       Pos,
                       Last,
                       MV.Storage_Table) or else not Get_U32 (B,
                       Pos,
                       Last,
                       MV.Last_Refresh_Commit) then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "truncated materialized-view storage metadata");
                     end if;
                     MV.Id := Database.Materialized_Views.Materialized_View_Id (Id_N);
                     MV.Name := Name;
                     Current_State.all.Materialized_Views.Append (MV);
                  end;
               end loop;
            end;
         end if;

         if Pos < Last then
            declare
               Extra_Count : Natural;
            begin
               if not Get_U32 (B, Pos, Last, Extra_Count) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "truncated index extension catalog");
               end if;
               for E in 1 .. Extra_Count loop
                  declare
                     Table_Id, Index_Id_N, Column_Count, Flag : Natural;
                     Found : Boolean := False;
                  begin
                     if not Get_U32  (B,
                       Pos,
                       Last,
                       Table_Id) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Index_Id_N) or else not Get_U32 (B,
                       Pos,
                       Last,
                       Column_Count) then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "truncated index extension metadata");
                     end if;
                     if Current_State.all.Tables.Length > 0 then
                        for TI in 0 .. Natural (Current_State.all.Tables.Length) - 1 loop
                           if Current_State.all.Tables.Element (TI).Table_Id = Table_Id then
                              declare
                                 S : Database.Schema.Table_Schema := Current_State.all.Tables.Element (TI);
                              begin
                                 if S.Indexes.Length > 0 then
                                    for II in 0 .. Natural (S.Indexes.Length) - 1 loop
                                       if Natural (S.Indexes.Element (II).Id) = Index_Id_N then
                                          declare
                                             IX : Database.Indexes.Index_Metadata := S.Indexes.Element (II);
                                          begin
                                             IX.Column_Ids.Clear;
                                             for C in 1 .. Column_Count loop
                                                declare
                                                   CID : Natural;
                                                begin
                                                   if not Get_U32 (B, Pos, Last, CID) then
                                                      return Database.Status.Failure (Database.Status.Corrupt_File,
                                                        "truncated index column extension metadata");
                                                   end if;
                                                   IX.Column_Ids.Append (CID);
                                                end;
                                             end loop;
                                             if not Get_U32 (B, Pos, Last, Flag) then
                                                return Database.Status.Failure (Database.Status.Corrupt_File,
                                                  "truncated index predicate extension metadata");
                                             end if;
                                             IX.Has_Predicate := Flag /= 0;
                                             if not Get_U32 (B, Pos, Last, Flag) then
                                                return Database.Status.Failure (Database.Status.Corrupt_File,
                                                  "truncated index expression extension metadata");
                                             end if;
                                             IX.Has_Expression := Flag /= 0;
                                             S.Indexes.Replace_Element (II, IX);
                                             Current_State.all.Tables.Replace_Element (TI, S);
                                             Found := True;
                                          end;
                                       end if;
                                    end loop;
                                 end if;
                              end;
                           end if;
                        end loop;
                     end if;
                     if not Found then
                        return Database.Status.Failure (Database.Status.Corrupt_File,
                          "index extension references missing index metadata");
                     end if;
                  end;
               end loop;
            end;
         end if;
      end;
      for S of Current_State.all.Tables loop
         if S.Heap_First_Page /= 0 then
            DB.Version := Natural'Max
              (DB.Version,
               Database.Storage.Table_Heap.Max_Commit_Version
                 (DB.File, Database.Storage.Pages.Page_Id (S.Heap_First_Page)));
         end if;
      end loop;
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.Corrupt_File, "malformed catalog");
   end Load;

   function Table_Count return Natural is (Natural (Current_State.all.Tables.Length));

   function Table_At (Index : Natural) return Database.Schema.Table_Schema is
   begin
      return Current_State.all.Tables.Element (Index);
   end Table_At;

   function Add_Foreign_Key
     (DB         : in out Database.Handle;
      Definition : Database.Foreign_Keys.Foreign_Key_Definition) return Database.Status.Result is
      Referencing_Schema, Referenced_Schema : Database.Schema.Table_Schema;
      R : Database.Status.Result;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      R := Find_By_Id (Definition.Referencing_Table, Referencing_Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Find_By_Id (Definition.Referenced_Table, Referenced_Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Foreign_Keys.Validate_Definition (Definition, Referencing_Schema, Referenced_Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      for Existing of Current_State.all.Foreign_Keys loop
         if Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Existing.Name)
           = Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Definition.Name) then
            return Database.Status.Failure (Database.Status.Already_Exists, "foreign key already exists");
         end if;
      end loop;
      Current_State.all.Foreign_Keys.Append (Definition);
      return Save (DB);
   end Add_Foreign_Key;

   function Foreign_Keys_For_Referencing_Table
     (Table_Id : Natural) return Database.Foreign_Keys.Foreign_Key_Vectors.Vector is
      Result : Database.Foreign_Keys.Foreign_Key_Vectors.Vector;
   begin
      for FK of Current_State.all.Foreign_Keys loop
         if FK.Referencing_Table = Table_Id then
            Result.Append (FK);
         end if;
      end loop;
      return Result;
   end Foreign_Keys_For_Referencing_Table;

   function Foreign_Keys_For_Referenced_Table
     (Table_Id : Natural) return Database.Foreign_Keys.Foreign_Key_Vectors.Vector is
      Result : Database.Foreign_Keys.Foreign_Key_Vectors.Vector;
   begin
      for FK of Current_State.all.Foreign_Keys loop
         if FK.Referenced_Table = Table_Id then
            Result.Append (FK);
         end if;
      end loop;
      return Result;
   end Foreign_Keys_For_Referenced_Table;

   function Add_Check_Constraint
     (DB         : in out Database.Handle;
      Table_Id   : Natural;
      Constraint : Database.Check_Constraints.Check_Constraint) return Database.Status.Result is
      S : Database.Schema.Table_Schema;
      R : Database.Status.Result;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      R := Find_By_Id (Table_Id, S);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Check_Constraints.Validate_Definition (Constraint);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Current_State.all.Table_Checks_List.Length > 0 then
      for I in 0 .. Natural (Current_State.all.Table_Checks_List.Length) - 1 loop
         if Current_State.all.Table_Checks_List.Element (I).Table_Id = Table_Id then
            declare
               T : Table_Checks := Current_State.all.Table_Checks_List.Element (I);
            begin
               T.Checks.Append (Constraint);
               Current_State.all.Table_Checks_List.Replace_Element (I, T);
               return Save (DB);
            end;
         end if;
      end loop;
      end if;
      declare
         T : Table_Checks;
      begin
         T.Table_Id := Table_Id;
         T.Checks.Append (Constraint);
         Current_State.all.Table_Checks_List.Append (T);
      end;
      return Save (DB);
   end Add_Check_Constraint;

   function Check_Constraints_For_Table
     (Table_Id : Natural) return Database.Check_Constraints.Check_Constraint_Vectors.Vector is
      Empty : Database.Check_Constraints.Check_Constraint_Vectors.Vector;
   begin
      for T of Current_State.all.Table_Checks_List loop
         if T.Table_Id = Table_Id then
            return T.Checks;
         end if;
      end loop;
      return Empty;
   end Check_Constraints_For_Table;

   function Add_Generated_Column
     (DB       : in out Database.Handle;
      Table_Id : Natural;
      Column   : Database.Generated_Columns.Generated_Column) return Database.Status.Result is
      S : Database.Schema.Table_Schema;
      R : Database.Status.Result;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      R := Find_By_Id (Table_Id, S);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Generated_Columns.Validate_Definition (Column);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Database.Schema.Find_Column_Id_Position (S, Column.Column_Id) = Natural'Last then
         return Database.Status.Failure (Database.Status.Invalid_Schema, "generated column id is not in table schema");
      end if;
      if Current_State.all.Table_Generated_List.Length > 0 then
         for I in 0 .. Natural (Current_State.all.Table_Generated_List.Length) - 1 loop
            if Current_State.all.Table_Generated_List.Element (I).Table_Id = Table_Id then
               declare
                  T : Table_Generated := Current_State.all.Table_Generated_List.Element (I);
               begin
                  T.Columns.Append (Column);
                  Current_State.all.Table_Generated_List.Replace_Element (I, T);
                  return Save (DB);
               end;
            end if;
         end loop;
      end if;
      declare
         T : Table_Generated;
      begin
         T.Table_Id := Table_Id;
         T.Columns.Append (Column);
         Current_State.all.Table_Generated_List.Append (T);
      end;
      return Save (DB);
   end Add_Generated_Column;

   function Generated_Columns_For_Table
     (Table_Id : Natural) return Database.Generated_Columns.Generated_Column_Vectors.Vector is
      Empty : Database.Generated_Columns.Generated_Column_Vectors.Vector;
   begin
      for T of Current_State.all.Table_Generated_List loop
         if T.Table_Id = Table_Id then
            return T.Columns;
         end if;
      end loop;
      return Empty;
   end Generated_Columns_For_Table;

   function Add_View
     (DB   : in out Database.Handle;
      View : in out Database.Views.View_Definition) return Database.Status.Result is
      R : Database.Status.Result := Database.Views.Validate (View);
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      for V of Current_State.all.Views loop
         if Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Name)
           = Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (View.Name) then
            return Database.Status.Failure (Database.Status.Already_Exists, "view already exists");
         end if;
      end loop;
      View.Id := Database.Views.View_Id (Natural (Current_State.all.Views.Length) + 1);
      Current_State.all.Views.Append (View);
      return Save (DB);
   end Add_View;

   function Find_View
     (Name : Wide_Wide_String;
      View : out Database.Views.View_Definition) return Database.Status.Result is
   begin
      for V of Current_State.all.Views loop
         if Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Name) = Name then
            View := V;
            return Database.Status.Success;
         end if;
      end loop;
      return Database.Status.Failure (Database.Status.Not_Found, "view not found");
   end Find_View;

   function View_Count return Natural is
   begin
      return Natural (Current_State.all.Views.Length);
   end View_Count;

   function View_At (Index : Natural) return Database.Views.View_Definition is
   begin
      return Current_State.all.Views.Element (Index);
   end View_At;

   function Add_Materialized_View
     (DB   : in out Database.Handle;
      View : in out Database.Materialized_Views.Materialized_View_Definition) return Database.Status.Result is
      R : Database.Status.Result := Database.Materialized_Views.Validate (View);
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      for V of Current_State.all.Materialized_Views loop
         if Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Name)
           = Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (View.Name) then
            return Database.Status.Failure (Database.Status.Already_Exists, "materialized view already exists");
         end if;
      end loop;
      View.Id  :=
        Database.Materialized_Views.Materialized_View_Id (Natural (Current_State.all.Materialized_Views.Length) + 1);
      Current_State.all.Materialized_Views.Append (View);
      return Save (DB);
   end Add_Materialized_View;

   function Find_Materialized_View
     (Name : Wide_Wide_String;
      View : out Database.Materialized_Views.Materialized_View_Definition) return Database.Status.Result is
   begin
      for V of Current_State.all.Materialized_Views loop
         if Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (V.Name) = Name then
            View := V;
            return Database.Status.Success;
         end if;
      end loop;
      return Database.Status.Failure (Database.Status.Not_Found, "materialized view not found");
   end Find_Materialized_View;

   function Materialized_View_Count return Natural is
   begin
      return Natural (Current_State.all.Materialized_Views.Length);
   end Materialized_View_Count;

   function Materialized_View_At
     (Index : Natural) return Database.Materialized_Views.Materialized_View_Definition is
   begin
      return Current_State.all.Materialized_Views.Element (Index);
   end Materialized_View_At;

   function Update_Materialized_View
     (DB   : in out Database.Handle;
      View : Database.Materialized_Views.Materialized_View_Definition) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      if Current_State.all.Materialized_Views.Length > 0 then
         for I in 0 .. Natural (Current_State.all.Materialized_Views.Length) - 1 loop
            if Current_State.all.Materialized_Views.Element (I).Id = View.Id then
               Current_State.all.Materialized_Views.Replace_Element (I, View);
               return Save (DB);
            end if;
         end loop;
      end if;
      return Database.Status.Failure (Database.Status.Not_Found, "materialized view not found");
   end Update_Materialized_View;

   function Same_Key (Schema : Database.Schema.Table_Schema; Left, Right : Database.Rows.Row) return Boolean is
      Pos : Natural;
      Any_Key : Boolean := False;
   begin
      for C of Schema.Columns loop
         if C.Primary_Key then
            Any_Key := True;
            Pos := Database.Schema.Find_Column_Id_Position (Schema, C.Id);
            if Pos >= Database.Rows.Column_Count (Left) or else Pos >= Database.Rows.Column_Count (Right) then
               return False;
            end if;
            if not Database.Values.Equal (Database.Rows.Get (Left, Pos), Database.Rows.Get (Right, Pos)) then
               return False;
            end if;
         end if;
      end loop;
      return Any_Key;
   end Same_Key;

   function Add_Full_Text_Index
     (DB       : in out Database.Handle;
      Metadata : Database.Full_Text.Indexes.Full_Text_Index_Metadata) return Database.Status.Result is
      M : Database.Full_Text.Indexes.Full_Text_Index_Metadata := Metadata;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      for Existing of Current_State.all.Full_Text_Indexes loop
         if To_Wide_Wide_String (Existing.Name) = To_Wide_Wide_String (M.Name) then
            return Database.Status.Failure (Database.Status.Already_Exists, "full-text index already exists");
         end if;
      end loop;
      if M.Id = 0 then
         M.Id  :=
           Database.Full_Text.Indexes.Full_Text_Index_Id (Natural (Current_State.all.Full_Text_Indexes.Length) + 1);
      end if;
      M.Owner_Key := 0;
      Current_State.all.Full_Text_Indexes.Append (M);
      return Save (DB);
   end Add_Full_Text_Index;

   function Remove_Full_Text_Index
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      if Current_State.all.Full_Text_Indexes.Length > 0 then
         for I in 0 .. Natural (Current_State.all.Full_Text_Indexes.Length) - 1 loop
            if To_Wide_Wide_String (Current_State.all.Full_Text_Indexes.Element (I).Name) = Name then
               Current_State.all.Full_Text_Indexes.Delete (I);
               return Save (DB);
            end if;
         end loop;
      end if;
      return Database.Status.Failure (Database.Status.Not_Found, "full-text index not found");
   end Remove_Full_Text_Index;

   function Full_Text_Index_Definitions return Database.Full_Text.Indexes.Metadata_Vectors.Vector is
   begin
      return Current_State.all.Full_Text_Indexes;
   end Full_Text_Index_Definitions;

   procedure Register_Row (Table_Id : Natural; Row : Database.Rows.Row) is
   begin
      Current_State.all.Cached_Rows.Append (Catalog_Row'(Table_Id => Table_Id, Row => Row));
   end Register_Row;

   procedure Remove_Row (Table_Id : Natural; Schema : Database.Schema.Table_Schema; Key_Row : Database.Rows.Row) is
   begin
      if Current_State.all.Cached_Rows.Length = 0 then
         return;
      end if;
      for I in reverse 0 .. Natural (Current_State.all.Cached_Rows.Length) - 1 loop
         if Current_State.all.Cached_Rows.Element  (I).Table_Id = Table_Id and then Same_Key (Schema,
           Current_State.all.Cached_Rows.Element (I).Row,
           Key_Row) then
            Current_State.all.Cached_Rows.Delete (I);
         end if;
      end loop;
   end Remove_Row;

   procedure Replace_Row  (Table_Id : Natural; Schema : Database.Schema.Table_Schema; Old_Row,
     New_Row : Database.Rows.Row) is
   begin
      Remove_Row (Table_Id, Schema, Old_Row);
      Register_Row (Table_Id, New_Row);
   end Replace_Row;

   function Rows_For_Table (Table_Id : Natural) return Database.Foreign_Keys.Row_Vectors.Vector is
      Result : Database.Foreign_Keys.Row_Vectors.Vector;
   begin
      for R of Current_State.all.Cached_Rows loop
         if R.Table_Id = Table_Id then
            Result.Append (R.Row);
         end if;
      end loop;
      return Result;
   end Rows_For_Table;

end Database.Catalog;
