with Ada.Containers;
with Database.Extension_Metadata;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;
with Database.Metrics;
with Database.Tracing;
with Database.Types;
with Ada.Unchecked_Deallocation;

package body Database.Functions is
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;

   type Function_Entry (Argument_Count : Function_Argument_Count := 0) is record
      Metadata : Function_Metadata (Argument_Count);
      Fn       : Scalar_Function;
   end record;

   package Function_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Function_Entry);

   type Registry_Access is access all Function_Vectors.Vector;
   type Registry_State_Entry is record
      Key      : Natural := 0;
      Registry : Registry_Access := null;
   end record;

   package Registry_State_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Registry_State_Entry);

   procedure Free_Registry is new Ada.Unchecked_Deallocation
     (Object => Function_Vectors.Vector, Name => Registry_Access);

   Default_Registry : Registry_Access := new Function_Vectors.Vector;
   States      : Registry_State_Vectors.Vector;
   Current_Key : Natural := 0;

   function Current_Registry return Registry_Access is
   begin
      if Current_Key = 0 then
         return Default_Registry;
      end if;
      if States.Length > 0 then
         for I in 0 .. Natural (States.Length) - 1 loop
            if States.Element (I).Key = Current_Key then
               if States.Element (I).Registry = null then
                  declare
                     E : Registry_State_Entry := States.Element (I);
                  begin
                     E.Registry := new Function_Vectors.Vector;
                     States.Replace_Element (I, E);
                  end;
               end if;
               return States.Element (I).Registry;
            end if;
         end loop;
      end if;
      declare
         E : Registry_State_Entry;
      begin
         E.Key := Current_Key;
         E.Registry := new Function_Vectors.Vector;
         States.Append (E);
         return States.Element (Natural (States.Length) - 1).Registry;
      end;
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
   begin
      if State_Key = 0 then
         return;
      end if;
      if States.Length > 0 then
         for I in reverse 0 .. Natural (States.Length) - 1 loop
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
      Registry : constant Registry_Access := Current_Registry;
   begin
      if Registry = null or else Registry.all.Length = 0 then
         return Natural'Last;
      end if;
      for I in 0 .. Natural (Registry.all.Length) - 1 loop
         declare
            E : constant Function_Vectors.Constant_Reference_Type :=
              Function_Vectors.Constant_Reference (Registry.all, I);
         begin
            if To_Wide_Wide_String (E.Element.Metadata.Name) = Name then
               return I;
            end if;
         end;
      end loop;
      return Natural'Last;
   end Find;

   function Register_Function
     (DB       : in out Database.Handle;
      Metadata : Function_Metadata;
      Fn       : Scalar_Function) return Database.Status.Result is
      Pos : Natural;
      Registry : Registry_Access;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Registry := Current_Registry;
      Pos := Find (To_Wide_Wide_String (Metadata.Name));
      if Length (Metadata.Name) = 0 or else Fn = null then
         return Database.Status.Failure (Database.Status.Invalid_Argument, "invalid scalar function registration");
      end if;
      if Pos = Natural'Last then
         Registry.all.Append
           (Function_Entry'
              (Argument_Count => Metadata.Argument_Count,
               Metadata       => Metadata,
               Fn             => Fn));
      else
         Registry.all.Replace_Element
           (Pos,
            Function_Entry'
              (Argument_Count => Metadata.Argument_Count,
               Metadata       => Metadata,
               Fn             => Fn));
      end if;
      return Database.Status.Success;
   end Register_Function;

   function Unregister_Function
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result is
      Pos : Natural;
      Registry : Registry_Access;
   begin
      Select_Database (Database.Catalog_State_Key (DB));
      Registry := Current_Registry;
      Pos := Find (Name);
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Not_Found, "scalar function is not registered");
      end if;
      Registry.all.Delete (Pos);
      return Database.Status.Success;
   end Unregister_Function;

   function Exists (Name : Wide_Wide_String) return Boolean is
   begin
      return Find (Name) /= Natural'Last;
   end Exists;

   function Metadata_Of
     (Name     : Wide_Wide_String;
      Metadata : out Function_Metadata) return Database.Status.Result is
      Pos : constant Natural := Find (Name);
      Registry : constant Registry_Access := Current_Registry;
   begin
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing scalar function: " & Name);
      end if;
      Metadata := Registry.all.Element (Pos).Metadata;
      return Database.Status.Success;
   end Metadata_Of;

   function Evaluate
     (Name      : Wide_Wide_String;
      Arguments : Database.Values.Value_Vector;
      Value     : out Database.Values.Value) return Database.Status.Result is
      Pos : constant Natural := Find (Name);
      Registry : constant Registry_Access := Current_Registry;
   begin
      Value := Database.Values.Null_Value;
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing scalar function: " & Name);
      end if;
      declare
         E : constant Function_Vectors.Constant_Reference_Type :=
           Function_Vectors.Constant_Reference (Registry.all, Pos);
      begin
         if Natural (Arguments.Length) /= E.Element.Metadata.Argument_Count then
            return Database.Status.Failure (Database.Status.Invalid_Argument, "wrong scalar function argument count");
         end if;
         if E.Element.Metadata.Argument_Count > 0 then
            for I in 1 .. E.Element.Metadata.Argument_Count loop
               if E.Element.Metadata.Argument_Types (I) /= Database.Types.Null_Value
                 and then Arguments.Element (I - 1).Kind /= E.Element.Metadata.Argument_Types (I)
               then
                  return Database.Status.Failure
                    (Database.Status.Invalid_Argument,
                     "wrong scalar function argument type");
               end if;
            end loop;
         end if;
         Value := E.Element.Fn.all (Arguments);
         Database.Metrics.Increment_Extension_Invocations;
         Database.Tracing.Emit_Trace ((0, Database.Tracing.Extension_Trace,
           Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String ("scalar extension function invoked"), False));
         if E.Element.Metadata.Result_Type /= Database.Types.Null_Value
           and then Value.Kind /= E.Element.Metadata.Result_Type
         then
            return Database.Status.Failure (Database.Status.Invalid_Argument, "wrong scalar function result type");
         end if;
         if not E.Element.Metadata.Nullable_Result and then Value.Kind = Database.Types.Null_Value then
            return Database.Status.Failure (Database.Status.Constraint_Error,
              "scalar function returned NULL where non-null result was required");
         end if;
      end;
      return Database.Status.Success;
   end Evaluate;

   function Validate_Persistent_Use (Name : Wide_Wide_String) return Database.Status.Result is
      Pos : constant Natural := Find (Name);
      Registry : constant Registry_Access := Current_Registry;
   begin
      if Pos = Natural'Last then
         return Database.Status.Failure (Database.Status.Missing_Extension, "missing scalar function: " & Name);
      end if;
      if not Registry.all.Element (Pos).Metadata.Deterministic then
         return Database.Status.Failure (Database.Status.Extension_Error,
           "non-deterministic function cannot be used in persistent expressions");
      end if;
      return Database.Status.Success;
   end Validate_Persistent_Use;

   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector is
      V : Database.Extension_Metadata.Metadata_Vectors.Vector;
      M : Database.Extension_Metadata.Extension_Object_Metadata;
      Registry : constant Registry_Access := Current_Registry;
   begin
      if Registry = null or else Registry.all.Length = 0 then
         return V;
      end if;
      for I in 0 .. Natural (Registry.all.Length) - 1 loop
         M.Extension_Name := Registry.all.Element (I).Metadata.Extension_Name;
         M.Object_Name := Registry.all.Element (I).Metadata.Name;
         M.Object_Kind := Database.Extension_Metadata.Scalar_Function_Object;
         M.Version := Registry.all.Element (I).Metadata.Version;
         M.Compatibility_Id := Registry.all.Element (I).Metadata.Compatibility_Id;
         M.Determinism  :=
           (if Registry.all.Element (I).Metadata.Deterministic then
              Database.Extension_Metadata.Deterministic
            else
              Database.Extension_Metadata.Non_Deterministic);
         M.Nullable_Result := Registry.all.Element (I).Metadata.Nullable_Result;
         M.Argument_Count := Registry.all.Element (I).Metadata.Argument_Count;
         M.Index_Compatible := Registry.all.Element (I).Metadata.Index_Compatible;
         M.Monotonic := Registry.all.Element (I).Metadata.Monotonic;
         M.Estimated_Cost := Registry.all.Element (I).Metadata.Estimated_Cost;
         V.Append (M);
      end loop;
      return V;
   end Registered_Metadata;

   procedure Clear is
   begin
      Current_Registry.all.Clear;
   end Clear;
end Database.Functions;
