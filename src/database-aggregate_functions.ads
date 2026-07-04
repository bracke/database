--  Ada-native aggregate function registry for grouped query execution.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Status;
with Database.Types;
with Database.Values;

--  Aggregate function registry support.
package Database.Aggregate_Functions is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Aggregate_State defines a public database type used by this package.
   type Aggregate_State is tagged record
      Values : Database.Values.Value_Vector;
   end record;

   --  Initialize_Callback defines a public database type used by this package.
   type Initialize_Callback is access procedure (State : in out Aggregate_State);
   --  Step_Callback defines a public database type used by this package.
   type Step_Callback is access procedure
     (State     : in out Aggregate_State;
      Arguments : Database.Values.Value_Vector;
      Result    : out Database.Status.Result);
   --  Finalize_Callback defines a public database type used by this package.
   type Finalize_Callback is access function
     (State : Aggregate_State) return Database.Values.Value;

   --  Aggregate_Function stores the public fields for this database abstraction.
   type Aggregate_Function is record
      Initialize : Initialize_Callback;
      Step       : Step_Callback;
      Finalize   : Finalize_Callback;
   end record;

   --  Aggregate_Metadata stores the public fields for this database abstraction.
   type Aggregate_Metadata is record
      Name             : Unbounded_Wide_Wide_String;
      Extension_Name   : Unbounded_Wide_Wide_String;
      Version          : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Argument_Count   : Natural := 1;
      Result_Type      : Database.Types.Value_Kind := Database.Types.Null_Value;
      Deterministic    : Boolean := True;
      Estimated_Cost   : Natural := 1;
   end record;

   --  Return register aggregate for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Fn fn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Aggregate
     (DB       : in out Database.Handle;
      Metadata : Aggregate_Metadata;
      Fn       : Aggregate_Function) return Database.Status.Result;

   --  Return evaluate for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Rows rows argument supplied to the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Evaluate
     (Name : Wide_Wide_String;
      Rows : Database.Values.Value_Vector;
      Value : out Database.Values.Value) return Database.Status.Result;

   --  Return exists for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Exists (Name : Wide_Wide_String) return Boolean;
   --  Return registered metadata for the supplied database state or arguments.
   --  @return Status result describing whether the operation succeeded.
   function Registered_Metadata return Database.Extension_Metadata.Metadata_Vectors.Vector;
   --  Selects the handle-owned callable registry used by legacy name-only lookup APIs.
   --  @param State_Key state key argument supplied to the operation.
   procedure Select_Database (State_Key : Natural);

   --  Drops all transient callable registrations owned by one database handle.
   --  @param State_Key state key argument supplied to the operation.
   procedure Drop_Database (State_Key : Natural);

   --  Perform clear for the supplied database state or arguments.
   procedure Clear;
end Database.Aggregate_Functions;
