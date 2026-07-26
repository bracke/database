with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Unchecked_Deallocation;
with Database.State_Registry;

package body Database.Aggregate_Functions is
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;
   type Aggregate_Entry is record
      Metadata : Aggregate_Metadata;
      Fn : Aggregate_Function;
   end record;
   package Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Aggregate_Entry);
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
   function Register_Aggregate
     (DB       : in out Database.Handle;
      Metadata : Aggregate_Metadata;
      Fn       : Aggregate_Function) return Database.Status.Result is
      Key : constant Natural := Database.Catalog_State_Key (DB);
      Reg : constant Registry_Access := Registry_For (Key);
      E : Aggregate_Entry;
      Pos : Natural;
   begin
      Pos := Find (Key, To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn.Initialize = null or else Fn.Step = null or else Fn.Finalize = null then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid aggregate registration");
      end if;
      E.Metadata := Metadata;
      E.Fn := Fn;
      if Pos = Natural'Last then
         Reg.all.Append (E);
      else
         Reg.all.Replace_Element (Pos, E);
      end if;
      return Database.Status.Success;
   end Register_Aggregate;
   function Evaluate
     (State_Key : Natural;
      Name  : Wide_Wide_String;
      Rows  : Database.Values.Value_Vector;
      Value : out Database.Values.Value) return Database.Status.Result is
      Reg : constant Registry_Access := Registry_For (State_Key);
      Pos : constant Natural := Find (State_Key, Name);
      State : Aggregate_State;
      R : Database.Status.Result;
      Args : Database.Values.Value_Vector;
   begin
      Value := Database.Values.Null_Value;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing aggregate: " & Name);
      end if;
      Reg.all.Element (Pos).Fn.Initialize.all (State);
      if Rows.Length > 0 then
         for I in 0 .. Natural (Rows.Length) - 1 loop
            Args.Clear;
            Args.Append (Rows.Element (I));
            Reg.all.Element (Pos).Fn.Step.all (State, Args, R);
            if not Database.Status.Is_Ok (R) then
               return R;
            end if;
         end loop;
      end if;
      Value := Reg.all.Element (Pos).Fn.Finalize.all (State);
      if Reg.all.Element (Pos).Metadata.Result_Type /= Database.Types.Null_Value
        and then Value.Kind /= Reg.all.Element (Pos).Metadata.Result_Type
      then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "wrong aggregate result type");
      end if;
      return Database.Status.Success;
   end Evaluate;
   function Exists (State_Key : Natural; Name : Wide_Wide_String) return Boolean
     is (Find (State_Key, Name) /= Natural'Last);
   function Registered_Metadata
     (State_Key : Natural)
      return Database.Extension_Metadata.Metadata_Vectors.Vector is
      Reg : constant Registry_Access := Registry_For (State_Key);
      OutV : Database.Extension_Metadata.Metadata_Vectors.Vector;
      M : Database.Extension_Metadata.Extension_Object_Metadata;
   begin
      if Reg.all.Length = 0 then
         return OutV;
      end if;
      for I in 0 .. Natural (Reg.all.Length) - 1 loop
         M.Extension_Name := Reg.all.Element (I).Metadata.Extension_Name;
         M.Object_Name := Reg.all.Element (I).Metadata.Name;
         M.Object_Kind := Database.Extension_Metadata.Aggregate_Function_Object;
         M.Version := Reg.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Reg.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism  :=
           (if Reg.all.Element (I).Metadata.Deterministic then
              Database.Extension_Metadata.Deterministic
            else
              Database.Extension_Metadata.Non_Deterministic);
         M.Argument_Count := Reg.all.Element (I).Metadata.Argument_Count;
         M.Estimated_Cost := Reg.all.Element (I).Metadata.Estimated_Cost;
         OutV.Append (M);
      end loop;
      return OutV;
   end Registered_Metadata;
   procedure Clear (State_Key : Natural) is
   begin
      Registry_For (State_Key).all.Clear;
   end Clear;
end Database.Aggregate_Functions;
