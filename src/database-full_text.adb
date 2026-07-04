with Database.Full_Text.Indexes;
with Database.Full_Text.Postings;
with Database.Full_Text.Queries;
with Database.Full_Text.Ranking;
with Ada.Characters.Conversions;
with Ada.Wide_Wide_Text_IO;
with Ada.Directories;
with Ada.Containers;
with Database.Catalog;
with Database.Types;
with Database.Values;
with Database.UUIDs;
with Database.Foreign_Keys;
with Database.MVCC;
with Database.Versioning;
with Database.Storage.Table_Heap;
with Database.Storage.Pages;
with Database.Storage.File_IO;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Full_Text is
   use type Database.MVCC.Transaction_Lifecycle;
   use type Database.Full_Text.Queries.Query_Kind;
   use type Ada.Containers.Count_Type;
   use Ada.Strings.Wide_Wide_Unbounded;

   type Full_Text_State is record
      Key     : Natural := 0;
      FT_Indexes : Database.Full_Text.Indexes.Index_Vectors.Vector;
   end record;

   package State_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Full_Text_State);

   --  The currently selected handle's indexes are kept in FT_Indexes for the
   --  existing implementation paths. Before selecting another handle the
   --  vector is stored in States;
   --  selecting a handle restores only that
   --  handle's vector. This avoids one process-global full-text index list
   --  shared by all open handles while preserving the established public API.
   FT_Indexes : Database.Full_Text.Indexes.Index_Vectors.Vector;
   States  : State_Vectors.Vector;
   Current_State_Key : Natural := 0;

   function State_Position (State_Key : Natural) return Natural is
   begin
      if States.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (States.Length) - 1 loop
         if States.Element (I).Key = State_Key then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end State_Position;

   procedure Store_Current_State is
      Pos : Natural;
      S   : Full_Text_State;
   begin
      if Current_State_Key = 0 then
         return;
      end if;

      Pos := State_Position (Current_State_Key);
      S.Key := Current_State_Key;
      S.FT_Indexes := FT_Indexes;

      if Pos = Natural'Last then
         States.Append (S);
      else
         States.Replace_Element (Pos, S);
      end if;
   end Store_Current_State;

   procedure Load_State (State_Key : Natural) is
      Pos : constant Natural := State_Position (State_Key);
      S   : Full_Text_State;
   begin
      FT_Indexes.Clear;
      if Pos = Natural'Last then
         S.Key := State_Key;
         States.Append (S);
      else
         FT_Indexes := States.Element (Pos).FT_Indexes;
      end if;
   end Load_State;

   procedure Select_Database (State_Key : Natural) is
   begin
      if State_Key = Current_State_Key then
         return;
      end if;

      Store_Current_State;
      Current_State_Key := State_Key;
      Load_State (State_Key);
   end Select_Database;

   procedure Select_From_Transaction (Tx : in out Database.Transactions.Transaction) is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
   begin
      if DB /= null then
         Select_Database (Database.Full_Text_State_Key (DB.all));
      end if;
   end Select_From_Transaction;

   function Find_Index (Name : Wide_Wide_String) return Natural is
   begin
      if FT_Indexes.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (FT_Indexes.Length) - 1 loop
         if FT_Indexes.Element (I).Metadata.Owner_Key = Current_State_Key
           and then To_Wide_Wide_String (FT_Indexes.Element (I).Metadata.Name) = Name
         then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Index;

   function Index_Visible
     (Tx : Database.Transactions.Transaction;
      IX : Database.Full_Text.Indexes.Full_Text_Index) return Boolean is
      use type Database.Versioning.Transaction_Id;
      use type Database.Versioning.Commit_Version;
   begin
      if IX.Metadata.Created_By /= Database.Versioning.No_Transaction
        and then IX.Metadata.Created_By /= Database.Transactions.Id (Tx)
      then
         return False;
      end if;

      if IX.Metadata.Created_At /= Database.Versioning.No_Version
        and then IX.Metadata.Created_At > Database.Transactions.Snapshot_Version (Tx)
      then
         return False;
      end if;

      if IX.Metadata.Deleted_By = Database.Transactions.Id (Tx) then
         return False;
      elsif IX.Metadata.Deleted_By /= Database.Versioning.No_Transaction then
         if IX.Metadata.Deleted_At = Database.Versioning.No_Version then
            return True;
         end if;
         return IX.Metadata.Deleted_At > Database.Transactions.Snapshot_Version (Tx);
      end if;

      return True;
   end Index_Visible;

   function Index_Committed_Visible
     (IX : Database.Full_Text.Indexes.Full_Text_Index) return Boolean is
      use type Database.Versioning.Transaction_Id;
   begin
      return IX.Metadata.Created_By = Database.Versioning.No_Transaction
        and then IX.Metadata.Deleted_By = Database.Versioning.No_Transaction;
   end Index_Committed_Visible;

   procedure Mix (H : in out Natural; N : Natural) is
      M : constant Long_Long_Integer := 2_147_483_647;
      V : constant Long_Long_Integer  :=
        (Long_Long_Integer (H) * 131 + Long_Long_Integer (N) + 17) mod M;
   begin
      H := Natural (V);
      if H = 0 then
         H := 1;
      end if;
   end Mix;

   procedure Mix_Text (H : in out Natural; S : Wide_Wide_String) is
   begin
      Mix (H, S'Length);
      for Ch of S loop
         Mix (H, Wide_Wide_Character'Pos (Ch));
      end loop;
   end Mix_Text;

   procedure Mix_Value (H : in out Natural; V : Database.Values.Value) is
      use type Database.Types.Value_Kind;
   begin
      Mix (H, Database.Types.Value_Kind'Pos (V.Kind));
      case V.Kind is
         when Database.Types.Null_Value =>
            null;
         when Database.Types.Boolean_Value =>
            Mix (H, (if V.Bool then 1 else 0));
         when Database.Types.Integer_Value =>
            Mix_Text (H, Integer'Wide_Wide_Image (V.Int));
         when Database.Types.Long_Integer_Value =>
            Mix_Text (H, Long_Long_Integer'Wide_Wide_Image (V.Long_Int));
         when Database.Types.Float_Value =>
            Mix_Text (H, Long_Float'Wide_Wide_Image (V.Flt));
         when Database.Types.Decimal_Value =>
            Mix_Text (H, Long_Long_Integer'Wide_Wide_Image (V.Dec.Coefficient));
            Mix (H, V.Dec.Scale);
         when Database.Types.Text_Value =>
            Mix_Text (H, To_Wide_Wide_String (V.Text));
         when Database.Types.Blob_Value =>
            Mix (H, Natural (V.Blob.Length));
            for B of V.Blob loop
               Mix (H, B);
            end loop;
         when Database.Types.Timestamp_Value =>
            Mix_Text (H, Integer'Wide_Wide_Image (V.Time.Year));
            Mix (H, V.Time.Month);
            Mix (H, V.Time.Day);
            Mix (H, V.Time.Hour);
            Mix (H, V.Time.Minute);
            Mix (H, V.Time.Second);
            Mix (H, V.Time.Nanosecond);
         when Database.Types.Enum_Value =>
            Mix_Text (H, To_Wide_Wide_String (V.Enum_Text));
         when Database.Types.Date_Value => Mix_Text  (H,
           Integer'Wide_Wide_Image (V.Date.Year));
           Mix (H,
           V.Date.Month);
           Mix (H,
           V.Date.Day);
         when Database.Types.Time_Value => Mix  (H,
           V.Clock_Time.Hour);
           Mix (H,
           V.Clock_Time.Minute);
           Mix (H,
           V.Clock_Time.Second);
           Mix (H,
           V.Clock_Time.Nanosecond);
         when Database.Types.Date_Time_Value => Mix_Text  (H,
           Integer'Wide_Wide_Image (V.Date_Time.Date_Part.Year));
           Mix (H,
           V.Date_Time.Date_Part.Month);
           Mix (H,
           V.Date_Time.Date_Part.Day);
           Mix (H,
           V.Date_Time.Time_Part.Hour);
           Mix (H,
           V.Date_Time.Time_Part.Minute);
           Mix (H,
           V.Date_Time.Time_Part.Second);
           Mix (H,
           V.Date_Time.Time_Part.Nanosecond);
         when Database.Types.Duration_Value => Mix_Text  (H,
           Long_Long_Integer'Wide_Wide_Image (V.Time_Span.Seconds));
           Mix (H,
           V.Time_Span.Nanoseconds);
         when Database.Types.UUID_Value => for B of V.UUID loop Mix (H, B);
         end loop;
         when Database.Types.Array_Value => Mix_Text (H, To_Wide_Wide_String (V.Array_Text));
      end case;
   end Mix_Value;

   procedure Append_Value_Key
     (S : in out Unbounded_Wide_Wide_String;
      V : Database.Values.Value) is
   begin
      Append (S, Database.Types.Value_Kind'Wide_Wide_Image (V.Kind));
      Append (S, ":");
      case V.Kind is
         when Database.Types.Null_Value =>
            Append (S, "null");
         when Database.Types.Boolean_Value =>
            Append (S, Boolean'Wide_Wide_Image (V.Bool));
         when Database.Types.Integer_Value =>
            Append (S, Integer'Wide_Wide_Image (V.Int));
         when Database.Types.Long_Integer_Value =>
            Append (S, Long_Long_Integer'Wide_Wide_Image (V.Long_Int));
         when Database.Types.Float_Value =>
            Append (S, Long_Float'Wide_Wide_Image (V.Flt));
         when Database.Types.Decimal_Value =>
            Append (S, Long_Long_Integer'Wide_Wide_Image (V.Dec.Coefficient));
            Append (S, "/");
            Append (S, Natural'Wide_Wide_Image (V.Dec.Scale));
         when Database.Types.Text_Value =>
            Append (S, To_Wide_Wide_String (V.Text));
         when Database.Types.Blob_Value =>
            Append (S, Natural'Wide_Wide_Image (Natural (V.Blob.Length)));
            for B of V.Blob loop
               Append (S, ",");
               Append (S, Natural'Wide_Wide_Image (B));
            end loop;
         when Database.Types.Timestamp_Value =>
            Append (S, Integer'Wide_Wide_Image (V.Time.Year));
            Append (S, "-");
            Append (S, Integer'Wide_Wide_Image (V.Time.Month));
            Append (S, "-");
            Append (S, Integer'Wide_Wide_Image (V.Time.Day));
            Append (S, "T");
            Append (S, Integer'Wide_Wide_Image (V.Time.Hour));
            Append (S, ":");
            Append (S, Integer'Wide_Wide_Image (V.Time.Minute));
            Append (S, ":");
            Append (S, Integer'Wide_Wide_Image (V.Time.Second));
            Append (S, ".");
            Append (S, Natural'Wide_Wide_Image (V.Time.Nanosecond));
         when Database.Types.Enum_Value =>
            Append (S, To_Wide_Wide_String (V.Enum_Text));
         when Database.Types.Date_Value => Append (S, Integer'Wide_Wide_Image (V.Date.Year));
         Append (S, "-");
         Append (S, Integer'Wide_Wide_Image (V.Date.Month));
         Append (S, "-");
         Append (S, Integer'Wide_Wide_Image (V.Date.Day));
         when Database.Types.Time_Value => Append (S, Integer'Wide_Wide_Image (V.Clock_Time.Hour));
         Append (S, ":");
         Append (S, Integer'Wide_Wide_Image (V.Clock_Time.Minute));
         Append (S, ":");
         Append (S, Integer'Wide_Wide_Image (V.Clock_Time.Second));
         when Database.Types.Date_Time_Value => Append (S, Integer'Wide_Wide_Image (V.Date_Time.Date_Part.Year));
         Append (S, "T");
         Append (S, Integer'Wide_Wide_Image (V.Date_Time.Time_Part.Hour));
         when Database.Types.Duration_Value => Append (S, Long_Long_Integer'Wide_Wide_Image (V.Time_Span.Seconds));
         Append (S, ".");
         Append (S, Natural'Wide_Wide_Image (V.Time_Span.Nanoseconds));
         when Database.Types.UUID_Value => Append (S, Database.UUIDs.UUID_To_String (V.UUID));
         when Database.Types.Array_Value => Append (S, To_Wide_Wide_String (V.Array_Text));
      end case;
      Append (S, ";");
   end Append_Value_Key;

   function Row_Identity_Key
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Wide_Wide_String is
      K : Unbounded_Wide_Wide_String;
      Used_Primary_Key : Boolean := False;
      Pos : Natural;
   begin
      Append (K, "T");
      Append (K, Natural'Wide_Wide_Image (Schema.Table_Id));
      Append (K, "|");
      if Schema.Primary_Key_Columns.Length > 0 then
         for Column_Id of Schema.Primary_Key_Columns loop
            Pos := Database.Schema.Find_Column_Id_Position (Schema, Column_Id);
            if Pos < Database.Rows.Column_Count (Row) then
               Append (K, "C");
               Append (K, Natural'Wide_Wide_Image (Column_Id));
               Append (K, "=");
               Append_Value_Key (K, Database.Rows.Get (Row, Pos));
               Used_Primary_Key := True;
            end if;
         end loop;
      else
         for C of Schema.Columns loop
            if C.Primary_Key then
               Pos := Database.Schema.Find_Column_Id_Position (Schema, C.Id);
               if Pos < Database.Rows.Column_Count (Row) then
                  Append (K, "C");
                  Append (K, Natural'Wide_Wide_Image (C.Id));
                  Append (K, "=");
                  Append_Value_Key (K, Database.Rows.Get (Row, Pos));
                  Used_Primary_Key := True;
               end if;
            end if;
         end loop;
      end if;
      if not Used_Primary_Key and then Database.Rows.Column_Count (Row) > 0 then
         for I in 0 .. Database.Rows.Column_Count (Row) - 1 loop
            Append (K, "R");
            Append (K, Natural'Wide_Wide_Image (I));
            Append (K, "=");
            Append_Value_Key (K, Database.Rows.Get (Row, I));
         end loop;
      end if;
      return To_Wide_Wide_String (K);
   end Row_Identity_Key;

   function Row_Identity
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Natural is
      H : Natural := 5381;
      Used_Primary_Key : Boolean := False;
      Pos : Natural;
   begin
      Mix (H, Schema.Table_Id);
      if Schema.Primary_Key_Columns.Length > 0 then
         for Column_Id of Schema.Primary_Key_Columns loop
            Pos := Database.Schema.Find_Column_Id_Position (Schema, Column_Id);
            if Pos < Database.Rows.Column_Count (Row) then
               Mix (H, Column_Id);
               Mix_Value (H, Database.Rows.Get (Row, Pos));
               Used_Primary_Key := True;
            end if;
         end loop;
      else
         for C of Schema.Columns loop
            if C.Primary_Key then
               Pos := Database.Schema.Find_Column_Id_Position (Schema, C.Id);
               if Pos < Database.Rows.Column_Count (Row) then
                  Mix (H, C.Id);
                  Mix_Value (H, Database.Rows.Get (Row, Pos));
                  Used_Primary_Key := True;
               end if;
            end if;
         end loop;
      end if;

      if not Used_Primary_Key and then Database.Rows.Column_Count (Row) > 0 then
         for I in 0 .. Database.Rows.Column_Count (Row) - 1 loop
            Mix (H, I);
            Mix_Value (H, Database.Rows.Get (Row, I));
         end loop;
      end if;

      if H = 0 then
         return 1;
      end if;
      return H;
   end Row_Identity;

   function Resolve_Row
     (Tx  : in out Database.Transactions.Transaction;
      Hit : Search_Result;
      Row : out Database.Rows.Row) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      Schema : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      Cursor : Database.Storage.Table_Heap.Heap_Cursor;
      Rows : Database.Foreign_Keys.Row_Vectors.Vector;
      Key : constant Wide_Wide_String := To_Wide_Wide_String (Hit.Row_Key);
   begin
      Select_From_Transaction (Tx);
      R := Database.Catalog.Find_By_Id (Hit.Table_Id, Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;

      if DB /= null
        and then Database.Backend (DB.all) = Database.Persistent_Backend
        and then Schema.Heap_First_Page /= 0
      then
         R := Database.Storage.Table_Heap.Scan_First
           (DB.File, Database.Storage.Pages.Page_Id (Schema.Heap_First_Page), Schema, Cursor);
         while Database.Status.Is_Ok (R) and then Cursor.Has_Row loop
            if Row_Identity (Schema, Cursor.Row) = Hit.Row_Id
              and then Row_Identity_Key (Schema, Cursor.Row) = Key
            then
               Row := Cursor.Row;
               return Database.Status.Success;
            end if;
            R := Database.Storage.Table_Heap.Scan_Next (DB.File, Schema, Cursor);
         end loop;
         return Database.Status.Failure (Database.Status.Not_Found, "full-text row reference not found in table heap");
      end if;

      Rows := Database.Catalog.Rows_For_Table (Hit.Table_Id);
      for Rw of Rows loop
         if Row_Identity (Schema, Rw) = Hit.Row_Id
           and then Row_Identity_Key (Schema, Rw) = Key
         then
            Row := Rw;
            return Database.Status.Success;
         end if;
      end loop;
      return Database.Status.Failure (Database.Status.Not_Found, "full-text row reference not found");
   end Resolve_Row;

   function Create_Full_Text_Index
     (Tx         : in out Database.Transactions.Transaction;
      Name       : Wide_Wide_String;
      Table_Name : Wide_Wide_String;
      Column     : Natural) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      Schema : Database.Schema.Table_Schema;
      R : Database.Status.Result;
      IX : Database.Full_Text.Indexes.Full_Text_Index;
      Rows : Database.Foreign_Keys.Row_Vectors.Vector;
      Cursor : Database.Storage.Table_Heap.Heap_Cursor;
      Scan_R : Database.Status.Result;
      Used_Heap : Boolean := False;
   begin
      Select_From_Transaction (Tx);
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure (Database.Status.Read_Only_Transaction,
           "full-text index creation requires write transaction");
      end if;
      if Find_Index (Name) /= Natural'Last then
         return Database.Status.Failure (Database.Status.Already_Exists, "full-text index already exists");
      end if;
      R := Database.Catalog.Find_By_Name (Table_Name, Schema);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      R := Database.Full_Text.Indexes.Validate_Definition (Schema, Column);
      if not Database.Status.Is_Ok (R) then
         return R;
      end if;
      IX := Database.Full_Text.Indexes.Create (Name, Schema, Column);
      IX.Metadata.Owner_Key := Current_State_Key;
      IX.Metadata.Id := Database.Full_Text.Indexes.Full_Text_Index_Id (Natural (FT_Indexes.Length) + 1);
      IX.Metadata.Created_By := Database.Transactions.Id (Tx);
      IX.Metadata.Created_At := Database.Transactions.Commit_Version (Tx);
      if DB /= null and then Database.Backend (DB.all) = Database.Persistent_Backend then
         R := Database.Catalog.Add_Full_Text_Index (DB.all, IX.Metadata);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      --  Build the initial inverted index from the authoritative row source.
      --  For persistent tables this is the table heap, not the transient
      --  catalog row cache. The cache can be empty after reopen.
      if DB /= null
        and then Database.Backend (DB.all) = Database.Persistent_Backend
        and then Schema.Heap_First_Page /= 0
      then
         Scan_R := Database.Storage.Table_Heap.Scan_First
           (Tx, DB.File, Database.Storage.Pages.Page_Id (Schema.Heap_First_Page), Schema, Cursor);
         while Database.Status.Is_Ok (Scan_R) and then Cursor.Has_Row loop
            Database.Full_Text.Indexes.Index_Row
              (IX, Tx, Row_Identity (Schema, Cursor.Row), Row_Identity_Key (Schema, Cursor.Row), Cursor.Row);
            Used_Heap := True;
            Scan_R := Database.Storage.Table_Heap.Scan_Next (Tx, DB.File, Schema, Cursor);
         end loop;
      end if;

      if not Used_Heap then
         Rows := Database.Catalog.Rows_For_Table (Schema.Table_Id);
         if Rows.Length > 0 then
            for I in 0 .. Natural (Rows.Length) - 1 loop
               Database.Full_Text.Indexes.Index_Row
                  (IX,
                   Tx,
                   Row_Identity (Schema,
                   Rows.Element (I)),
                   Row_Identity_Key (Schema,
                   Rows.Element (I)),
                   Rows.Element (I));
            end loop;
         end if;
      end if;
      FT_Indexes.Append (IX);
      return Database.Status.Success;
   end Create_Full_Text_Index;

   function Drop_Full_Text_Index
     (Tx   : in out Database.Transactions.Transaction;
      Name : Wide_Wide_String) return Database.Status.Result is
      DB : access Database.Handle := Database.Transactions.Owning_Database (Tx);
      Pos : Natural;
      R : Database.Status.Result;
   begin
      Select_From_Transaction (Tx);
      Pos := Find_Index (Name);
      if not Database.Transactions.Can_Write (Tx) then
         return Database.Status.Failure (Database.Status.Read_Only_Transaction,
           "full-text index drop requires write transaction");
      end if;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "full-text index not found");
      end if;
      if DB /= null and then Database.Backend (DB.all) = Database.Persistent_Backend then
         R := Database.Catalog.Remove_Full_Text_Index (DB.all, Name);
         if not Database.Status.Is_Ok (R) then
            return R;
         end if;
      end if;
      declare
         IX : Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (Pos);
      begin
         IX.Metadata.Deleted_By := Database.Transactions.Id (Tx);
         IX.Metadata.Deleted_At := Database.Transactions.Snapshot_Version (Tx) + 1;
         FT_Indexes.Replace_Element (Pos, IX);
      end;
      return Database.Status.Success;
   end Drop_Full_Text_Index;

   function All_Postings
     (IX : Database.Full_Text.Indexes.Full_Text_Index)
      return Database.Full_Text.Postings.Posting_Vectors.Vector is
      R : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      for E of IX.Terms loop
         R := Database.Full_Text.Postings.Union (R, E.Postings);
      end loop;
      return R;
   end All_Postings;

   function Eval
     (IX : Database.Full_Text.Indexes.Full_Text_Index;
      Q  : Database.Full_Text.Queries.Query) return Database.Full_Text.Postings.Posting_Vectors.Vector is
      use Database.Full_Text.Queries;
      K : constant Query_Kind := Kind (Q);
      R : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      case K is
         when Match_All => return All_Postings (IX);
         when Term_Query => return Database.Full_Text.Indexes.Lookup (IX, Text (Q));
         when Prefix_Query => return Database.Full_Text.Indexes.Lookup_Prefix (IX, Text (Q));
         when Fuzzy_Query => return Database.Full_Text.Indexes.Lookup_Fuzzy (IX, Text (Q), Distance (Q));
         when Near_Query =>
            return Database.Full_Text.Postings.Near_Intersect
              (Eval (IX, Left (Q)), Eval (IX, Right (Q)), Positive'Max (1, Positive (Distance (Q))));
         when And_Query => return Database.Full_Text.Postings.Intersect (Eval (IX, Left (Q)), Eval (IX, Right (Q)));
         when Or_Query => return Database.Full_Text.Postings.Union (Eval (IX, Left (Q)), Eval (IX, Right (Q)));
         when Not_Query => return Database.Full_Text.Postings.Difference (All_Postings (IX), Eval (IX, Child (Q)));
         when Phrase_Query =>
            declare
               Ts : constant Term_Vectors.Vector := Terms (Q);
            begin
               if Ts.Length = 0 then
                  return R;
               end if;
               R := Database.Full_Text.Indexes.Lookup (IX, To_Wide_Wide_String (Ts.Element (0)));
               if Ts.Length > 1 then
                  for I in 1 .. Natural (Ts.Length) - 1 loop
                     R := Database.Full_Text.Postings.Phrase_Intersect
                       (R,
                        Database.Full_Text.Indexes.Lookup (IX, To_Wide_Wide_String (Ts.Element (I))),
                        I);
                  end loop;
               end if;
               return R;
            end;
      end case;
   end Eval;

   function Posting_Visible
     (Tx : Database.Transactions.Transaction;
      P  : Database.Full_Text.Postings.Posting) return Boolean is
      Created_Lifecycle : constant Database.MVCC.Transaction_Lifecycle  :=
        Database.MVCC.Lifecycle (P.Created_By);
      Deleted_Lifecycle : constant Database.MVCC.Transaction_Lifecycle  :=
        Database.MVCC.Lifecycle (P.Deleted_By);
      Created_OK : Boolean := False;
      Deleted_OK : Boolean := False;
   begin
      if P.Created_By = Database.Transactions.Id (Tx) then
         Created_OK := True;
      elsif P.Created_At /= Database.Versioning.No_Version then
         Created_OK := P.Created_At <= Database.Transactions.Snapshot_Version (Tx);
      elsif P.Created_By = Database.Versioning.No_Transaction then
         Created_OK := True;
      else
         case Created_Lifecycle is
            when Database.MVCC.Committed =>
               declare
                  CV : constant Database.Versioning.Commit_Version  :=
                    Database.MVCC.Transaction_Commit_Version (P.Created_By);
               begin
                  Created_OK := CV /= Database.Versioning.No_Version
                    and then CV <= Database.Transactions.Snapshot_Version (Tx);
               end;
            when Database.MVCC.Active | Database.MVCC.Rolled_Back | Database.MVCC.Unknown =>
               Created_OK := False;
         end case;
      end if;

      if not Created_OK then
         return False;
      end if;

      if P.Deleted_By = Database.Versioning.No_Transaction then
         return True;
      elsif P.Deleted_By = Database.Transactions.Id (Tx) then
         return False;
      elsif P.Deleted_At /= Database.Versioning.No_Version then
         return P.Deleted_At > Database.Transactions.Snapshot_Version (Tx);
      else
         case Deleted_Lifecycle is
            when Database.MVCC.Committed =>
               declare
                  CV : constant Database.Versioning.Commit_Version  :=
                    Database.MVCC.Transaction_Commit_Version (P.Deleted_By);
               begin
                  Deleted_OK := CV /= Database.Versioning.No_Version
                    and then CV <= Database.Transactions.Snapshot_Version (Tx);
               end;
            when Database.MVCC.Active | Database.MVCC.Rolled_Back | Database.MVCC.Unknown =>
               Deleted_OK := False;
         end case;
      end if;

      return not Deleted_OK;
   end Posting_Visible;

   function Filter_Visible
     (Tx : Database.Transactions.Transaction;
      P  : Database.Full_Text.Postings.Posting_Vectors.Vector)
      return Database.Full_Text.Postings.Posting_Vectors.Vector is
      R : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      for E of P loop
         if Posting_Visible (Tx, E) then
            R.Append (E);
         end if;
      end loop;
      return R;
   end Filter_Visible;

   function Eval_Visible
     (Tx : Database.Transactions.Transaction;
      IX : Database.Full_Text.Indexes.Full_Text_Index;
      Q  : Database.Full_Text.Queries.Query) return Database.Full_Text.Postings.Posting_Vectors.Vector is
      use Database.Full_Text.Queries;
      K : constant Query_Kind := Kind (Q);
      R : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      case K is
         when Match_All =>
            return Filter_Visible (Tx, All_Postings (IX));
         when Term_Query =>
            return Filter_Visible (Tx, Database.Full_Text.Indexes.Lookup (IX, Text (Q)));
         when Prefix_Query =>
            return Filter_Visible (Tx, Database.Full_Text.Indexes.Lookup_Prefix (IX, Text (Q)));
         when Fuzzy_Query =>
            return Filter_Visible (Tx, Database.Full_Text.Indexes.Lookup_Fuzzy (IX, Text (Q), Distance (Q)));
         when Near_Query =>
            return Database.Full_Text.Postings.Near_Intersect
              (Eval_Visible (Tx, IX, Left (Q)),
               Eval_Visible (Tx, IX, Right (Q)),
               Positive'Max (1, Positive (Distance (Q))));
         when And_Query =>
            return Database.Full_Text.Postings.Intersect
              (Eval_Visible (Tx, IX, Left (Q)), Eval_Visible (Tx, IX, Right (Q)));
         when Or_Query =>
            return Database.Full_Text.Postings.Union
              (Eval_Visible (Tx, IX, Left (Q)), Eval_Visible (Tx, IX, Right (Q)));
         when Not_Query =>
            return Database.Full_Text.Postings.Difference
              (Filter_Visible (Tx, All_Postings (IX)), Eval_Visible (Tx, IX, Child (Q)));
         when Phrase_Query =>
            declare
               Ts : constant Term_Vectors.Vector := Terms (Q);
            begin
               if Ts.Length = 0 then
                  return R;
               end if;
               R := Filter_Visible (Tx, Database.Full_Text.Indexes.Lookup (IX, To_Wide_Wide_String (Ts.Element (0))));
               if Ts.Length > 1 then
                  for I in 1 .. Natural (Ts.Length) - 1 loop
                     R := Database.Full_Text.Postings.Phrase_Intersect
                       (R,
                        Filter_Visible  (Tx,
                          Database.Full_Text.Indexes.Lookup (IX,
                          To_Wide_Wide_String (Ts.Element (I)))),
                        I);
                  end loop;
               end if;
               return R;
            end;
      end case;
   end Eval_Visible;

   function Representative_Term (Q : Database.Full_Text.Queries.Query) return Wide_Wide_String is
      use Database.Full_Text.Queries;
      Ts : Term_Vectors.Vector;
   begin
      case Kind (Q) is
         when Term_Query | Prefix_Query | Fuzzy_Query =>
            return Text (Q);
         when Phrase_Query =>
            Ts := Terms (Q);
            if Ts.Length > 0 then
               return To_Wide_Wide_String (Ts.Element (0));
            else
               return "";
            end if;
         when And_Query | Or_Query | Near_Query =>
            return Representative_Term (Left (Q));
         when Not_Query =>
            return Representative_Term (Child (Q));
         when Match_All =>
            return "";
      end case;
   end Representative_Term;

   procedure Sort_By_Score (R : in out Search_Result_Vectors.Vector) is
   begin
      if R.Length < 2 then
         return;
      end if;
      for I in 0 .. Natural (R.Length) - 2 loop
         for J in I + 1 .. Natural (R.Length) - 1 loop
            if R.Element (J).Score > R.Element (I).Score
              or else (R.Element (J).Score = R.Element (I).Score
                       and then To_Wide_Wide_String (R.Element (J).Row_Key)
                         < To_Wide_Wide_String (R.Element (I).Row_Key))
            then
               declare
                  A : constant Search_Result := R.Element (I);
               begin
                  R.Replace_Element (I, R.Element (J));
                  R.Replace_Element (J, A);
               end;
            end if;
         end loop;
      end loop;
   end Sort_By_Score;

   function Try_Search
     (Tx     : in out Database.Transactions.Transaction;
      Index  : Wide_Wide_String;
      Query  : Database.Full_Text.Queries.Query;
      Cursor : out Search_Cursor) return Database.Status.Result is
      Pos : Natural;
   begin
      Cursor.Results.Clear;
      Cursor.Index := 0;
      Select_From_Transaction (Tx);
      Pos := Find_Index (Index);
      if Pos = Natural'Last or else not Index_Visible (Tx, FT_Indexes.Element (Pos)) then
         return Database.Status.Failure
           (Database.Status.Not_Found, "full-text index not found");
      end if;
      declare
         P : constant Database.Full_Text.Postings.Posting_Vectors.Vector  :=
           Eval_Visible (Tx, FT_Indexes.Element (Pos), Query);
      begin
         for E of P loop
            Cursor.Results.Append
              (Search_Result'(Table_Id => E.Ref.Table_Id,
                Row_Id => E.Ref.Row_Id,
                Row_Key => E.Ref.Row_Key,
                Column_Id => E.Ref.Column_Id,
                Score => Long_Float (Database.Full_Text.Ranking.Query_Score
                  (Posting => E,
                   Total_Documents => Natural'Max  (1,
                     Database.Full_Text.Indexes.Document_Count (FT_Indexes.Element (Pos))),
                   Document_Frequency => Natural'Max  (1,
                     Database.Full_Text.Indexes.Document_Frequency (FT_Indexes.Element (Pos),
                     Representative_Term (Query))),
                   Average_Document_Length =>
                     Database.Full_Text.Ranking.Score
                       (Database.Full_Text.Indexes.Average_Document_Length
                          (FT_Indexes.Element (Pos))),
                   Document_Length => Natural'Max  (1,
                     Database.Full_Text.Indexes.Document_Length (FT_Indexes.Element (Pos),
                     To_Wide_Wide_String (E.Ref.Row_Key))),
                   Matched_Terms => 1,
                   Phrase_Bonus =>
                     Database.Full_Text.Queries.Kind (Query) = Database.Full_Text.Queries.Phrase_Query))));
         end loop;
      end;
      Sort_By_Score (Cursor.Results);
      return Database.Status.Success;
   end Try_Search;

   function Try_Search
     (Tx     : in out Database.Transactions.Transaction;
      Index  : Wide_Wide_String;
      Query  : Wide_Wide_String;
      Cursor : out Search_Cursor) return Database.Status.Result is
   begin
      return Try_Search
        (Tx     => Tx,
         Index  => Index,
         Query  => Database.Full_Text.Queries.Term (Query),
         Cursor => Cursor);
   end Try_Search;

   function Search
     (Tx    : in out Database.Transactions.Transaction;
      Index : Wide_Wide_String;
      Query : Wide_Wide_String) return Search_Cursor is
      C : Search_Cursor;
      R : Database.Status.Result;
   begin
      R := Try_Search (Tx, Index, Query, C);
      pragma Unreferenced (R);
      return C;
   end Search;

   function Has_Element (C : Search_Cursor) return Boolean is
   begin
      return C.Index < Natural (C.Results.Length);
   end Has_Element;
   function Element (C : Search_Cursor) return Search_Result is (C.Results.Element (C.Index));
   procedure Next (C : in out Search_Cursor) is
   begin
      if Has_Element (C) then
         C.Index := C.Index + 1;
      end if;
   end Next;
   function Row_Count (C : Search_Cursor) return Natural is (Natural (C.Results.Length));

   procedure Maintain_Insert
     (Tx       : in out Database.Transactions.Transaction;
      Schema   : Database.Schema.Table_Schema;
      Row_Id   : Natural;
      Row      : Database.Rows.Row) is
   begin
      Select_From_Transaction (Tx);
      if FT_Indexes.Length > 0 then
         for I in 0 .. Natural (FT_Indexes.Length) - 1 loop
            declare
               IX : Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (I);
            begin
               if IX.Metadata.Owner_Key = Current_State_Key and then IX.Metadata.Table_Id = Schema.Table_Id
                 and then Index_Visible (Tx, IX) then
                  Database.Full_Text.Indexes.Index_Row  (IX,
                    Tx,
                    Row_Identity (Schema,
                    Row),
                    Row_Identity_Key (Schema,
                    Row),
                    Row);
                  FT_Indexes.Replace_Element (I, IX);
               end if;
            end;
         end loop;
      end if;
   end Maintain_Insert;

   procedure Maintain_Delete
     (Tx       : in out Database.Transactions.Transaction;
      Schema   : Database.Schema.Table_Schema;
      Row      : Database.Rows.Row) is
      Stable_Id  : constant Natural := Row_Identity (Schema, Row);
      Stable_Key : constant Wide_Wide_String := Row_Identity_Key (Schema, Row);
   begin
      Select_From_Transaction (Tx);
      if FT_Indexes.Length > 0 then
         for I in 0 .. Natural (FT_Indexes.Length) - 1 loop
            declare
               IX : Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (I);
            begin
               if IX.Metadata.Owner_Key = Current_State_Key and then IX.Metadata.Table_Id = Schema.Table_Id
                 and then Index_Visible (Tx, IX) then
                  Database.Full_Text.Indexes.Delete_Row (IX, Tx, Stable_Id, Stable_Key);
                  FT_Indexes.Replace_Element (I, IX);
               end if;
            end;
         end loop;
      end if;
   end Maintain_Delete;

   function Sidecar_Path (Path : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Path & ".fts");
   end Sidecar_Path;

   procedure Commit_Transaction
     (Tx_Id          : Database.Versioning.Transaction_Id;
      Commit_Version : Database.Versioning.Commit_Version) is
   begin
      if FT_Indexes.Length = 0 then
         return;
      end if;
      for II in reverse 0 .. Natural (FT_Indexes.Length) - 1 loop
         declare
            IX : Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (II);
         begin
            if IX.Metadata.Owner_Key = Current_State_Key then
               if IX.Metadata.Deleted_By = Tx_Id then
                  FT_Indexes.Delete (II);
               else
                  if IX.Metadata.Created_By = Tx_Id then
                     IX.Metadata.Created_By := Database.Versioning.No_Transaction;
                     IX.Metadata.Created_At := Commit_Version;
                  end if;
                  if IX.Terms.Length > 0 then
                  for TI in 0 .. Natural (IX.Terms.Length) - 1 loop
                     declare
                        TE : Database.Full_Text.Indexes.Term_Entry := IX.Terms.Element (TI);
                     begin
                        if TE.Postings.Length > 0 then
                        for PI in 0 .. Natural (TE.Postings.Length) - 1 loop
                           declare
                              P : Database.Full_Text.Postings.Posting := TE.Postings.Element (PI);
                           begin
                              if P.Created_By = Tx_Id then
                                 P.Created_At := Commit_Version;
                              end if;
                              if P.Deleted_By = Tx_Id then
                                 P.Deleted_At := Commit_Version;
                              end if;
                              TE.Postings.Replace_Element (PI, P);
                           end;
                        end loop;
                        end if;
                        IX.Terms.Replace_Element (TI, TE);
                     end;
                  end loop;
                  end if;
                  FT_Indexes.Replace_Element (II, IX);
               end if;
            end if;
         end;
      end loop;
   end Commit_Transaction;

   procedure Rollback_Transaction
     (Tx_Id : Database.Versioning.Transaction_Id) is
   begin
      if FT_Indexes.Length = 0 then
         return;
      end if;
      for II in reverse 0 .. Natural (FT_Indexes.Length) - 1 loop
         declare
            IX : Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (II);
         begin
            if IX.Metadata.Owner_Key = Current_State_Key then
               if IX.Metadata.Created_By = Tx_Id then
                  FT_Indexes.Delete (II);
               else
                  if IX.Metadata.Deleted_By = Tx_Id then
                     IX.Metadata.Deleted_By := Database.Versioning.No_Transaction;
                     IX.Metadata.Deleted_At := Database.Versioning.No_Version;
                  end if;
                  if IX.Terms.Length > 0 then
                  for TI in reverse 0 .. Natural (IX.Terms.Length) - 1 loop
                     declare
                        TE : Database.Full_Text.Indexes.Term_Entry := IX.Terms.Element (TI);
                     begin
                        if TE.Postings.Length > 0 then
                        for PI in reverse 0 .. Natural (TE.Postings.Length) - 1 loop
                           declare
                              P : Database.Full_Text.Postings.Posting := TE.Postings.Element (PI);
                           begin
                              if P.Created_By = Tx_Id then
                                 TE.Postings.Delete (PI);
                              elsif P.Deleted_By = Tx_Id then
                                 P.Deleted_By := Database.Versioning.No_Transaction;
                                 P.Deleted_At := Database.Versioning.No_Version;
                                 TE.Postings.Replace_Element (PI, P);
                                 if IX.Deleted_Posting_Count > 0 then
                                    IX.Deleted_Posting_Count := IX.Deleted_Posting_Count - 1;
                                 end if;
                              end if;
                           end;
                        end loop;
                        end if;
                        if TE.Postings.Is_Empty then
                           IX.Terms.Delete (TI);
                        else
                           IX.Terms.Replace_Element (TI, TE);
                        end if;
                     end;
                  end loop;
                  end if;
                  FT_Indexes.Replace_Element (II, IX);
               end if;
            end if;
         end;
      end loop;
   end Rollback_Transaction;

   function Owned_Index_Count return Natural is
      C : Natural := 0;
   begin
      for IX of FT_Indexes loop
         if IX.Metadata.Owner_Key = Current_State_Key and then Index_Committed_Visible (IX) then
            C := C + 1;
         end if;
      end loop;
      return C;
   end Owned_Index_Count;

   function Save (Path : Wide_Wide_String) return Database.Status.Result is
      use Ada.Wide_Wide_Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Sidecar_Path (Path));
      Put_Line (F, "DATABASE_FULL_TEXT_V2");
      Put_Line (F, Natural'Wide_Wide_Image (Owned_Index_Count));
      for IX of FT_Indexes loop
         if IX.Metadata.Owner_Key = Current_State_Key and then Index_Committed_Visible (IX) then
         Put_Line (F, "INDEX");
         Put_Line (F, Natural'Wide_Wide_Image (Natural (IX.Metadata.Id)));
         Put_Line (F, To_Wide_Wide_String (IX.Metadata.Name));
         Put_Line (F, Natural'Wide_Wide_Image (IX.Metadata.Table_Id));
         Put_Line (F, To_Wide_Wide_String (IX.Metadata.Table_Name));
         Put_Line (F, Natural'Wide_Wide_Image (IX.Metadata.Column_Id));
         Put_Line (F, Natural'Wide_Wide_Image (Natural (IX.Terms.Length)));
         for TE of IX.Terms loop
            Put_Line (F, To_Wide_Wide_String (TE.Term));
            Put_Line (F, Natural'Wide_Wide_Image (Natural (TE.Postings.Length)));
            for P of TE.Postings loop
               Put_Line (F,
                 Natural'Wide_Wide_Image (P.Ref.Table_Id) & " " &
                 Natural'Wide_Wide_Image (P.Ref.Row_Id) & " " &
                 Natural'Wide_Wide_Image (P.Ref.Column_Id) & " " &
                 Natural'Wide_Wide_Image (P.Frequency) & " " &
                 Natural'Wide_Wide_Image (Natural (P.Created_By)) & " " &
                 Natural'Wide_Wide_Image (Natural (P.Created_At)) & " " &
                 Natural'Wide_Wide_Image (Natural (P.Deleted_By)) & " " &
                 Natural'Wide_Wide_Image (Natural (P.Deleted_At)) & " " &
                 Natural'Wide_Wide_Image (Natural (P.Positions.Length)));
               Put_Line (F, To_Wide_Wide_String (P.Ref.Row_Key));
               if P.Positions.Length = 0 then
                  Put_Line (F, "");
               else
                  declare
                     Line : Unbounded_Wide_Wide_String;
                  begin
                     for Pos of P.Positions loop
                        Append (Line, Natural'Wide_Wide_Image (Pos));
                        Append (Line, " ");
                     end loop;
                     Put_Line (F, To_Wide_Wide_String (Line));
                  end;
               end if;
            end loop;
         end loop;
         end if;
      end loop;
      Close (F);
      return Database.Status.Success;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         return Database.Status.Failure (Database.Status.IOError, "could not save full-text sidecar");
   end Save;

   procedure Next_Number
     (Line : Wide_Wide_String;
      Pos  : in out Natural;
      N    : out Natural) is
      First : Natural;
   begin
      while Pos <= Line'Last and then Line (Pos) = ' ' loop
         Pos := Pos + 1;
      end loop;
      First := Pos;
      while Pos <= Line'Last and then Line (Pos) /= ' ' loop
         Pos := Pos + 1;
      end loop;
      if First > Line'Last then
         N := 0;
      else
         N := Natural'Wide_Wide_Value (Line (First .. Pos - 1));
      end if;
   end Next_Number;

   function Load_Definitions (Path : Wide_Wide_String) return Database.Full_Text.Indexes.Index_Vectors.Vector is
      pragma Unreferenced (Path);
      Result : Database.Full_Text.Indexes.Index_Vectors.Vector;
      Defs : constant Database.Full_Text.Indexes.Metadata_Vectors.Vector  :=
        Database.Catalog.Full_Text_Index_Definitions;
   begin
      for M of Defs loop
         declare
            IX : Database.Full_Text.Indexes.Full_Text_Index;
         begin
            IX.Metadata := M;
            IX.Metadata.Owner_Key := Current_State_Key;
            Result.Append (IX);
         end;
      end loop;
      return Result;
   end Load_Definitions;

   function Rebuild_From_Catalog
     (DB   : in out Database.Handle;
      Path : Wide_Wide_String) return Database.Status.Result is
      Definitions : Database.Full_Text.Indexes.Index_Vectors.Vector := Load_Definitions (Path);
      Schema : Database.Schema.Table_Schema;
      Schema_R : Database.Status.Result;
      Cursor : Database.Storage.Table_Heap.Heap_Cursor;
      Scan_R : Database.Status.Result;
      Root : Database.Storage.Pages.Page_Id;
   begin
      Clear;
      if Definitions.Length = 0 then
         return Database.Status.Success;
      end if;
      for I in 0 .. Natural (Definitions.Length) - 1 loop
         declare
            IX : Database.Full_Text.Indexes.Full_Text_Index := Definitions.Element (I);
         begin
            Schema_R := Database.Catalog.Find_By_Id (IX.Metadata.Table_Id, Schema);
            if not Database.Status.Is_Ok (Schema_R) then
               Schema_R := Database.Catalog.Find_By_Name (To_Wide_Wide_String (IX.Metadata.Table_Name), Schema);
            end if;
            if Database.Status.Is_Ok (Schema_R) then
               --  Recreate metadata through the normal constructor so tokenizer
               --  and normalizer defaults are identical to fresh indexes.
               declare
                  Rebuilt : Database.Full_Text.Indexes.Full_Text_Index  :=
                    Database.Full_Text.Indexes.Create
                      (To_Wide_Wide_String (IX.Metadata.Name), Schema, IX.Metadata.Column_Id);
               begin
                  Rebuilt.Metadata.Id := IX.Metadata.Id;
                  Rebuilt.Metadata.Owner_Key := Current_State_Key;
                  if Schema.Heap_First_Page /= 0 then
                     Root := Database.Storage.Pages.Page_Id (Schema.Heap_First_Page);
                     Scan_R := Database.Storage.Table_Heap.Scan_First (DB.File, Root, Schema, Cursor);
                     while Database.Status.Is_Ok (Scan_R) and then Cursor.Has_Row loop
                        Database.Full_Text.Indexes.Index_Row_Committed
                           (Rebuilt,
                            Row_Identity (Schema,
                            Cursor.Row),
                            Row_Identity_Key (Schema,
                            Cursor.Row),
                            Cursor.Row);
                        Scan_R := Database.Storage.Table_Heap.Scan_Next (DB.File, Schema, Cursor);
                     end loop;
                  else
                     declare
                        Rows : constant Database.Foreign_Keys.Row_Vectors.Vector  :=
                          Database.Catalog.Rows_For_Table (Schema.Table_Id);
                     begin
                        for R of Rows loop
                           Database.Full_Text.Indexes.Index_Row_Committed
                             (Rebuilt, Row_Identity (Schema, R), Row_Identity_Key (Schema, R), R);
                        end loop;
                     end;
                  end if;
                  FT_Indexes.Append (Rebuilt);
               end;
            end if;
         end;
      end loop;
      return Save (Path);
   end Rebuild_From_Catalog;

   function Load
     (DB   : in out Database.Handle;
      Path : Wide_Wide_String) return Database.Status.Result is
      use Ada.Wide_Wide_Text_IO;
      F : File_Type;
      Line : Wide_Wide_String (1 .. 4096);
      Last : Natural;
      Count : Natural;
      Header_Is_V2 : Boolean := False;
   begin
      Clear;
      --  The posting sidecar is treated as a cache. If durable full-text
      --  definitions are present, rebuild postings from the authoritative
      --  catalog/table contents on open. This avoids exposing stale postings
      --  after a crash between a database commit and a sidecar save.
      if Database.Catalog.Full_Text_Index_Definitions.Length > 0 then
         return Rebuild_From_Catalog (DB, Path);
      end if;
      if not Ada.Directories.Exists (Sidecar_Path (Path)) then
         return Database.Status.Success;
      end if;
      Open (F, In_File, Sidecar_Path (Path));
      Get_Line (F, Line, Last);
      if Line (1 .. Last) = "DATABASE_FULL_TEXT_V2" then
         Header_Is_V2 := True;
      elsif Line (1 .. Last) = "DATABASE_FULL_TEXT_V1" then
         Header_Is_V2 := False;
      else
         Close (F);
         return Database.Status.Failure (Database.Status.Corrupt_File, "bad full-text sidecar header");
      end if;
      Get_Line (F, Line, Last);
      Count := Natural'Wide_Wide_Value (Line (1 .. Last));
      for I in 1 .. Count loop
         declare
            IX : Database.Full_Text.Indexes.Full_Text_Index;
            Term_Count_N : Natural;
         begin
            Get_Line (F, Line, Last);
            if Line (1 .. Last) /= "INDEX" then
               Close (F);
               return Database.Status.Failure
                 (Database.Status.Corrupt_File,
                  "malformed full-text sidecar index marker");
            end if;
            Get_Line (F, Line, Last);
            IX.Metadata.Id  :=
              Database.Full_Text.Indexes.Full_Text_Index_Id
                (Natural'Wide_Wide_Value (Line (1 .. Last)));
            Get_Line (F, Line, Last);
            IX.Metadata.Name := To_Unbounded_Wide_Wide_String (Line (1 .. Last));
            Get_Line (F, Line, Last);
            IX.Metadata.Table_Id := Natural'Wide_Wide_Value (Line (1 .. Last));
            Get_Line (F, Line, Last);
            IX.Metadata.Table_Name := To_Unbounded_Wide_Wide_String (Line (1 .. Last));
            Get_Line (F, Line, Last);
            IX.Metadata.Column_Id := Natural'Wide_Wide_Value (Line (1 .. Last));
            Get_Line (F, Line, Last);
            Term_Count_N := Natural'Wide_Wide_Value (Line (1 .. Last));
            for T in 1 .. Term_Count_N loop
               declare
                  TE : Database.Full_Text.Indexes.Term_Entry;
                  Posting_Count_N : Natural;
               begin
                  Get_Line (F, Line, Last);
                  TE.Term := To_Unbounded_Wide_Wide_String (Line (1 .. Last));
                  Get_Line (F, Line, Last);
                  Posting_Count_N := Natural'Wide_Wide_Value (Line (1 .. Last));
                  for J in 1 .. Posting_Count_N loop
                     declare
                        P : Database.Full_Text.Postings.Posting;
                        N, Posn : Natural;
                        Parse_Pos : Natural := Line'First;
                     begin
                        Get_Line (F, Line, Last);
                        Parse_Pos := Line'First;
                        Next_Number  (Line (1 .. Last),
                          Parse_Pos,
                          P.Ref.Table_Id);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          P.Ref.Row_Id);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          P.Ref.Column_Id);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          P.Frequency);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          N);
                          P.Created_By := Database.Versioning.Transaction_Id (N);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          N);
                          P.Created_At := Database.Versioning.Commit_Version (N);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          N);
                          P.Deleted_By := Database.Versioning.Transaction_Id (N);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          N);
                          P.Deleted_At := Database.Versioning.Commit_Version (N);
                          Next_Number (Line (1 .. Last),
                          Parse_Pos,
                          N);
                        if Header_Is_V2 then
                           Get_Line (F, Line, Last);
                           P.Ref.Row_Key := To_Unbounded_Wide_Wide_String (Line (1 .. Last));
                        end if;
                        Get_Line (F, Line, Last);
                        Parse_Pos := Line'First;
                        for K in 1 .. N loop
                           Next_Number (Line (1 .. Last), Parse_Pos, Posn);
                           P.Positions.Append (Posn);
                        end loop;
                        TE.Postings.Append (P);
                        if P.Deleted_By /= Database.Versioning.No_Transaction then
                           IX.Deleted_Posting_Count := IX.Deleted_Posting_Count + 1;
                        end if;
                     end;
                  end loop;
                  IX.Terms.Append (TE);
               end;
            end loop;
            IX.Metadata.Owner_Key := Current_State_Key;
            Database.Full_Text.Indexes.Recompute_Document_Statistics_From_Postings (IX);
            FT_Indexes.Append (IX);
         end;
      end loop;
      Close (F);
      return Database.Status.Success;
   exception
      when others =>
         Clear;
         if Is_Open (F) then
            Close (F);
         end if;
         return Database.Status.Failure (Database.Status.Corrupt_File, "malformed full-text sidecar");
   end Load;

   function Check_Index
     (Tx   : in out Database.Transactions.Transaction;
      Name : Wide_Wide_String) return Database.Status.Result is
      Pos : Natural;
      Row : Database.Rows.Row;
      R : Database.Status.Result;
   begin
      Select_From_Transaction (Tx);
      Pos := Find_Index (Name);
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "full-text index not found");
      end if;
      declare
         IX : constant Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (Pos);
      begin
         for TE of IX.Terms loop
            if Length (TE.Term) = 0 then
               return Database.Status.Failure (Database.Status.Corrupt_File, "empty full-text term");
            end if;
            for P of TE.Postings loop
               if P.Ref.Table_Id /= IX.Metadata.Table_Id
                 or else P.Ref.Column_Id /= IX.Metadata.Column_Id
                 or else P.Ref.Row_Id = 0
                 or else Length (P.Ref.Row_Key) = 0
               then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting reference");
               end if;
               if P.Frequency /= Natural (P.Positions.Length) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting frequency");
               end if;
               if P.Deleted_By = Database.Versioning.No_Transaction then
                  R := Resolve_Row
                       (Tx,
                        Search_Result'(Table_Id => P.Ref.Table_Id,
                                       Row_Id => P.Ref.Row_Id,
                                       Row_Key => P.Ref.Row_Key,
                                       Column_Id => P.Ref.Column_Id,
                                       Score => 0.0),
                        Row);
                  if not Database.Status.Is_Ok (R) then
                     return Database.Status.Failure (Database.Status.Corrupt_File,
                       "dangling full-text posting row reference");
                  end if;
               end if;
            end loop;
         end loop;
      end;
      return Database.Status.Success;
   end Check_Index;

   function Check_Index (Name : Wide_Wide_String) return Database.Status.Result is
      Pos : constant Natural := Find_Index (Name);
   begin
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "full-text index not found");
      end if;
      declare
         IX : constant Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (Pos);
      begin
         for TE of IX.Terms loop
            if Length (TE.Term) = 0 then
               return Database.Status.Failure (Database.Status.Corrupt_File, "empty full-text term");
            end if;
            for P of TE.Postings loop
               if P.Ref.Table_Id /= IX.Metadata.Table_Id or else P.Ref.Column_Id /= IX.Metadata.Column_Id
                 or else P.Ref.Row_Id = 0 then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting reference");
               end if;
               if Length (P.Ref.Row_Key) = 0 then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "missing full-text row identity key");
               end if;
               declare
                  Rows : constant Database.Foreign_Keys.Row_Vectors.Vector  :=
                    Database.Catalog.Rows_For_Table (IX.Metadata.Table_Id);
                  Live_Schema : Database.Schema.Table_Schema;
                  Schema_Result : Database.Status.Result;
                  Found : Boolean := False;
               begin
                  Schema_Result := Database.Catalog.Find_By_Name
                    (To_Wide_Wide_String (IX.Metadata.Table_Name), Live_Schema);
                  if Database.Status.Is_Ok (Schema_Result) then
                     for R of Rows loop
                        if Row_Identity_Key (Live_Schema, R) = To_Wide_Wide_String (P.Ref.Row_Key)
                          and then Row_Identity (Live_Schema, R) = P.Ref.Row_Id
                        then
                           Found := True;
                           exit;
                        end if;
                     end loop;
                  end if;
                  if Rows.Length > 0 and then not Found and then P.Deleted_By = Database.Versioning.No_Transaction then
                     return Database.Status.Failure (Database.Status.Corrupt_File,
                       "dangling full-text posting row reference");
                  end if;
               end;
               if P.Frequency /= Natural (P.Positions.Length) then
                  return Database.Status.Failure (Database.Status.Corrupt_File, "invalid full-text posting frequency");
               end if;
            end loop;
         end loop;
      end;
      return Database.Status.Success;
   end Check_Index;

   procedure Vacuum_Index (Name : Wide_Wide_String) is
      Pos : constant Natural := Find_Index (Name);
   begin
      if Pos = Natural'Last then
         return;
      end if;
      declare
         IX : Database.Full_Text.Indexes.Full_Text_Index := FT_Indexes.Element (Pos);
      begin
         if IX.Terms.Length > 0 then
         for TI in reverse 0 .. Natural (IX.Terms.Length) - 1 loop
            declare
               TE : Database.Full_Text.Indexes.Term_Entry := IX.Terms.Element (TI);
            begin
               if TE.Postings.Length > 0 then
               for PI in reverse 0 .. Natural (TE.Postings.Length) - 1 loop
                  declare
                     P : constant Database.Full_Text.Postings.Posting := TE.Postings.Element (PI);
                  begin
                     if P.Deleted_By /= Database.Versioning.No_Transaction
                       and then Database.MVCC.Lifecycle (P.Deleted_By) = Database.MVCC.Committed
                       and then Database.MVCC.Safe_Reclaim_Version
                         ((if P.Deleted_At

                           /= Database.Versioning.No_Version then
                                 P.Deleted_At
                               else
                                 Database.MVCC.Transaction_Commit_Version
                                   (P.Deleted_By)))
                     then
                        TE.Postings.Delete (PI);
                     end if;
                  end;
               end loop;
               end if;
               if TE.Postings.Is_Empty then
                  IX.Terms.Delete (TI);
               else
                  IX.Terms.Replace_Element (TI, TE);
               end if;
            end;
         end loop;
         end if;
         IX.Deleted_Posting_Count := 0;
         for TE of IX.Terms loop
            for P of TE.Postings loop
               if P.Deleted_By /= Database.Versioning.No_Transaction then
                  IX.Deleted_Posting_Count := IX.Deleted_Posting_Count + 1;
               end if;
            end loop;
         end loop;
         FT_Indexes.Replace_Element (Pos, IX);
      end;
   end Vacuum_Index;

   procedure Vacuum_All is
   begin
      if FT_Indexes.Length = 0 then
         return;
      end if;
      for I in 0 .. Natural (FT_Indexes.Length) - 1 loop
         if FT_Indexes.Element (I).Metadata.Owner_Key = Current_State_Key then
            Vacuum_Index (To_Wide_Wide_String (FT_Indexes.Element (I).Metadata.Name));
         end if;
      end loop;
   end Vacuum_All;

   procedure Clear is
   begin
      if FT_Indexes.Length = 0 then
         return;
      end if;
      for I in reverse 0 .. Natural (FT_Indexes.Length) - 1 loop
         if FT_Indexes.Element (I).Metadata.Owner_Key = Current_State_Key then
            FT_Indexes.Delete (I);
         end if;
      end loop;
   end Clear;

   function Full_Text_Index_Count return Natural is (Owned_Index_Count);
   function Exists (Name : Wide_Wide_String) return Boolean is
      Pos : constant Natural := Find_Index (Name);
   begin
      return Pos /= Natural'Last and then Index_Committed_Visible (FT_Indexes.Element (Pos));
   end Exists;
   function Term_Count (Name : Wide_Wide_String) return Natural is
      Pos : constant Natural := Find_Index (Name);
   begin
      if Pos = Natural'Last or else not Index_Committed_Visible (FT_Indexes.Element (Pos)) then
         return 0;
      else
         return Database.Full_Text.Indexes.Term_Count (FT_Indexes.Element (Pos));
      end if;
   end Term_Count;
   function Posting_Count (Name : Wide_Wide_String) return Natural is
      Pos : constant Natural := Find_Index (Name);
   begin
      if Pos = Natural'Last or else not Index_Committed_Visible (FT_Indexes.Element (Pos)) then
         return 0;
      else
         return Database.Full_Text.Indexes.Posting_Count (FT_Indexes.Element (Pos));
      end if;
   end Posting_Count;
   function Max_Commit_Version return Database.Versioning.Commit_Version is
      Max : Database.Versioning.Commit_Version := Database.Versioning.No_Version;
   begin
      for IX of FT_Indexes loop
         if IX.Metadata.Owner_Key = Current_State_Key then
            for TE of IX.Terms loop
               for P of TE.Postings loop
                  if P.Created_At > Max then
                     Max := P.Created_At;
                  end if;
                  if P.Deleted_At > Max then
                     Max := P.Deleted_At;
                  end if;
               end loop;
            end loop;
         end if;
      end loop;
      return Max;
   end Max_Commit_Version;

   function Obsolete_Posting_Count (Name : Wide_Wide_String) return Natural is
      Pos : constant Natural := Find_Index (Name);
   begin
      if Pos = Natural'Last or else not Index_Committed_Visible (FT_Indexes.Element (Pos)) then
         return 0;
      else
         return FT_Indexes.Element (Pos).Deleted_Posting_Count;
      end if;
   end Obsolete_Posting_Count;
end Database.Full_Text;
