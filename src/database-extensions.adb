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

   function State_For (State_Key : Natural) return Extension_State_Access is
      S, Winner : Extension_State_Access;
   begin
      if State_Key = 0 then
         return Default_State'Access;
      end if;
      S := State_Reg.Find (State_Key);
      if S /= null then
         return S;
      end if;
      S := new Extension_State;              --  allocate outside the lock
      State_Reg.Insert (State_Key, S, Winner);
      if Winner /= S then
         Free_State (S);                      --  lost the race; free ours
         S := Winner;
      end if;
      return S;
   end State_For;

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
   end Drop_Database;

   function Register_Extension
     (DB        : in out Database.Handle;
      Extension : Extension_Definition) return Database.Status.Result is
      State : constant Extension_State_Access :=
        State_For (Database.Catalog_State_Key (DB));
   begin
      State.all.Extensions.Append (Extension);
      return Database.Status.Success;
   end Register_Extension;

   function Unregister_Extension
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result is
      State : constant Extension_State_Access :=
        State_For (Database.Catalog_State_Key (DB));
   begin
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
      State : constant Extension_State_Access :=
        State_For (Database.Catalog_State_Key (DB));
   begin
      State.all.Dependencies.Append (Dependency);
      return Database.Status.Success;
   end Add_Dependency;

   function Validate_Dependencies (State_Key : Natural) return Database.Status.Result is
      use Database.Extension_Metadata;
      State : constant Extension_State_Access := State_For (State_Key);
   begin
      if State.all.Dependencies.Length > 0 then
         for D of State.all.Dependencies loop
            declare
               Name : constant Wide_Wide_String := To_Wide_Wide_String (D.Object_Name);
               Found : Boolean := False;
            begin
               case D.Object_Kind is
                  when Scalar_Function_Object | Generated_Function_Object =>
                     Found := Database.Functions.Exists (State_Key, Name);
                  when Aggregate_Function_Object =>
                     Found := Database.Aggregate_Functions.Exists (State_Key, Name);
                  when Collation_Object =>
                     Found := Database.Collations.Exists (State_Key, Name);
                  when Tokenizer_Object =>
                     Found := Database.Full_Text.Tokenizers.Tokenizer_Exists (State_Key, Name);
                  when Ranking_Function_Object =>
                     Found := Database.Full_Text.Ranking.Ranking_Function_Exists (State_Key, Name);
                  when Validation_Hook_Object =>
                     Found := Database.Validation_Hooks.Exists (State_Key, Name);
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

   function Registered_Extensions (State_Key : Natural) return Extension_Vectors.Vector is
   begin
      return State_For (State_Key).all.Extensions;
   end Registered_Extensions;

   function Dependencies
     (State_Key : Natural) return Database.Extension_Metadata.Dependency_Vectors.Vector is
   begin
      return State_For (State_Key).all.Dependencies;
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

   procedure Clear (State_Key : Natural) is
      State : constant Extension_State_Access := State_For (State_Key);
   begin
      State.all.Extensions.Clear;
      State.all.Dependencies.Clear;
      Database.Aggregate_Functions.Clear (State_Key);
      Database.Collations.Clear (State_Key);
      Database.Functions.Clear (State_Key);
      Database.Full_Text.Ranking.Clear_Custom_Ranking (State_Key);
      Database.Full_Text.Tokenizers.Clear_Custom_Tokenizers (State_Key);
      Database.Validation_Hooks.Clear (State_Key);
   end Clear;

end Database.Extensions;
