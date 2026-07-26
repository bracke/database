with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Unchecked_Deallocation;
with Database.State_Registry;

package body Database.Collations is
   use type Ada.Containers.Count_Type;

   type Collation_Entry is record
      Metadata : Collation_Metadata;
      Fn       : Collation_Function;
   end record;

   package Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Collation_Entry);
   type Registry_Access is access all Vectors.Vector;
   package State_Reg is new Database.State_Registry
     (Vectors.Vector, Registry_Access);
   procedure Free_Registry is new Ada.Unchecked_Deallocation (Object => Vectors.Vector, Name => Registry_Access);

   Default_Registry : aliased Vectors.Vector;

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
      S := new Vectors.Vector;
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

   function Find
     (State_Key : Natural; Name : Wide_Wide_String) return Natural is
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
   end Find;

   function Register_Collation
     (DB       : in out Database.Handle;
      Metadata : Collation_Metadata;
      Fn       : Collation_Function) return Database.Status.Result is
      Key : constant Natural := Database.Catalog_State_Key (DB);
      Reg : constant Registry_Access := Registry_For (Key);
      E   : Collation_Entry;
      Pos : Natural;
   begin
      Pos := Find (Key, To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn = null then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid collation registration");
      end if;
      E.Metadata := Metadata;
      E.Fn := Fn;
      if Pos = Natural'Last then
         Reg.all.Append (E);
      else
         Reg.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Collation;

   function Compare
     (State_Key : Natural;
      Name, Left, Right : Wide_Wide_String;
      Result : out Integer) return Database.Status.Result is
      Reg : constant Registry_Access := Registry_For (State_Key);
      Pos : constant Natural := Find (State_Key, Name);
   begin
      Result := 0;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing collation: " & Name);
      end if;
      Result := Reg.all.Element (Pos).Fn.all (Left, Right);
      return Database.Status.Success;
   end Compare;

   function Exists (State_Key : Natural; Name : Wide_Wide_String) return Boolean
     is (Find (State_Key, Name) /= Natural'Last);

   function Validate_Index_Use
     (State_Key : Natural; Name : Wide_Wide_String) return Database.Status.Result is
      Reg : constant Registry_Access := Registry_For (State_Key);
      Pos : constant Natural := Find (State_Key, Name);
   begin
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing collation: " & Name);
      end if;
      if not Reg.all.Element (Pos).Metadata.Deterministic
        or else not Reg.all.Element (Pos).Metadata.Index_Compatible
      then
         return Database.Status.Failure (Database.Status.Extension_Error, "collation is not index-compatible");
      end if;
      return Database.Status.Success;
   end Validate_Index_Use;

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
         M.Object_Kind := Database.Extension_Metadata.Collation_Object;
         M.Version := Reg.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Reg.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism  :=
           (if Reg.all.Element (I).Metadata.Deterministic then
              Database.Extension_Metadata.Deterministic
            else
              Database.Extension_Metadata.Non_Deterministic);
         M.Index_Compatible := Reg.all.Element (I).Metadata.Index_Compatible;
         V.Append (M);
      end loop;
      return V;
   end Registered_Metadata;

   procedure Clear (State_Key : Natural) is
   begin
      Registry_For (State_Key).all.Clear;
   end Clear;
end Database.Collations;
