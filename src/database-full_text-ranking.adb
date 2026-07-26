with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Unchecked_Deallocation;
with Database.State_Registry;

package body Database.Full_Text.Ranking is
   use type Ada.Containers.Count_Type;

   type Ranking_Entry is record
      Metadata : Ranking_Metadata;
      Fn       : Ranking_Function;
   end record;
   package Ranking_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Ranking_Entry);
   type Registry_Access is access all Ranking_Vectors.Vector;
   package State_Reg is new Database.State_Registry (Ranking_Vectors.Vector, Registry_Access);
   procedure Free_Registry is new Ada.Unchecked_Deallocation  (Object => Ranking_Vectors.Vector,
     Name => Registry_Access);
   Default_Registry : aliased Ranking_Vectors.Vector;

   function Registry_For (State_Key : Natural) return Registry_Access is
      S, Winner : Registry_Access;
   begin
      if State_Key = 0 then
         return Default_Registry'Access;
      end if;
      S := State_Reg.Find (State_Key);
      if S /= null then
         return S;
      end if;
      S := new Ranking_Vectors.Vector;
      State_Reg.Insert (State_Key, S, Winner);
      if Winner /= S then
         Free_Registry (S);
         S := Winner;
      end if;
      return S;
   end Registry_For;

   procedure Drop_Database (State_Key : Natural) is
      Freed : Registry_Access;
   begin
      if State_Key = 0 then
         return;
      end if;
      State_Reg.Remove (State_Key, Freed);
      if Freed /= null then
         Free_Registry (Freed);
      end if;
   end Drop_Database;

   function Find_Custom (State_Key : Natural; Name : Wide_Wide_String) return Natural is
      Reg : constant Registry_Access := Registry_For (State_Key);
   begin
      if Reg.all.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Reg.all.Length) - 1 loop
         if To_Wide_Wide_String (Reg.all.Element (I).Metadata.Name) = Name then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Custom;

   function Register_Ranking_Function
     (DB       : in out Database.Handle;
      Metadata : Ranking_Metadata;
      Fn       : Ranking_Function) return Database.Status.Result is
      Key : constant Natural := Database.Catalog_State_Key (DB);
      Reg : constant Registry_Access := Registry_For (Key);
      E : Ranking_Entry;
      Pos : Natural;
   begin
      Pos := Find_Custom (Key, To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn = null or else not Metadata.Deterministic then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid ranking function registration");
      end if;
      E.Metadata := Metadata;
      E.Fn := Fn;
      if Pos = Natural'Last then
         Reg.all.Append (E);
      else
         Reg.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Ranking_Function;

   function Score_With
     (State_Key : Natural;
      Name    : Wide_Wide_String;
      Context : Ranking_Context;
      Score_Value : out Score) return Database.Status.Result is
      Reg : constant Registry_Access := Registry_For (State_Key);
      Pos : constant Natural := Find_Custom (State_Key, Name);
   begin
      Score_Value := 0.0;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing ranking function: " & Name);
      end if;
      Score_Value := Reg.all.Element (Pos).Fn.all (Context);
      return Database.Status.Success;
   end Score_With;

   function Ranking_Function_Exists (State_Key : Natural; Name : Wide_Wide_String) return Boolean
     is (Find_Custom (State_Key, Name) /= Natural'Last);

   function Registered_Metadata
     (State_Key : Natural)
      return Database.Extension_Metadata.Metadata_Vectors.Vector is
      Reg : constant Registry_Access := Registry_For (State_Key);
      V : Database.Extension_Metadata.Metadata_Vectors.Vector;
      M : Database.Extension_Metadata.Extension_Object_Metadata;
   begin
      if Reg.all.Length = 0 then
         return V;
      end if;
      for I in 0 .. Natural (Reg.all.Length) - 1 loop
         M.Extension_Name := Reg.all.Element (I).Metadata.Extension_Name;
         M.Object_Name := Reg.all.Element (I).Metadata.Name;
         M.Object_Kind := Database.Extension_Metadata.Ranking_Function_Object;
         M.Version := Reg.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Reg.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism := Database.Extension_Metadata.Deterministic;
         V.Append (M);
      end loop;
      return V;
   end Registered_Metadata;

   procedure Clear_Custom_Ranking (State_Key : Natural) is
   begin
      Registry_For (State_Key).all.Clear;
   end Clear_Custom_Ranking;
   function Frequency_Score (P : Database.Full_Text.Postings.Posting) return Score is
   begin
      return Score (P.Frequency);
   end Frequency_Score;

   function Matched_Term_Score
     (Matched_Terms : Natural;
      Frequency     : Natural;
      Phrase_Bonus  : Boolean := False) return Score is
      S : Score := Score (Matched_Terms) + Score (Frequency) / 10.0;
   begin
      if Phrase_Bonus then
         S := S + 1.0;
      end if;
      return S;
   end Matched_Term_Score;

   function BM25_Score
     (Term_Frequency          : Natural;
      Document_Frequency      : Natural;
      Total_Documents         : Natural;
      Document_Length         : Natural;
      Average_Document_Length : Score) return Score is
      K1  : constant Score := 1.2;
      B   : constant Score := 0.75;
      TF  : constant Score := Score (Term_Frequency);
      DL  : constant Score := Score (Document_Length);
      Avg : constant Score := Score'Max (Average_Document_Length, 1.0);
      N   : constant Score := Score'Max (Score (Total_Documents), 1.0);
      DF  : constant Score := Score'Max (Score (Document_Frequency), 1.0);
      --  Conservative positive IDF approximation. This avoids depending on
      --  elementary-log functions and remains monotonic with rarity.
      IDF : constant Score := (N + 1.0) / (DF + 1.0);
      Den : constant Score := TF + K1 * (1.0 - B + B * DL / Avg);
   begin
      if Term_Frequency = 0 then
         return 0.0;
      end if;
      return IDF * ((TF * (K1 + 1.0)) / Den);
   end BM25_Score;

   function Query_Score
     (Posting                 : Database.Full_Text.Postings.Posting;
      Total_Documents         : Natural;
      Document_Frequency      : Natural;
      Average_Document_Length : Score;
      Document_Length         : Natural;
      Matched_Terms           : Natural := 1;
      Phrase_Bonus            : Boolean := False) return Score is
      S : Score := BM25_Score
        (Term_Frequency          => Posting.Frequency,
         Document_Frequency      => Document_Frequency,
         Total_Documents         => Total_Documents,
         Document_Length         => Document_Length,
         Average_Document_Length => Average_Document_Length);
   begin
      S := S + Score (Matched_Terms) * 0.25;
      if Phrase_Bonus then
         S := S + 2.0;
      end if;
      return S;
   end Query_Score;
end Database.Full_Text.Ranking;
