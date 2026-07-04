with Ada.Containers;
with Database.Aggregate_Functions;
with Database.Collations;
with Database.Functions;
with Database.Full_Text.Ranking;
with Database.Full_Text.Tokenizers;
with Database.Validation_Hooks;

package body Database.Extensions is
   use type Ada.Containers.Count_Type;

   Current_State_Key : Natural := 0;
   Extensions        : Extension_Vectors.Vector;
   Dependency_List   : Database.Extension_Metadata.Dependency_Vectors.Vector;

   type Extension_State is record
      Key          : Natural := 0;
      Extensions   : Extension_Vectors.Vector;
      Dependencies : Database.Extension_Metadata.Dependency_Vectors.Vector;
   end record;

   package State_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Extension_State);

   States : State_Vectors.Vector;

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
      S   : Extension_State;
   begin
      if Current_State_Key = 0 then
         return;
      end if;

      Pos := State_Position (Current_State_Key);
      S.Key := Current_State_Key;
      S.Extensions := Extensions;
      S.Dependencies := Dependency_List;

      if Pos = Natural'Last then
         States.Append (S);
      else
         States.Replace_Element (Pos, S);
      end if;
   end Store_Current_State;

   procedure Load_State (State_Key : Natural) is
      Pos : constant Natural := State_Position (State_Key);
      S   : Extension_State;
   begin
      Extensions.Clear;
      Dependency_List.Clear;
      if State_Key = 0 then
         return;
      end if;
      if Pos = Natural'Last then
         S.Key := State_Key;
         States.Append (S);
      else
         Extensions := States.Element (Pos).Extensions;
         Dependency_List := States.Element (Pos).Dependencies;
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

   procedure Drop_Database (State_Key : Natural) is
      Pos : Natural;
   begin
      if Current_State_Key = State_Key then
         Clear;
         Current_State_Key := 0;
      end if;
      Pos := State_Position (State_Key);
      if Pos /= Natural'Last then
         States.Delete (Pos);
      end if;
   end Drop_Database;

   function Register_Extension
     (DB        : in out Database.Handle;
      Extension : Extension_Definition) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Extensions.Append (Extension);
      return Database.Status.Success;
   end Register_Extension;

   function Unregister_Extension
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      for Index in reverse 0 .. Natural (Extensions.Length) - 1 loop
         if To_Wide_Wide_String (Extensions.Element (Index).Name) = Name then
            Extensions.Delete (Index);
            return Database.Status.Success;
         end if;
      end loop;

      return Database.Status.Failure
        (Database.Status.Not_Found,
         "extension not registered");
   end Unregister_Extension;

   function Add_Dependency
     (DB         : in out Database.Handle;
      Dependency : Database.Extension_Metadata.Dependency)
      return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Dependency_List.Append (Dependency);
      return Database.Status.Success;
   end Add_Dependency;

   function Validate_Dependencies return Database.Status.Result is
      use Database.Extension_Metadata;
   begin
      if Dependency_List.Length > 0 then
         for D of Dependency_List loop
            declare
               Name : constant Wide_Wide_String := To_Wide_Wide_String (D.Object_Name);
               Found : Boolean := False;
            begin
               case D.Object_Kind is
                  when Scalar_Function_Object | Generated_Function_Object =>
                     Found := Database.Functions.Exists (Name);
                  when Aggregate_Function_Object =>
                     Found := Database.Aggregate_Functions.Exists (Name);
                  when Collation_Object =>
                     Found := Database.Collations.Exists (Name);
                  when Tokenizer_Object =>
                     Found := Database.Full_Text.Tokenizers.Tokenizer_Exists (Name);
                  when Ranking_Function_Object =>
                     Found := Database.Full_Text.Ranking.Ranking_Function_Exists (Name);
                  when Validation_Hook_Object =>
                     Found := Database.Validation_Hooks.Exists (Name);
               end case;

               if not Found then
                  return Database.Status.Failure
                    (Database.Status.Missing_Extension,
                     "missing extension dependency: " & Name);
               end if;
            end;
         end loop;
      end if;
      return Database.Status.Success;
   end Validate_Dependencies;

   function Registered_Extensions return Extension_Vectors.Vector is
   begin
      Store_Current_State;
      return Extensions;
   end Registered_Extensions;

   function Dependencies
      return Database.Extension_Metadata.Dependency_Vectors.Vector is
   begin
      Store_Current_State;
      return Dependency_List;
   end Dependencies;

   function Save (Path : Wide_Wide_String) return Database.Status.Result is
      pragma Unreferenced (Path);
   begin
      return Database.Status.Success;
   end Save;

   function Load (Path : Wide_Wide_String) return Database.Status.Result is
      pragma Unreferenced (Path);
   begin
      return Database.Status.Success;
   end Load;

   procedure Clear is
   begin
      Extensions.Clear;
      Dependency_List.Clear;
      Database.Aggregate_Functions.Clear;
      Database.Collations.Clear;
      Database.Functions.Clear;
      Database.Full_Text.Ranking.Clear_Custom_Ranking;
      Database.Full_Text.Tokenizers.Clear_Custom_Tokenizers;
      Database.Validation_Hooks.Clear;
   end Clear;

end Database.Extensions;
