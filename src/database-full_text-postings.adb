with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;
package body Database.Full_Text.Postings is
   use type Ada.Containers.Count_Type;
   function Same_Row (Left, Right : Row_Reference) return Boolean is
   begin
      return Left.Table_Id = Right.Table_Id
        and then Left.Column_Id = Right.Column_Id
        and then
          ((Ada.Strings.Wide_Wide_Unbounded.Length (Left.Row_Key) > 0
            and then Ada.Strings.Wide_Wide_Unbounded.Length (Right.Row_Key) > 0
            and then Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Left.Row_Key)
              = Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Right.Row_Key))
           or else
             (Ada.Strings.Wide_Wide_Unbounded.Length (Left.Row_Key) = 0
              and then Ada.Strings.Wide_Wide_Unbounded.Length (Right.Row_Key) = 0
              and then Left.Row_Id = Right.Row_Id));
   end Same_Row;

   procedure Add_Position (P : in out Posting; Position : Natural) is
   begin
      P.Positions.Append (Position);
      P.Frequency := P.Frequency + 1;
   end Add_Position;

   function Build_Skip_Table
     (Postings : Posting_Vectors.Vector;
      Stride   : Positive := 8) return Skip_Entry_Vectors.Vector is
      R : Skip_Entry_Vectors.Vector;
      To_Pos : Natural;
   begin
      if Postings.Length = 0 then
         return R;
      end if;
      if Natural (Postings.Length) <= Stride then
         return R;
      end if;

      for I in 0 .. Natural (Postings.Length) - 1 loop
         if I + Stride < Natural (Postings.Length) then
            To_Pos := I + Stride;
            R.Append
              (Skip_Entry'(From_Index => I,
                To_Index   => To_Pos,
                Target     => Postings.Element (To_Pos).Ref));
         end if;
      end loop;
      return R;
   end Build_Skip_Table;

   function Row_Less (Left, Right : Row_Reference) return Boolean is
      Left_Key_Length  : constant Natural := Ada.Strings.Wide_Wide_Unbounded.Length (Left.Row_Key);
      Right_Key_Length : constant Natural := Ada.Strings.Wide_Wide_Unbounded.Length (Right.Row_Key);
   begin
      if Left.Table_Id /= Right.Table_Id then
         return Left.Table_Id < Right.Table_Id;
      end if;
      if Left.Column_Id /= Right.Column_Id then
         return Left.Column_Id < Right.Column_Id;
      end if;
      if Left_Key_Length = 0 and then Right_Key_Length = 0 then
         return Left.Row_Id < Right.Row_Id;
      end if;
      return Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Left.Row_Key)
        < Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Right.Row_Key);
   end Row_Less;

   function Intersect_With_Skips
     (Left, Right : Posting_Vectors.Vector;
      Stride      : Positive := 8) return Posting_Vectors.Vector is
      R : Posting_Vectors.Vector;
      L_Pos : Natural := 0;
      R_Pos : Natural := 0;
      L_Skips : constant Skip_Entry_Vectors.Vector := Build_Skip_Table (Left, Stride);
      R_Skips : constant Skip_Entry_Vectors.Vector := Build_Skip_Table (Right, Stride);

      function Skip_Target
        (Skips : Skip_Entry_Vectors.Vector;
         From  : Natural;
         To_Pos : out Natural;
         Target : out Row_Reference) return Boolean is
      begin
         for S of Skips loop
            if S.From_Index = From then
               To_Pos := S.To_Index;
               Target := S.Target;
               return True;
            end if;
         end loop;
         return False;
      end Skip_Target;

      Jump_Pos : Natural;
      Jump_Ref : Row_Reference;
   begin
      while L_Pos < Natural (Left.Length) and then R_Pos < Natural (Right.Length) loop
         declare
            LP : constant Posting := Left.Element (L_Pos);
            RP : constant Posting := Right.Element (R_Pos);
         begin
            if Same_Row (LP.Ref, RP.Ref) then
               R.Append (LP);
               L_Pos := L_Pos + 1;
               R_Pos := R_Pos + 1;
            elsif Row_Less (LP.Ref, RP.Ref) then
               if Skip_Target (L_Skips, L_Pos, Jump_Pos, Jump_Ref)
                 and then (Same_Row (Jump_Ref, RP.Ref) or else Row_Less (Jump_Ref, RP.Ref))
               then
                  L_Pos := Jump_Pos;
               else
                  L_Pos := L_Pos + 1;
               end if;
            else
               if Skip_Target (R_Skips, R_Pos, Jump_Pos, Jump_Ref)
                 and then (Same_Row (Jump_Ref, LP.Ref) or else Row_Less (Jump_Ref, LP.Ref))
               then
                  R_Pos := Jump_Pos;
               else
                  R_Pos := R_Pos + 1;
               end if;
            end if;
         end;
      end loop;
      return R;
   end Intersect_With_Skips;

   function Contains_Row (V : Posting_Vectors.Vector; R : Row_Reference) return Boolean is
   begin
      for P of V loop
         if Same_Row (P.Ref, R) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Row;

   function Intersect (Left, Right : Posting_Vectors.Vector) return Posting_Vectors.Vector is
      R : Posting_Vectors.Vector;
   begin
      --  Preserve correctness for arbitrary posting-list order. Callers that
      --  maintain sorted posting lists may opt in to Intersect_With_Skips.
      for L of Left loop
         if Contains_Row (Right, L.Ref) then
            R.Append (L);
         end if;
      end loop;
      return R;
   end Intersect;

   function Union (Left, Right : Posting_Vectors.Vector) return Posting_Vectors.Vector is
      R : Posting_Vectors.Vector := Left;
   begin
      for P of Right loop
         if not Contains_Row (R, P.Ref) then
            R.Append (P);
         end if;
      end loop;
      return R;
   end Union;

   function Difference (Left, Right : Posting_Vectors.Vector) return Posting_Vectors.Vector is
      R : Posting_Vectors.Vector;
   begin
      for P of Left loop
         if not Contains_Row (Right, P.Ref) then
            R.Append (P);
         end if;
      end loop;
      return R;
   end Difference;

   function Phrase_Match (P : Posting; Required_Positions : Position_Vectors.Vector) return Boolean is
   begin
      if Required_Positions.Length = 0 then
         return P.Positions.Length > 0;
      end if;
      for R of Required_Positions loop
         for Existing of P.Positions loop
            if Existing = R then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Phrase_Match;

   function Find_Row
     (V : Posting_Vectors.Vector;
      R : Row_Reference) return Natural is
   begin
      if V.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (V.Length) - 1 loop
         if Same_Row (V.Element (I).Ref, R) then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Row;

   function Phrase_Intersect
     (Left   : Posting_Vectors.Vector;
      Right  : Posting_Vectors.Vector;
      Offset : Positive) return Posting_Vectors.Vector is
      R : Posting_Vectors.Vector;
   begin
      for L of Left loop
         declare
            Pos : constant Natural := Find_Row (Right, L.Ref);
         begin
            if Pos /= Natural'Last then
               declare
                  RP : constant Posting := Right.Element (Pos);
                  Out_P : Posting := L;
                  Kept : Position_Vectors.Vector;
               begin
                  for LP of L.Positions loop
                     for RP_Pos of RP.Positions loop
                        if RP_Pos = LP + Offset then
                           Kept.Append (LP);
                        end if;
                     end loop;
                  end loop;
                  if Kept.Length > 0 then
                     Out_P.Positions := Kept;
                     Out_P.Frequency := Natural (Kept.Length);
                     R.Append (Out_P);
                  end if;
               end;
            end if;
         end;
      end loop;
      return R;
   end Phrase_Intersect;

   function Near_Intersect
     (Left         : Posting_Vectors.Vector;
      Right        : Posting_Vectors.Vector;
      Max_Distance : Positive) return Posting_Vectors.Vector is
      R : Posting_Vectors.Vector;
   begin
      for L of Left loop
         declare
            Pos : constant Natural := Find_Row (Right, L.Ref);
         begin
            if Pos /= Natural'Last then
               declare
                  RP : constant Posting := Right.Element (Pos);
                  Out_P : Posting := L;
                  Kept : Position_Vectors.Vector;
               begin
                  for LP of L.Positions loop
                     for RP_Pos of RP.Positions loop
                        declare
                           D : Natural;
                        begin
                           if RP_Pos >= LP then
                              D := RP_Pos - LP;
                           else
                              D := LP - RP_Pos;
                           end if;
                           if D <= Max_Distance then
                              Kept.Append (LP);
                           end if;
                        end;
                     end loop;
                  end loop;
                  if Kept.Length > 0 then
                     Out_P.Positions := Kept;
                     Out_P.Frequency := Natural (Kept.Length);
                     R.Append (Out_P);
                  end if;
               end;
            end if;
         end;
      end loop;
      return R;
   end Near_Intersect;

end Database.Full_Text.Postings;
