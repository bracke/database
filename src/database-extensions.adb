with Ada.Containers;
with Ada.Unchecked_Deallocation;
with Database.Aggregate_Functions;
with Database.Collations;
with Database.Functions;
with Database.Full_Text.Ranking;
with Database.Full_Text.Tokenizers;
with Database.State_Registry;
with Database.Validation_Hooks;

package body Database.Extensions is
   use type Ada.Containers.Count_Type;

   --  Per-database extension state, held by pointer in a protected registry so
   --  concurrent tasks operating different database handles stay isolated. The
   --  registry does no allocation under its lock; Current allocates outside it
   --  (see Database.State_Registry).
   type Extension_State is record
      Extensions   : Extension_Vectors.Vector;
      Dependencies : Database.Extension_Metadata.Dependency_Vectors.Vector;
   end record;
   type Extension_State_Access is access all Extension_State;

   package State_Reg is new Database.State_Registry
     (Extension_State, Extension_State_Access);
   procedure Free_State is new Ada.Unchecked_Deallocation
     (Object => Extension_State, Name => Extension_State_Access);

   Default_State : aliased Extension_State;
   Current_Key   : Natural := 0;
   pragma Thread_Local_Storage (Current_Key);

   function Current return Extension_State_Access is
      S, Winner : Extension_State_Access;
   begin
      if Current_Key = 0 then
         return Default_State'Access;
      end if;
      S := State_Reg.Find (Current_Key);
      if S /= null then
         return S;
      end if;
      S := new Extension_State;              --  allocate outside the lock
      State_Reg.Insert (Current_Key, S, Winner);
      if Winner /= S then
         Free_State (S);                      --  lost the race; free ours
         S := Winner;
      end if;
      return S;
   end Current;

   procedure Select_Database (State_Key : Natural) is
   begin
      Current_Key := State_Key;
      if State_Key /= 0 then
         declare
            Ignore : constant Extension_State_Access := Current;
            pragma Unreferenced (Ignore);
         begin
            null;
         end;
      end if;
   end Select_Database;

   procedure Drop_Database (State_Key : Natural) is
      Freed : Extension_State_Access;
   begin
      if State_Key = 0 then
         return;
      end if;
      State_Reg.Remove (State_Key, Freed);
      if Freed /= null then
         Free_State (Freed);                  --  free outside the lock
      end if;
      if Current_Key = State_Key then
         Current_Key := 0;
      end if;
   end Drop_Database;

   function Register_Extension
     (DB        : in out Database.Handle;
      Extension : Extension_Definition) return Database.Status.Result is
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Current.all.Extensions.Append (Extension);
      return Database.Status.Success;
   end Register_Extension;

   function Unregister_Extension
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result is
      State : Extension_State_Access;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      State := Current;
      for Index in reverse 0 .. Natural (State.all.Extensions.Length) - 1 loop
         if To_Wide_Wide_String (State.all.Extensions.Element (Index).Name) = Name
         then
            State.all.Extensions.Delete (Index);
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
      Current.all.Dependencies.Append (Dependency);
      return Database.Status.Success;
   end Add_Dependency;

   function Validate_Dependencies return Database.Status.Result is
      use Database.Extension_Metadata;
      State : constant Extension_State_Access := Current;
   begin
      if State.all.Dependencies.Length > 0 then
         for D of State.all.Dependencies loop
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
      return Current.all.Extensions;
   end Registered_Extensions;

   function Dependencies
      return Database.Extension_Metadata.Dependency_Vectors.Vector is
   begin
      return Current.all.Dependencies;
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
      Current.all.Extensions.Clear;
      Current.all.Dependencies.Clear;
      Database.Aggregate_Functions.Clear;
      Database.Collations.Clear;
      Database.Functions.Clear;
      Database.Full_Text.Ranking.Clear_Custom_Ranking;
      Database.Full_Text.Tokenizers.Clear_Custom_Tokenizers;
      Database.Validation_Hooks.Clear;
   end Clear;

end Database.Extensions;
