with Ada.Containers;
with Database.Full_Text.Normalization;
with Ada.Strings.Wide_Wide_Unbounded;

package body Database.Full_Text.Snippets is
   use type Ada.Containers.Count_Type;
   use Ada.Strings.Wide_Wide_Unbounded;

   function Default_Config return Snippet_Config is
   begin
      return (Context_Code_Points => 32,
              Marker_Start        => To_Unbounded_Wide_Wide_String ("["),
              Marker_End          => To_Unbounded_Wide_Wide_String ("]"));
   end Default_Config;

   function First_Term (Q : Database.Full_Text.Queries.Query) return Wide_Wide_String is
      use Database.Full_Text.Queries;
   begin
      case Kind (Q) is
         when Term_Query | Prefix_Query | Fuzzy_Query =>
            return Text (Q);
         when Phrase_Query =>
            declare
               Ts : constant Term_Vectors.Vector := Terms (Q);
            begin
               if Ts.Length = 0 then
                  return "";
               else
                  return To_Wide_Wide_String (Ts.Element (0));
               end if;
            end;
         when And_Query | Or_Query | Near_Query =>
            return First_Term (Left (Q));
         when Not_Query | Match_All =>
            return "";
      end case;
   end First_Term;

   function Contains_At
     (Text       : Wide_Wide_String;
      Pattern    : Wide_Wide_String;
      Start_Pos  : Positive) return Boolean is
   begin
      if Pattern'Length = 0 then
         return False;
      end if;
      if Start_Pos + Pattern'Length - 1 > Text'Last then
         return False;
      end if;
      return Text (Start_Pos .. Start_Pos + Pattern'Length - 1) = Pattern;
   end Contains_At;

   function Is_Combining_Mark (C : Wide_Wide_Character) return Boolean is
      P : constant Natural := Wide_Wide_Character'Pos (C);
   begin
      return P in 16#0300# .. 16#036F#
        or else P in 16#1AB0# .. 16#1AFF#
        or else P in 16#1DC0# .. 16#1DFF#
        or else P in 16#20D0# .. 16#20FF#
        or else P in 16#FE20# .. 16#FE2F#;
   end Is_Combining_Mark;

   function Extend_Left_To_Cluster
     (Text : Wide_Wide_String;
      Pos  : Natural) return Natural is
      R : Natural := Pos;
   begin
      while R > Text'First and then Is_Combining_Mark (Text (R)) loop
         R := R - 1;
      end loop;
      return R;
   end Extend_Left_To_Cluster;

   function Extend_Right_To_Cluster
     (Text : Wide_Wide_String;
      Pos  : Natural) return Natural is
      R : Natural := Pos;
   begin
      while R < Text'Last and then Is_Combining_Mark (Text (R + 1)) loop
         R := R + 1;
      end loop;
      return R;
   end Extend_Right_To_Cluster;

   function Generate
     (Text   : Wide_Wide_String;
      Query  : Database.Full_Text.Queries.Query;
      Config : Snippet_Config := Default_Config) return Wide_Wide_String is
      Term        : constant Wide_Wide_String := First_Term (Query);
      Normal_Text : constant Wide_Wide_String := Database.Full_Text.Normalization.Normalize (Text);
      Normal_Term : constant Wide_Wide_String := Database.Full_Text.Normalization.Normalize (Term);
      Match_Start : Natural := 0;
      Left_Edge   : Natural;
      Right_Edge  : Natural;
      Match_End   : Natural;
      R           : Unbounded_Wide_Wide_String;
   begin
      if Text'Length = 0 or else Term'Length = 0 then
         return Text;
      end if;

      for I in Normal_Text'Range loop
         if Contains_At (Normal_Text, Normal_Term, I) then
            Match_Start := I;
            exit;
         end if;
      end loop;

      if Match_Start = 0 then
         if Text'Length <= Config.Context_Code_Points * 2 then
            return Text;
         else
            return Text (Text'First .. Text'First + Config.Context_Code_Points * 2 - 1);
         end if;
      end if;

      if Match_Start > Config.Context_Code_Points then
         Left_Edge := Match_Start - Config.Context_Code_Points;
      else
         Left_Edge := Text'First;
      end if;
      Match_Start := Extend_Left_To_Cluster (Text, Match_Start);
      Match_End := Extend_Right_To_Cluster (Text, Match_Start + Term'Length - 1);
      Left_Edge := Extend_Left_To_Cluster (Text, Left_Edge);
      Right_Edge := Extend_Right_To_Cluster
        (Text,
         Natural'Min (Text'Last, Match_End + Config.Context_Code_Points));

      if Left_Edge > Text'First then
         Append (R, "...");
      end if;
      Append (R, Text (Left_Edge .. Match_Start - 1));
      Append (R, To_Wide_Wide_String (Config.Marker_Start));
      Append (R, Text (Match_Start .. Match_End));
      Append (R, To_Wide_Wide_String (Config.Marker_End));
      if Match_End < Right_Edge then
         Append (R, Text (Match_End + 1 .. Right_Edge));
      end if;
      if Right_Edge < Text'Last then
         Append (R, "...");
      end if;
      return To_Wide_Wide_String (R);
   end Generate;
end Database.Full_Text.Snippets;
