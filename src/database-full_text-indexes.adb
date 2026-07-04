with Ada.Containers;
with Database.Rows;
with Database.Types;
with Database.Values;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Full_Text.Indexes is
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;
   use Ada.Strings.Wide_Wide_Unbounded;

   function Validate_Definition
     (Schema : Database.Schema.Table_Schema;
      Column : Natural) return Database.Status.Result is
      Pos : Natural;
   begin
      Pos := Database.Schema.Find_Column_Id_Position (Schema, Column);
      if Pos >= Database.Schema.Column_Count (Schema) then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "full-text column id does not exist");
      end if;
      if Schema.Columns.Element (Pos).Kind /= Database.Types.Text_Value then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "full-text indexes require text columns");
      end if;
      return Database.Status.Success;
   end Validate_Definition;

   function Create
     (Name   : Wide_Wide_String;
      Schema : Database.Schema.Table_Schema;
      Column : Natural) return Full_Text_Index is
      M : Full_Text_Index_Metadata;
   begin
      M.Name := To_Unbounded_Wide_Wide_String (Name);
      M.Table_Id := Schema.Table_Id;
      M.Table_Name := Schema.Name;
      M.Column_Id := Column;
      M.Tokenizer := Database.Full_Text.Tokenizers.Default_Config;
      M.Normalizer := Database.Full_Text.Normalization.Default_Config;
      return  (Metadata => M,
        Terms => Term_Entry_Vectors.Empty_Vector,
        Documents => Document_Stat_Vectors.Empty_Vector,
        Deleted_Posting_Count => 0);
   end Create;

   function Find_Document (Index : Full_Text_Index; Row_Id : Natural; Row_Key : Wide_Wide_String) return Natural is
   begin
      if Index.Documents.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Index.Documents.Length) - 1 loop
         declare
            D : constant Document_Stat := Index.Documents.Element (I);
         begin
            if D.Row_Id = Row_Id and then To_Wide_Wide_String (D.Row_Key) = Row_Key then
               return I;
            end if;
         end;
      end loop;
      return Natural'Last;
   end Find_Document;

   procedure Register_Document
     (Index       : in out Full_Text_Index;
      Row_Id      : Natural;
      Row_Key     : Wide_Wide_String;
      Token_Count : Natural) is
      Pos : constant Natural := Find_Document (Index, Row_Id, Row_Key);
      D   : Document_Stat;
   begin
      if Pos = Natural'Last then
         D.Row_Id := Row_Id;
         D.Row_Key := To_Unbounded_Wide_Wide_String (Row_Key);
         D.Token_Count := Token_Count;
         D.Deleted := False;
         Index.Documents.Append (D);
      else
         D := Index.Documents.Element (Pos);
         D.Token_Count := Token_Count;
         D.Deleted := False;
         Index.Documents.Replace_Element (Pos, D);
      end if;
   end Register_Document;

   function Find_Term (Index : Full_Text_Index; Term : Wide_Wide_String) return Natural is
   begin
      if Index.Terms.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Index.Terms.Length) - 1 loop
         if To_Wide_Wide_String (Index.Terms.Element (I).Term) = Term then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Term;

   procedure Add_Posting
     (Index : in out Full_Text_Index;
      Term  : Wide_Wide_String;
      P     : Database.Full_Text.Postings.Posting) is
      Pos : constant Natural := Find_Term (Index, Term);
      E : Term_Entry;
   begin
      if Pos = Natural'Last then
         E.Term := To_Unbounded_Wide_Wide_String (Term);
         E.Postings.Append (P);
         Index.Terms.Append (E);
      else
         declare
            Existing : Term_Entry := Index.Terms.Element (Pos);
         Merged : Boolean := False;
         begin
            if Existing.Postings.Length > 0 then
               for I in 0 .. Natural (Existing.Postings.Length) - 1 loop
                  declare
                     EP : Database.Full_Text.Postings.Posting := Existing.Postings.Element (I);
                  begin
                     if Database.Full_Text.Postings.Same_Row (EP.Ref, P.Ref)
                       and then EP.Deleted_By = 0
                       and then EP.Created_By = P.Created_By
                     then
                        for Position of P.Positions loop
                           EP.Positions.Append (Position);
                        end loop;
                        EP.Frequency := EP.Frequency + P.Frequency;
                        Existing.Postings.Replace_Element (I, EP);
                        Merged := True;
                     end if;
                  end;
               end loop;
            end if;
            if not Merged then
               Existing.Postings.Append (P);
            end if;
            Index.Terms.Replace_Element (Pos, Existing);
         end;
      end if;
   end Add_Posting;

   procedure Index_Row
     (Index   : in out Full_Text_Index;
      Tx      : in out Database.Transactions.Transaction;
      Row_Id  : Natural;
      Row_Key : Wide_Wide_String;
      Row     : Database.Rows.Row) is
      use type Database.Types.Value_Kind;
      Col : constant Natural := Index.Metadata.Column_Id;
   begin
      if Col >= Database.Rows.Column_Count (Row) then
         return;
      end if;
      declare
         V : constant Database.Values.Value := Database.Rows.Get (Row, Col);
      begin
         if V.Kind /= Database.Types.Text_Value then
            return;
         end if;
         declare Tokens : constant Database.Full_Text.Tokenizers.Token_Vectors.Vector  :=
            Database.Full_Text.Tokenizers.Tokenize (To_Wide_Wide_String (V.Text), Index.Metadata.Tokenizer);
         begin
            Register_Document (Index, Row_Id, Row_Key, Natural (Tokens.Length));
            for T of Tokens loop
               declare
                  Term : constant Wide_Wide_String  :=
                    Database.Full_Text.Normalization.Normalize  (To_Wide_Wide_String (T.Text),
                    Index.Metadata.Normalizer);
                  P : Database.Full_Text.Postings.Posting;
               begin
                  P.Ref :=  (Table_Id => Index.Metadata.Table_Id,
                    Row_Id => Row_Id,
                    Row_Key => To_Unbounded_Wide_Wide_String (Row_Key),
                    Column_Id => Col);
                  P.Created_By := Database.Transactions.Id (Tx);
                  P.Created_At := Database.Transactions.Commit_Version (Tx);
                  Database.Full_Text.Postings.Add_Position (P, T.Position);
                  Add_Posting (Index, Term, P);
               end;
            end loop;
         end;
      end;
   end Index_Row;

   procedure Index_Row_Committed
     (Index   : in out Full_Text_Index;
      Row_Id  : Natural;
      Row_Key : Wide_Wide_String;
      Row     : Database.Rows.Row) is
      use type Database.Types.Value_Kind;
      Col : constant Natural := Index.Metadata.Column_Id;
   begin
      if Col >= Database.Rows.Column_Count (Row) then
         return;
      end if;
      declare
         V : constant Database.Values.Value := Database.Rows.Get (Row, Col);
      begin
         if V.Kind /= Database.Types.Text_Value then
            return;
         end if;
         declare Tokens : constant Database.Full_Text.Tokenizers.Token_Vectors.Vector  :=
            Database.Full_Text.Tokenizers.Tokenize (To_Wide_Wide_String (V.Text), Index.Metadata.Tokenizer);
         begin
            Register_Document (Index, Row_Id, Row_Key, Natural (Tokens.Length));
            for T of Tokens loop
               declare
                  Term : constant Wide_Wide_String  :=
                    Database.Full_Text.Normalization.Normalize  (To_Wide_Wide_String (T.Text),
                    Index.Metadata.Normalizer);
                  P : Database.Full_Text.Postings.Posting;
               begin
                  P.Ref :=  (Table_Id => Index.Metadata.Table_Id,
                    Row_Id => Row_Id,
                    Row_Key => To_Unbounded_Wide_Wide_String (Row_Key),
                    Column_Id => Col);
                  P.Created_By := Database.Versioning.No_Transaction;
                  P.Created_At := Database.Versioning.No_Version;
                  Database.Full_Text.Postings.Add_Position (P, T.Position);
                  Add_Posting (Index, Term, P);
               end;
            end loop;
         end;
      end;
   end Index_Row_Committed;

   procedure Delete_Row
     (Index   : in out Full_Text_Index;
      Tx      : in out Database.Transactions.Transaction;
      Row_Id  : Natural;
      Row_Key : Wide_Wide_String) is
   begin
      if Index.Terms.Length = 0 then
         return;
      end if;
      declare
         Doc_Pos : constant Natural := Find_Document (Index, Row_Id, Row_Key);
      begin
         if Doc_Pos /= Natural'Last then
            declare
               D : Document_Stat := Index.Documents.Element (Doc_Pos);
            begin
               D.Deleted := True;
               Index.Documents.Replace_Element (Doc_Pos, D);
            end;
         end if;
      end;

      for TI in 0 .. Natural (Index.Terms.Length) - 1 loop
         declare
            TE : Term_Entry := Index.Terms.Element (TI);
         begin
            if TE.Postings.Length > 0 then
               for PI in 0 .. Natural (TE.Postings.Length) - 1 loop
                  declare
                     P : Database.Full_Text.Postings.Posting := TE.Postings.Element (PI);
                  begin
                     if (P.Ref.Row_Id = Row_Id and then To_Wide_Wide_String (P.Ref.Row_Key) = Row_Key)
                       and then P.Deleted_By = 0 then
                        P.Deleted_By := Database.Transactions.Id (Tx);
                        P.Deleted_At := Database.Transactions.Snapshot_Version (Tx) + 1;
                        TE.Postings.Replace_Element (PI, P);
                        Index.Deleted_Posting_Count := Index.Deleted_Posting_Count + 1;
                     end if;
                  end;
               end loop;
            end if;
            Index.Terms.Replace_Element (TI, TE);
         end;
      end loop;
   end Delete_Row;

   function Lookup
     (Index : Full_Text_Index;
      Term  : Wide_Wide_String) return Database.Full_Text.Postings.Posting_Vectors.Vector is
      N : constant Wide_Wide_String := Database.Full_Text.Normalization.Normalize (Term, Index.Metadata.Normalizer);
      Pos : constant Natural := Find_Term (Index, N);
   begin
      if Pos = Natural'Last then
         return Database.Full_Text.Postings.Posting_Vectors.Empty_Vector;
      end if;
      return Index.Terms.Element (Pos).Postings;
   end Lookup;

   function Starts_With (S, Prefix : Wide_Wide_String) return Boolean is
   begin
      return Prefix'Length <= S'Length and then S (S'First .. S'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Lookup_Prefix
     (Index  : Full_Text_Index;
      Prefix : Wide_Wide_String) return Database.Full_Text.Postings.Posting_Vectors.Vector is
      N : constant Wide_Wide_String := Database.Full_Text.Normalization.Normalize (Prefix, Index.Metadata.Normalizer);
      R : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      for E of Index.Terms loop
         if Starts_With (To_Wide_Wide_String (E.Term), N) then
            R := Database.Full_Text.Postings.Union (R, E.Postings);
         end if;
      end loop;
      return R;
   end Lookup_Prefix;

   function Minimum (A, B, C : Natural) return Natural is
      R : Natural := A;
   begin
      if B < R then
         R := B;
      end if;
      if C < R then
         R := C;
      end if;
      return R;
   end Minimum;

   function Edit_Distance (Left, Right : Wide_Wide_String; Limit : Natural) return Natural is
      Prev : array (Natural range 0 .. Right'Length) of Natural;
      Curr : array (Natural range 0 .. Right'Length) of Natural;
      Cost : Natural;
      Best : Natural;
   begin
      if Left'Length = 0 then
         return Right'Length;
      end if;
      if Right'Length = 0 then
         return Left'Length;
      end if;
      if Left'Length > Right'Length + Limit or else Right'Length > Left'Length + Limit then
         return Limit + 1;
      end if;
      for J in Prev'Range loop
         Prev (J) := J;
      end loop;
      for I in 1 .. Left'Length loop
         Curr (0) := I;
         Best := Curr (0);
         for J in 1 .. Right'Length loop
            if Left (Left'First + I - 1) = Right (Right'First + J - 1) then
               Cost := 0;
            else
               Cost := 1;
            end if;
            Curr (J) := Minimum (Prev (J) + 1, Curr (J - 1) + 1, Prev (J - 1) + Cost);
            if Curr (J) < Best then
               Best := Curr (J);
            end if;
         end loop;
         if Best > Limit then
            return Limit + 1;
         end if;
         for J in Prev'Range loop
            Prev (J) := Curr (J);
         end loop;
      end loop;
      return Prev (Right'Length);
   end Edit_Distance;

   function Lookup_Fuzzy
     (Index             : Full_Text_Index;
      Term              : Wide_Wide_String;
      Max_Edit_Distance : Natural) return Database.Full_Text.Postings.Posting_Vectors.Vector is
      N : constant Wide_Wide_String := Database.Full_Text.Normalization.Normalize (Term, Index.Metadata.Normalizer);
      R : Database.Full_Text.Postings.Posting_Vectors.Vector;
   begin
      for E of Index.Terms loop
         declare
            T : constant Wide_Wide_String := To_Wide_Wide_String (E.Term);
         begin
            if Edit_Distance (T, N, Max_Edit_Distance) <= Max_Edit_Distance then
               R := Database.Full_Text.Postings.Union (R, E.Postings);
            end if;
         end;
      end loop;
      return R;
   end Lookup_Fuzzy;

   function Term_Count (Index : Full_Text_Index) return Natural is (Natural (Index.Terms.Length));
   function Posting_Count (Index : Full_Text_Index) return Natural is
      C : Natural := 0;
   begin
      for E of Index.Terms loop
         C := C + Natural (E.Postings.Length);
      end loop;
      return C;
   end Posting_Count;

   function Document_Count (Index : Full_Text_Index) return Natural is
      C : Natural := 0;
   begin
      for D of Index.Documents loop
         if not D.Deleted then
            C := C + 1;
         end if;
      end loop;
      return C;
   end Document_Count;

   function Document_Length
     (Index   : Full_Text_Index;
      Row_Key : Wide_Wide_String) return Natural is
   begin
      for D of Index.Documents loop
         if not D.Deleted and then To_Wide_Wide_String (D.Row_Key) = Row_Key then
            return D.Token_Count;
         end if;
      end loop;
      return 1;
   end Document_Length;

   function Average_Document_Length (Index : Full_Text_Index) return Natural is
      Total : Natural := 0;
      Count : Natural := 0;
   begin
      for D of Index.Documents loop
         if not D.Deleted then
            Total := Total + Natural'Max (1, D.Token_Count);
            Count := Count + 1;
         end if;
      end loop;
      if Count = 0 then
         return 1;
      end if;
      return Natural'Max (1, Total / Count);
   end Average_Document_Length;

   function Document_Frequency
     (Index : Full_Text_Index;
      Term  : Wide_Wide_String) return Natural is
      Seen : Document_Stat_Vectors.Vector;
      P    : constant Natural := Find_Term  (Index,
        Database.Full_Text.Normalization.Normalize (Term,
        Index.Metadata.Normalizer));
      Found : Boolean;
   begin
      if P = Natural'Last then
         return 0;
      end if;
      for Posting of Index.Terms.Element (P).Postings loop
         if Posting.Deleted_By = 0 and then Posting.Deleted_At = 0 then
            Found := False;
            for D of Seen loop
               if To_Wide_Wide_String (D.Row_Key) = To_Wide_Wide_String (Posting.Ref.Row_Key) then
                  Found := True;
               end if;
            end loop;
            if not Found then
               declare
                  D : Document_Stat;
               begin
                  D.Row_Id := Posting.Ref.Row_Id;
                  D.Row_Key := Posting.Ref.Row_Key;
                  Seen.Append (D);
               end;
            end if;
         end if;
      end loop;
      return Natural (Seen.Length);
   end Document_Frequency;

   procedure Recompute_Document_Statistics_From_Postings
     (Index : in out Full_Text_Index) is
      Pos : Natural;
      D   : Document_Stat;
      Max_Position : Natural;
   begin
      Index.Documents.Clear;
      for E of Index.Terms loop
         for P of E.Postings loop
            if P.Deleted_By = 0 and then P.Deleted_At = 0 then
               Max_Position := 0;
               for Position of P.Positions loop
                  if Position > Max_Position then
                     Max_Position := Position;
                  end if;
               end loop;
               Pos := Find_Document (Index, P.Ref.Row_Id, To_Wide_Wide_String (P.Ref.Row_Key));
               if Pos = Natural'Last then
                  D := (Row_Id => P.Ref.Row_Id,
                        Row_Key => P.Ref.Row_Key,
                        Token_Count => Max_Position + 1,
                        Deleted => False);
                  Index.Documents.Append (D);
               else
                  D := Index.Documents.Element (Pos);
                  if Max_Position + 1 > D.Token_Count then
                     D.Token_Count := Max_Position + 1;
                  end if;
                  D.Deleted := False;
                  Index.Documents.Replace_Element (Pos, D);
               end if;
            end if;
         end loop;
      end loop;
   end Recompute_Document_Statistics_From_Postings;
end Database.Full_Text.Indexes;
