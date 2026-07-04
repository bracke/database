--  Ada-native scalar function registry for expressions, generated columns, and constraints.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Status;
with Database.Types;
with Database.Values;

--  Scalar function registry support.
package Database.Functions is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Scalar_Function defines a public database type used by this package.
   type Scalar_Function is access function
     (Arguments : Database.Values.Value_Vector) return Database.Values.Value;

   --  Argument_Type_Array defines a public database type used by this package.
   type Argument_Type_Array is array (Natural range <>) of Database.Types.Value_Kind;

   --  Maximum number of arguments accepted by scalar function metadata.
   Max_Function_Arguments : constant := 64;

   --  Function_Argument_Count defines the supported scalar function arity range.
   subtype Function_Argument_Count is Natural range 0 .. Max_Function_Arguments;

   --  Function_Metadata stores the public fields for this database abstraction.
   type Function_Metadata (Argument_Count : Function_Argument_Count := 0) is record
      Name            : Unbounded_Wide_Wide_String;
      Extension_Name  : Unbounded_Wide_Wide_String;
      Version         : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Deterministic   : Boolean := True;
      Nullable_Result : Boolean := True;
      Result_Type     : Database.Types.Value_Kind := Database.Types.Null_Value;
      Argument_Types  : Argument_Type_Array (1 .. Argument_Count);
      Index_Compatible : Boolean := False;
      Monotonic        : Boolean := False;
      Estimated_Cost   : Natural := 1;
   end record;

   --  Return register function for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Fn fn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Function
     (DB       : in out Database.Handle;
      Metadata : Function_Metadata;
      Fn       : Scalar_Function) return Database.Status.Result;

   --  Return unregister function for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Name logical name of the object.
   --  @return Status result describing whether the operation succeeded.
   function Unregister_Function
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result;

   --  Return exists for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Exists (Name : Wide_Wide_String) return Boolean;

   --  Return metadata of for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Metadata metadata argument supplied to the operation.
   --  @return Result produced by the function.
   function Metadata_Of
     (Name     : Wide_Wide_String;
      Metadata : out Function_Metadata) return Database.Status.Result;

   --  Return evaluate for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Arguments arguments argument supplied to the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Evaluate
     (Name      : Wide_Wide_String;
      Arguments : Database.Values.Value_Vector;
      Value     : out Database.Values.Value) return Database.Status.Result;

   --  Return validate persistent use for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Persistent_Use (Name : Wide_Wide_String) return Database.Status.Result;

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
end Database.Functions;
