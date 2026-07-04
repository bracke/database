with Database.Rows;
with Database.Schema;
with Database.Storage.File_IO;
with Database.Storage.Free_List;
with Database.Storage.Pages;
with Database.Status;
with Database.Storage.Record_Format;
with Database.Transactions;
with Database.Indexes;
with Database.Visibility;
with Database.Versioning;

package body Database.Storage.Table_Heap is
   use Database.Storage.Pages;

   Slot_Header : constant Natural := 21;
   --  Flags + created tx/version + deleted tx/version + u32 length.

   procedure Put_U32 (B : in out Page_Buffer; Offset : Natural; V : Natural) is
   begin
      B (Offset) := Byte ((V / 16#1000000#) mod 256);
      B (Offset + 1) := Byte ((V / 16#10000#) mod 256);
      B (Offset + 2) := Byte ((V / 16#100#) mod 256);
      B (Offset + 3) := Byte (V mod 256);
   end Put_U32;
   function Get_U32 (B : Page_Buffer; Offset : Natural) return Natural is
   begin
      return Natural (B (Offset))*16#1000000#+Natural (B (Offset + 1))*16#10000#+Natural (B (Offset
        + 2))*16#100#+Natural (B (Offset + 3));
   end Get_U32;

   function Metadata_At
     (P : Page; Offset : Natural) return Database.Versioning.Row_Version_Metadata is
      Base : constant Natural := Header_Size + Offset;
      Flags_Byte : constant Byte := P.Buffer (Base);
   begin
      return
        (Created_By_Tx    => Get_U32 (P.Buffer, Base + 1),
         Created_Version  => Get_U32 (P.Buffer, Base + 5),
         Deleted_By_Tx    => Get_U32 (P.Buffer, Base + 9),
         Deleted_Version  => Get_U32 (P.Buffer, Base + 13),
         Previous_Version => Database.Indexes.Invalid_Row_Reference,
         Flags            =>
           (Committed => True,
            Deleted   => (Flags_Byte and Byte (1)) /= Byte (0),
            Tombstone => False));
   end Metadata_At;

   procedure Put_Metadata
     (P        : in out Page;
      Offset   : Natural;
      Metadata : Database.Versioning.Row_Version_Metadata) is
      Base : constant Natural := Header_Size + Offset;
   begin
      P.Buffer (Base) := (if Metadata.Flags.Deleted then Byte (1) else Byte (0));
      Put_U32 (P.Buffer, Base + 1, Metadata.Created_By_Tx);
      Put_U32 (P.Buffer, Base + 5, Metadata.Created_Version);
      Put_U32 (P.Buffer, Base + 9, Metadata.Deleted_By_Tx);
      Put_U32 (P.Buffer, Base + 13, Metadata.Deleted_Version);
   end Put_Metadata;

   function Slot_Length (P : Page; Offset : Natural) return Natural is
   begin
      return Get_U32 (P.Buffer, Header_Size + Offset + 17);
   end Slot_Length;

   function Create_Heap
     (F          : in out Database.Storage.File_IO.File_Handle;
      Allocator  : in out Database.Storage.Free_List.Allocator;
      First_Page : out Page_Id) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
   begin
      R := Database.Storage.Free_List.Allocate (Allocator, F, Table_Heap_Page, P);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      First_Page := Get_Id (P);
      return Database.Status.Success;
   end Create_Heap;

   function Append_Row
     (Tx         : in out Database.Transactions.Transaction;
      F          : in out Database.Storage.File_IO.File_Handle;
      Allocator  : in out Database.Storage.Free_List.Allocator;
      First_Page : in out Page_Id;
      Schema     : Database.Schema.Table_Schema;
      Row        : Database.Rows.Row;
      Ref        : out Database.Indexes.Row_Reference) return Database.Status.Result is
      Enc : Database.Storage.Record_Format.Byte_Vector;
      R : Database.Status.Result;
      P : Page;
      Id : Page_Id;
   begin
      Ref := Database.Indexes.Invalid_Row_Reference;
      R := Database.Storage.Record_Format.Serialize (Schema, Row, Enc);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if Enc.Last + Slot_Header > Payload_Capacity then
         return Database.Status.Failure (Database.Status.Row_Too_Large, "row does not fit table heap page");
      end if;
      if First_Page = Invalid_Page_Id then
         R := Create_Heap (F, Allocator, First_Page);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      Id := First_Page;
      loop
         R := Database.Storage.File_IO.Read_Page (F, Id, Table_Heap_Page, P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         if Used (P) + Slot_Header + Enc.Last <= Payload_Capacity then
            declare
               Off : constant Natural := Header_Size + Used (P);
            begin
               Ref := (Page => Get_Id (P), Slot_Offset => Used (P));
               Put_Metadata
                 (P, Used (P),
                  Database.Versioning.New_Uncommitted
                    (Database.Transactions.Id (Tx),
                     Database.Transactions.Snapshot_Version (Tx) + 1));
               Put_U32 (P.Buffer, Off + 17, Enc.Last);
               for I in 0 .. Enc.Last - 1 loop
                  P.Buffer (Off + Slot_Header + I) := Enc.Data (I);
               end loop;
               Set_Used (P, Used (P) + Slot_Header + Enc.Last);
               return Database.Transactions.Write_Page (Tx, P);
            end;
         elsif Get_Next (P) = Invalid_Page_Id then
            declare
               N : Page;
            begin
               R := Database.Transactions.Write_Page (Tx, P);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               R := Database.Storage.Free_List.Allocate (Allocator, F, Table_Heap_Page, N);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               Set_Next (P, Get_Id (N));
               R := Database.Transactions.Write_Page (Tx, P);
               if not Database.Status.Is_Ok (R) then
                  return R;
               end if;
               Id := Get_Id (N);
            end;
         else
            Id := Get_Next (P);
         end if;
      end loop;
   end Append_Row;

   function Decode_Row_At
     (P      : Page;
      Offset : Natural;
      Schema : Database.Schema.Table_Schema;
      C      : in out Heap_Cursor) return Database.Status.Result is
      Len : Natural;
   begin
      if Offset + Slot_Header > Used (P) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "slot header beyond page payload");
      end if;
      Len := Slot_Length (P, Offset);
      if Len > Payload_Capacity or else Offset + Slot_Header + Len > Used (P) then
         return Database.Status.Failure (Database.Status.Corrupt_File, "slot length beyond page payload");
      end if;
      if Len = 0 then
         declare
            Empty : Byte_Array (1 .. 0);
         begin
            return Database.Storage.Record_Format.Deserialize (Schema, Empty, C.Row);
         end;
      else
         declare
            D : Byte_Array (0 .. Len - 1);
         begin
            for I in 0 .. Len - 1 loop
               D (I) := P.Buffer (Header_Size + Offset + Slot_Header + I);
            end loop;
            return Database.Storage.Record_Format.Deserialize (Schema, D, C.Row);
         end;
      end if;
   end Decode_Row_At;

   function Read_Visible_At
     (P      : Page;
      Offset : Natural;
      Schema : Database.Schema.Table_Schema;
      C      : in out Heap_Cursor) return Database.Status.Result is
      M : Database.Versioning.Row_Version_Metadata;
   begin
      M := Metadata_At (P, Offset);
      if M.Flags.Deleted then
         C.Has_Row := False;
         return Database.Status.Success;
      end if;
      declare
         R : constant Database.Status.Result := Decode_Row_At (P, Offset, Schema, C);
      begin
         if Database.Status.Is_Ok (R) then
            C.Has_Row := True;
         end if;
         return R;
      end;
   end Read_Visible_At;

   function Read_Visible_At
     (Tx     : in out Database.Transactions.Transaction;
      P      : Page;
      Offset : Natural;
      Schema : Database.Schema.Table_Schema;
      C      : in out Heap_Cursor) return Database.Status.Result is
      M : Database.Versioning.Row_Version_Metadata;
   begin
      M := Metadata_At (P, Offset);
      if not Database.Visibility.Is_Visible (Tx, M) then
         C.Has_Row := False;
         return Database.Status.Success;
      end if;
      declare
         R : constant Database.Status.Result := Decode_Row_At (P, Offset, Schema, C);
      begin
         if Database.Status.Is_Ok (R) then
            C.Has_Row := True;
         end if;
         return R;
      end;
   end Read_Visible_At;

   function Advance_To_Row
     (F      : in out Database.Storage.File_IO.File_Handle;
      Schema : Database.Schema.Table_Schema;
      Cursor : in out Heap_Cursor) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
      Len : Natural;
   begin
      while Cursor.Current_Page /= Invalid_Page_Id loop
         R := Database.Storage.File_IO.Read_Page (F, Cursor.Current_Page, Table_Heap_Page, P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         while Cursor.Slot_Offset < Used (P) loop
            R := Read_Visible_At (P, Cursor.Slot_Offset, Schema, Cursor);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Len := Slot_Length (P, Cursor.Slot_Offset);
            if Cursor.Has_Row then
               return Database.Status.Success;
            end if;
            Cursor.Slot_Offset := Cursor.Slot_Offset + Slot_Header + Len;
         end loop;
         Cursor.Current_Page := Get_Next (P);
         Cursor.Slot_Offset := 0;
      end loop;
      Cursor.Has_Row := False;
      return Database.Status.Success;
   end Advance_To_Row;

   function Advance_To_Row
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Schema : Database.Schema.Table_Schema;
      Cursor : in out Heap_Cursor) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
      Len : Natural;
   begin
      while Cursor.Current_Page /= Invalid_Page_Id loop
         R := Database.Storage.File_IO.Read_Page (F, Cursor.Current_Page, Table_Heap_Page, P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         while Cursor.Slot_Offset < Used (P) loop
            R := Read_Visible_At (Tx, P, Cursor.Slot_Offset, Schema, Cursor);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
            Len := Slot_Length (P, Cursor.Slot_Offset);
            if Cursor.Has_Row then
               return Database.Status.Success;
            end if;
            Cursor.Slot_Offset := Cursor.Slot_Offset + Slot_Header + Len;
         end loop;
         Cursor.Current_Page := Get_Next (P);
         Cursor.Slot_Offset := 0;
      end loop;
      Cursor.Has_Row := False;
      return Database.Status.Success;
   end Advance_To_Row;

   function Read_At
     (F      : in out Database.Storage.File_IO.File_Handle;
      Ref    : Database.Indexes.Row_Reference;
      Schema : Database.Schema.Table_Schema;
      Row    : out Database.Rows.Row) return Database.Status.Result is
      P : Page;
      C : Heap_Cursor;
      R : Database.Status.Result;
   begin
      if Ref.Page = Invalid_Page_Id then
         return Database.Status.Failure (Database.Status.Not_Found, "invalid row reference");
      end if;
      R := Database.Storage.File_IO.Read_Page (F, Ref.Page, Table_Heap_Page, P);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      C := (Current_Page => Ref.Page, Slot_Offset => Ref.Slot_Offset, Has_Row => False, Row => <>);
      R := Read_Visible_At (P, Ref.Slot_Offset, Schema, C);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if not C.Has_Row then
         return Database.Status.Failure (Database.Status.Not_Found, "row reference points to deleted row");
      end if;
      Row := C.Row;
      return Database.Status.Success;
   end Read_At;

   function Read_At
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Ref    : Database.Indexes.Row_Reference;
      Schema : Database.Schema.Table_Schema;
      Row    : out Database.Rows.Row) return Database.Status.Result is
      P : Page;
      C : Heap_Cursor;
      R : Database.Status.Result;
   begin
      if Ref.Page = Invalid_Page_Id then
         return Database.Status.Failure (Database.Status.Not_Found, "invalid row reference");
      end if;
      R := Database.Storage.File_IO.Read_Page (F, Ref.Page, Table_Heap_Page, P);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      C := (Current_Page => Ref.Page, Slot_Offset => Ref.Slot_Offset, Has_Row => False, Row => <>);
      R := Read_Visible_At (Tx, P, Ref.Slot_Offset, Schema, C);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      if not C.Has_Row then
         return Database.Status.Failure (Database.Status.Not_Found, "row reference is not visible in snapshot");
      end if;
      Row := C.Row;
      return Database.Status.Success;
   end Read_At;

   function Scan_First
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Page_Id;
      Schema     : Database.Schema.Table_Schema;
      Cursor     : out Heap_Cursor) return Database.Status.Result is
   begin
      Cursor := (Current_Page => First_Page, Slot_Offset => 0, Has_Row => False, Row => <>);
      return Advance_To_Row (F, Schema, Cursor);
   end Scan_First;

   function Scan_First
     (Tx         : in out Database.Transactions.Transaction;
      F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Page_Id;
      Schema     : Database.Schema.Table_Schema;
      Cursor     : out Heap_Cursor) return Database.Status.Result is
   begin
      Cursor := (Current_Page => First_Page, Slot_Offset => 0, Has_Row => False, Row => <>);
      return Advance_To_Row (Tx, F, Schema, Cursor);
   end Scan_First;

   function Scan_Next
     (F      : in out Database.Storage.File_IO.File_Handle;
      Schema : Database.Schema.Table_Schema;
      Cursor : in out Heap_Cursor) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
      Len : Natural;
   begin
      if not Cursor.Has_Row then
         return Database.Status.Success;
      end if;
      R := Database.Storage.File_IO.Read_Page (F, Cursor.Current_Page, Table_Heap_Page, P);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Len := Slot_Length (P, Cursor.Slot_Offset);
      Cursor.Slot_Offset := Cursor.Slot_Offset + Slot_Header + Len;
      Cursor.Has_Row := False;
      return Advance_To_Row (F, Schema, Cursor);
   end Scan_Next;

   function Scan_Next
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Schema : Database.Schema.Table_Schema;
      Cursor : in out Heap_Cursor) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
      Len : Natural;
   begin
      if not Cursor.Has_Row then
         return Database.Status.Success;
      end if;
      R := Database.Storage.File_IO.Read_Page (F, Cursor.Current_Page, Table_Heap_Page, P);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      Len := Slot_Length (P, Cursor.Slot_Offset);
      Cursor.Slot_Offset := Cursor.Slot_Offset + Slot_Header + Len;
      Cursor.Has_Row := False;
      return Advance_To_Row (Tx, F, Schema, Cursor);
   end Scan_Next;

   function Delete_At
     (Tx     : in out Database.Transactions.Transaction;
      F      : in out Database.Storage.File_IO.File_Handle;
      Cursor : Heap_Cursor) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
   begin
      if not Cursor.Has_Row then
         return Database.Status.Failure (Database.Status.Not_Found, "cursor does not identify row");
      end if;
      R := Database.Storage.File_IO.Read_Page (F, Cursor.Current_Page, Table_Heap_Page, P);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      declare
         M : Database.Versioning.Row_Version_Metadata := Metadata_At (P, Cursor.Slot_Offset);
      begin
         Database.Versioning.Mark_Deleted
           (M, Database.Transactions.Id (Tx),
            Database.Transactions.Snapshot_Version (Tx) + 1);
         Put_Metadata (P, Cursor.Slot_Offset, M);
      end;
      Set_Used (P, Used (P));
      return Database.Transactions.Write_Page (Tx, P);
   end Delete_At;

   function Max_Commit_Version
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id) return Natural is
      Current : Page_Id := First_Page;
      P       : Page;
      R       : Database.Status.Result;
      Off     : Natural;
      Len     : Natural;
      Max_V   : Natural := 0;
   begin
      while Current /= Invalid_Page_Id loop
         R := Database.Storage.File_IO.Read_Page (F, Current, Table_Heap_Page, P);
         if not Database.Status.Is_Ok (R) then
            return Max_V;
         end if;
         Off := 0;
         while Off < Used (P) loop
            exit when Off + Slot_Header > Used (P);
            Len := Slot_Length (P, Off);
            exit when Len > Payload_Capacity or else Off + Slot_Header + Len > Used (P);
            declare
               M : constant Database.Versioning.Row_Version_Metadata := Metadata_At (P, Off);
            begin
               Max_V := Natural'Max (Max_V, M.Created_Version);
               Max_V := Natural'Max (Max_V, M.Deleted_Version);
            end;
            Off := Off + Slot_Header + Len;
         end loop;
         Current := Get_Next (P);
      end loop;
      return Max_V;
   exception
      when others =>
         return Max_V;
   end Max_Commit_Version;

   function Validate_Row_Slots
     (Page : Database.Storage.Pages.Page) return Database.Status.Result is
      Off : Natural := 0;
      Len : Natural;
   begin
      while Off < Used (Page) loop
         if Off + Slot_Header > Used (Page) then
            return Database.Status.Failure (Database.Status.Corrupt_File, "truncated row slot header");
         end if;
         if Page.Buffer (Header_Size + Off) > 1 then
            return Database.Status.Failure (Database.Status.Corrupt_File, "invalid MVCC row flags");
         end if;
         Len := Slot_Length (Page, Off);
         if Len > Payload_Capacity or else Off + Slot_Header + Len > Used (Page) then
            return Database.Status.Failure (Database.Status.Corrupt_File, "row slot payload out of bounds");
         end if;
         Off := Off + Slot_Header + Len;
      end loop;
      return Database.Status.Success;
   exception
      when others => return Database.Status.Failure (Database.Status.Corrupt_File, "malformed row slots");
   end Validate_Row_Slots;

   function Validate_Row_Payloads
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema) return Database.Status.Result is
      C : Heap_Cursor;
      R : Database.Status.Result;
   begin
      if First_Page = Invalid_Page_Id then
         return Database.Status.Success;
      end if;
      R := Scan_First (F, First_Page, Schema, C);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      while C.Has_Row loop
         R := Scan_Next (F, Schema, C);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end loop;
      return Database.Status.Success;
   end Validate_Row_Payloads;

   function Validate_Table_Heap
     (F          : in out Database.Storage.File_IO.File_Handle;
      First_Page : Database.Storage.Pages.Page_Id;
      Schema     : Database.Schema.Table_Schema) return Database.Status.Result is
      P : Page;
      R : Database.Status.Result;
      Id : Page_Id := First_Page;
      Count : constant Natural := Database.Storage.File_IO.Page_Count (F);
      Guard : Natural := 0;
   begin
      if First_Page = Invalid_Page_Id then
         return Database.Status.Success;
      end if;
      while Id /= Invalid_Page_Id loop
         if Natural (Id) >= Count then
            return Database.Status.Failure (Database.Status.Corrupt_File, "heap page reference out of range");
         end if;
         if Guard > Count then
            return Database.Status.Failure (Database.Status.Corrupt_File, "heap page chain loop");
         end if;
         R := Database.Storage.File_IO.Read_Page (F, Id, Table_Heap_Page, P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         R := Validate_Row_Slots (P);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
         Id := Get_Next (P);
         Guard := Guard + 1;
      end loop;
      return Validate_Row_Payloads (F, First_Page, Schema);
   end Validate_Table_Heap;
end Database.Storage.Table_Heap;
