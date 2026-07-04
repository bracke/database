with Ada.Containers;
with Database.Extension_Metadata;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;
with Ada.Unchecked_Deallocation;
with Database.Types;

package body Database.Aggregate_Functions is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;
   type Aggregate_Entry is record Metadata : Aggregate_Metadata;
   Fn : Aggregate_Function;
   end record;
   package Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Aggregate_Entry);
   type Registry_Access is access all Vectors.Vector;
   type Registry_State_Entry is record Key : Natural := 0;
   Registry : Registry_Access := null;
   end record;
   package Registry_State_Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Registry_State_Entry);
   procedure Free_Registry is new Ada.Unchecked_Deallocation (Object => Vectors.Vector, Name => Registry_Access);
   Default_Registry : aliased Vectors.Vector;
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
         E.Registry := new Vectors.Vector;
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
   function Register_Aggregate
     (DB       : in out Database.Handle;
      Metadata : Aggregate_Metadata;
      Fn       : Aggregate_Function) return Database.Status.Result is
      E : Aggregate_Entry;
      Pos : Natural;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Pos := Find (To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn.Initialize = null or else Fn.Step = null or else Fn.Finalize = null then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid aggregate registration");
      end if;
      E.Metadata := Metadata;
      E.Fn := Fn;
      if Pos = Natural'Last then
         Current_Registry.all.Append (E);
      else
         Current_Registry.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Aggregate;
   function Evaluate
     (Name  : Wide_Wide_String;
      Rows  : Database.Values.Value_Vector;
      Value : out Database.Values.Value) return Database.Status.Result is
      Pos : constant Natural := Find (Name);
      State : Aggregate_State;
      R : Database.Status.Result;
      Args : Database.Values.Value_Vector;
   begin
      Value := Database.Values.Null_Value;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing aggregate: " & Name);
      end if;
      Current_Registry.all.Element (Pos).Fn.Initialize.all (State);
      if Rows.Length > 0 then
         for I in 0 .. Natural (Rows.Length) - 1 loop
            Args.Clear;
            Args.Append (Rows.Element (I));
            Current_Registry.all.Element (Pos).Fn.Step.all (State, Args, R);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end loop;
      end if;
      Value := Current_Registry.all.Element (Pos).Fn.Finalize.all (State);
      if Current_Registry.all.Element (Pos).Metadata.Result_Type /= Database.Types.Null_Value
        and then Value.Kind /= Current_Registry.all.Element (Pos).Metadata.Result_Type then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "wrong aggregate result type");
      end if;
      return Database.Status.Success;
   end Evaluate;
   function Exists (Name : Wide_Wide_String) return Boolean is (Find (Name) /= Natural'Last);
   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector is
      OutV : Database.Extension_Metadata.Metadata_Vectors.Vector;
      M : Database.Extension_Metadata.Extension_Object_Metadata;
   begin
      if Current_Registry.all.Length = 0 then
         return OutV;
      end if;
      for I in 0 .. Natural (Current_Registry.all.Length) - 1 loop
         M.Extension_Name := Current_Registry.all.Element (I).Metadata.Extension_Name;
         M.Object_Name := Current_Registry.all.Element (I).Metadata.Name;
         M.Object_Kind := Database.Extension_Metadata.Aggregate_Function_Object;
         M.Version := Current_Registry.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Current_Registry.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism  :=
           (if Current_Registry.all.Element (I).Metadata.Deterministic then
              Database.Extension_Metadata.Deterministic
            else
              Database.Extension_Metadata.Non_Deterministic);
         M.Argument_Count := Current_Registry.all.Element (I).Metadata.Argument_Count;
         M.Estimated_Cost := Current_Registry.all.Element (I).Metadata.Estimated_Cost;
         OutV.Append (M);
      end loop;
      return OutV;
   end Registered_Metadata;
   procedure Clear is
   begin
      Current_Registry.all.Clear;
   end Clear;
end Database.Aggregate_Functions;
