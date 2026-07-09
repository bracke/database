with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Full_Text.Segments is
   use Ada.Strings.Wide_Wide_Unbounded;

   function Create (Id : Segment_Id) return Segment is
      S : Segment;
   begin
      S.Metadata.Id := Id;
      S.Metadata.State := Mutable_Segment;
      return S;
   end Create;

   function Find_Term (S : Segment; Term : Wide_Wide_String) return Natural is
   begin
      if S.Terms.Is_Empty then
         return Natural'Last;
      end if;

      for I in S.Terms.First_Index .. S.Terms.Last_Index loop
         if To_Wide_Wide_String (S.Terms.Element (I).Term) = Term then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Term;

   procedure Refresh_Metadata (S : in out Segment) is
      Count    : Natural := 0;
      Obsolete : Natural := 0;
   begin
      for T of S.Terms loop
         Count := Count + Natural (T.Postings.Length);
         for P of T.Postings loop
            if P.Deleted_By /= 0 or else P.Deleted_At /= 0 then
               Obsolete := Obsolete + 1;
            end if;
         end loop;
      end loop;
      S.Metadata.Term_Count := Natural (S.Terms.Length);
      S.Metadata.Posting_Count := Count;
      S.Metadata.Obsolete_Count := Obsolete;
   end Refresh_Metadata;

   procedure Add_Posting
     (S       : in out Segment;
      Term    : Wide_Wide_String;
      Posting : Database.Full_Text.Postings.Posting) is
      Pos : constant Natural := Find_Term (S, Term);
      E   : Segment_Term;
   begin
      if S.Metadata.State /= Mutable_Segment then
         return;
      end if;

      if Pos = Natural'Last then
         E.Term := To_Unbounded_Wide_Wide_String (Term);
         E.Postings.Append (Posting);
         S.Terms.Append (E);
      else
         E := S.Terms.Element (Pos);
         E.Postings.Append (Posting);
         S.Terms.Replace_Element (Pos, E);
      end if;

      Refresh_Metadata (S);
   end Add_Posting;

   function Lookup
     (S    : Segment;
      Term : Wide_Wide_String)
      return Database.Full_Text.Postings.Posting_Vectors.Vector is
      Pos : constant Natural := Find_Term (S, Term);
   begin
      if Pos = Natural'Last then
         return Database.Full_Text.Postings.Posting_Vectors.Empty_Vector;
      end if;
      return S.Terms.Element (Pos).Postings;
   end Lookup;

   procedure Seal (S : in out Segment) is
   begin
      if S.Metadata.State = Mutable_Segment then
         S.Metadata.State := Sealed_Segment;
      end if;
      Refresh_Metadata (S);
   end Seal;

   procedure Mark_Obsolete (S : in out Segment) is
   begin
      S.Metadata.State := Obsolete_Segment;
      Refresh_Metadata (S);
   end Mark_Obsolete;

   function Merge
     (Left, Right : Segment;
      New_Id      : Segment_Id) return Segment is
      M : Segment := Create (New_Id);
   begin
      for T of Left.Terms loop
         for P of T.Postings loop
            if P.Deleted_By = 0 and then P.Deleted_At = 0 then
               Add_Posting (M, To_Wide_Wide_String (T.Term), P);
            end if;
         end loop;
      end loop;

      for T of Right.Terms loop
         for P of T.Postings loop
            if P.Deleted_By = 0 and then P.Deleted_At = 0 then
               Add_Posting (M, To_Wide_Wide_String (T.Term), P);
            end if;
         end loop;
      end loop;

      Seal (M);
      return M;
   end Merge;

   function Compact
     (Input  : Segment_Vectors.Vector;
      New_Id : Segment_Id) return Segment is
      M : Segment := Create (New_Id);
   begin
      for S of Input loop
         if S.Metadata.State /= Obsolete_Segment then
            for T of S.Terms loop
               for P of T.Postings loop
                  if P.Deleted_By = 0 and then P.Deleted_At = 0 then
                     Add_Posting (M, To_Wide_Wide_String (T.Term), P);
                  end if;
               end loop;
            end loop;
         end if;
      end loop;
      Seal (M);
      return M;
   end Compact;

   function Needs_Compaction
     (Input  : Segment_Vectors.Vector;
      Policy : Segment_Compaction_Policy := Default_Compaction_Policy)
      return Boolean is
      Active   : constant Natural := Segment_Count (Input);
      Postings : constant Natural := Posting_Count (Input);
      Dead     : constant Natural := Obsolete_Count (Input);
   begin
      if Active > Policy.Max_Active_Segments then
         return True;
      end if;

      if Dead < Policy.Minimum_Obsolete_Postings then
         return False;
      end if;

      if Postings = 0 then
         return Dead > 0;
      end if;

      return (Dead * 100) / Postings >= Policy.Minimum_Obsolete_Percent;
   end Needs_Compaction;

   procedure Compact_With_Policy
     (Input     : in out Segment_Vectors.Vector;
      Next_Id   : in out Segment_Id;
      Compacted : out Boolean;
      Policy    : Segment_Compaction_Policy := Default_Compaction_Policy) is
      M : Segment;
   begin
      Compacted := False;
      if not Needs_Compaction (Input, Policy) then
         return;
      end if;

      M := Compact (Input, Next_Id);
      Next_Id := Next_Id + 1;
      Input.Clear;
      if M.Metadata.Posting_Count > 0 then
         Input.Append (M);
      end if;
      Compacted := True;
   end Compact_With_Policy;

   function Segment_Count (Input : Segment_Vectors.Vector) return Natural is
      Count : Natural := 0;
   begin
      for S of Input loop
         if S.Metadata.State /= Obsolete_Segment then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Segment_Count;

   function Posting_Count (Input : Segment_Vectors.Vector) return Natural is
      Count : Natural := 0;
   begin
      for S of Input loop
         if S.Metadata.State /= Obsolete_Segment then
            Count := Count + S.Metadata.Posting_Count;
         end if;
      end loop;
      return Count;
   end Posting_Count;

   function Obsolete_Count (Input : Segment_Vectors.Vector) return Natural is
      Count : Natural := 0;
   begin
      for S of Input loop
         Count := Count + S.Metadata.Obsolete_Count;
         if S.Metadata.State = Obsolete_Segment then
            Count := Count + S.Metadata.Posting_Count;
         end if;
      end loop;
      return Count;
   end Obsolete_Count;
end Database.Full_Text.Segments;
