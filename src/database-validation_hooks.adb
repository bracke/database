with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Unchecked_Deallocation;
with Database.State_Registry;

package body Database.Validation_Hooks is
   use type Ada.Containers.Count_Type;

   type Hook_Entry is record
      Metadata : Validation_Metadata;
      Hook     : Validation_Hook;
   end record;

   package Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Hook_Entry);
   type Registry_Access is access all Vectors.Vector;
   package State_Reg is new Database.State_Registry
     (Vectors.Vector, Registry_Access);
   procedure Free_Registry is new Ada.Unchecked_Deallocation (Object => Vectors.Vector, Name => Registry_Access);

   Default_Registry : aliased Vectors.Vector;
   Current_Key      : Natural := 0;
   pragma Thread_Local_Storage (Current_Key);

   function Current_Registry return Registry_Access is
      S, Winner : Registry_Access;
   begin
      if Current_Key = 0 then
         return Default_Registry'Access;
      end if;
      S := State_Reg.Find (Current_Key);
      if S /= null then
         return S;
      end if;
      S := new Vectors.Vector;
      State_Reg.Insert (Current_Key, S, Winner);
      if Winner /= S then
         Free_Registry (S);
         S := Winner;
      end if;
      return S;
   end Current_Registry;

   procedure Select_Database (State_Key : Natural) is
   begin
      Current_Key := State_Key;
      if State_Key /= 0 then
         declare
            Ignore : constant Registry_Access := Current_Registry;
         begin
            null;
         end;
      end if;
   end Select_Database;

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
      if Current_Key = State_Key then
         Current_Key := 0;
      end if;
   end Drop_Database;

   function Find (Name : Wide_Wide_String) return Natural is
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
   end Find;

   function Register_Validation_Hook
     (DB       : in out Database.Handle;
      Metadata : Validation_Metadata;
      Hook     : Validation_Hook) return Database.Status.Result is
      E   : Hook_Entry;
      Pos : Natural;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Pos := Find (To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Hook = null or else not Metadata.Deterministic then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid validation hook registration");
      end if;
      E.Metadata := Metadata;
      E.Hook := Hook;
      if Pos = Natural'Last then
         Current_Registry.all.Append (E);
      else
         Current_Registry.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Validation_Hook;

   function Validate
     (Name   : Wide_Wide_String;
      Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Database.Status.Result is
      Pos : constant Natural := Find (Name);
   begin
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing validation hook: " & Name);
      end if;
      return Current_Registry.all.Element (Pos).Hook.all (Schema, Row);
   end Validate;

   function Exists (Name : Wide_Wide_String) return Boolean is (Find (Name) /= Natural'Last);

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
         M.Object_Kind := Database.Extension_Metadata.Validation_Hook_Object;
         M.Version := Current_Registry.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Current_Registry.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism := Database.Extension_Metadata.Deterministic;
         V.Append (M);
      end loop;
      return V;
   end Registered_Metadata;

   procedure Clear is
   begin
      Current_Registry.all.Clear;
   end Clear;
end Database.Validation_Hooks;
