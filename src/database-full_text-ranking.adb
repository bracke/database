with Ada.Containers;
with Database.Extension_Metadata;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;
with Ada.Unchecked_Deallocation;

package body Database.Full_Text.Ranking is
   use type Ada.Containers.Count_Type;

   use Ada.Strings.Wide_Wide_Unbounded;
   type Ranking_Entry is record
      Metadata : Ranking_Metadata;
      Fn       : Ranking_Function;
   end record;
   package Ranking_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Ranking_Entry);
   type Registry_Access is access all Ranking_Vectors.Vector;
   type Registry_State_Entry is record Key : Natural := 0;
   Registry : Registry_Access := null;
   end record;
   package Registry_State_Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Registry_State_Entry);
   procedure Free_Registry is new Ada.Unchecked_Deallocation  (Object => Ranking_Vectors.Vector,
     Name => Registry_Access);
   Default_Registry : aliased Ranking_Vectors.Vector;
   States : Registry_State_Vectors.Vector;
   Current_Key : Natural := 0;
   function Current_Registry return Registry_Access is
   begin
      if Current_Key = 0 then
         return Default_Registry'Access;
      end if;
      if States.Length > 0 then
         for I in 0 .. Natural (States.Length) - 1 loop
            if States.Element (I).Key = Current_Key then
               return States.Element (I).Registry;
            end if;
         end loop;
      end if;
      declare
         E : Registry_State_Entry;
      begin
         E.Key := Current_Key;
         E.Registry := new Ranking_Vectors.Vector;
         States.Append (E);
         return E.Registry;
      end;
   end Current_Registry;

   procedure Select_Database (State_Key : Natural) is
   begin
      Current_Key := State_Key;
      if State_Key /= 0 then
         declare
            Ignore : constant Registry_Access := Current_Registry;
            pragma Unreferenced (Ignore);
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
         for I in reverse 0 .. Natural (States.Length)-1 loop
            if States.Element (I).Key = State_Key then
               declare
                  E : Registry_State_Entry := States.Element (I);
               begin
                  if E.Registry /= null then
                     Free_Registry (E.Registry);
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

   function Find_Custom (Name : Wide_Wide_String) return Natural is
   begin
      if Current_Registry.all.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Current_Registry.all.Length) - 1 loop
         if To_Wide_Wide_String (Current_Registry.all.Element (I).Metadata.Name) = Name then
            return I;
         end if;
      end loop;
      return Natural'Last;
   end Find_Custom;

   function Register_Ranking_Function
     (DB       : in out Database.Handle;
      Metadata : Ranking_Metadata;
      Fn       : Ranking_Function) return Database.Status.Result is
      E : Ranking_Entry;
      Pos : Natural;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Pos := Find_Custom (To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn = null or else not Metadata.Deterministic then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid ranking function registration");
      end if;
      E.Metadata := Metadata;
      E.Fn := Fn;
      if Pos = Natural'Last then
         Current_Registry.all.Append (E);
      else
         Current_Registry.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Ranking_Function;

   function Score_With
     (Name    : Wide_Wide_String;
      Context : Ranking_Context;
      Score_Value : out Score) return Database.Status.Result is
      Pos : constant Natural := Find_Custom (Name);
   begin
      Score_Value := 0.0;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing ranking function: " & Name);
      end if;
      Score_Value := Current_Registry.all.Element (Pos).Fn.all (Context);
      return Database.Status.Success;
   end Score_With;

   function Ranking_Function_Exists (Name : Wide_Wide_String) return Boolean is (Find_Custom (Name) /= Natural'Last);

   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector is
      V : Database.Extension_Metadata.Metadata_Vectors.Vector;
      M : Database.Extension_Metadata.Extension_Object_Metadata;
   begin
      if Current_Registry.all.Length = 0 then
         return V;
      end if;
      for I in 0 .. Natural (Current_Registry.all.Length) - 1 loop
         M.Extension_Name := Current_Registry.all.Element (I).Metadata.Extension_Name;
         M.Object_Name := Current_Registry.all.Element (I).Metadata.Name;
         M.Object_Kind := Database.Extension_Metadata.Ranking_Function_Object;
         M.Version := Current_Registry.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Current_Registry.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism := Database.Extension_Metadata.Deterministic;
         V.Append (M);
      end loop;
      return V;
   end Registered_Metadata;

   procedure Clear_Custom_Ranking is
   begin
      Current_Registry.all.Clear;
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
