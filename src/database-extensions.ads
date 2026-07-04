--  Ada-native extension registration and persistent dependency validation.
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Status;

--  Extension registry and dependency metadata.
package Database.Extensions is
   --  Perform select database for the supplied database state or arguments.
   --  @param State_Key state key argument supplied to the operation.
   procedure Select_Database (State_Key : Natural);
   --  Perform drop database for the supplied database state or arguments.
   --  @param State_Key state key argument supplied to the operation.
   procedure Drop_Database (State_Key : Natural);
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Extension_Definition stores the public fields for this database abstraction.
   type Extension_Definition is record
      Name             : Unbounded_Wide_Wide_String;
      Version          : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Required         : Boolean := True;
      Metadata         : Database.Extension_Metadata.Metadata_Vectors.Vector;
   end record;

   --  Extension_Vectors stores ordered extension values for this package.
   package Extension_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Extension_Definition);

   --  Return register extension for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Extension extension argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Extension
     (DB        : in out Database.Handle;
      Extension : Extension_Definition) return Database.Status.Result;

   --  Return unregister extension for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Name logical name of the object.
   --  @return Status result describing whether the operation succeeded.
   function Unregister_Extension
     (DB   : in out Database.Handle;
      Name : Wide_Wide_String) return Database.Status.Result;

   --  Return add dependency for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Dependency dependency argument supplied to the operation.
   --  @return Result produced by the function.
   function Add_Dependency
     (DB         : in out Database.Handle;
      Dependency : Database.Extension_Metadata.Dependency) return Database.Status.Result;

   --  Return validate dependencies for the supplied database state or arguments.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Dependencies return Database.Status.Result;
   --  Return registered extensions for the supplied database state or arguments.
   --  @return Status result describing whether the operation succeeded.
   function Registered_Extensions return Extension_Vectors.Vector;
   --  Return dependencies for the supplied database state or arguments.
   --  @return Result produced by the function.
   function Dependencies return Database.Extension_Metadata.Dependency_Vectors.Vector;

   --  Return save for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Save (Path : Wide_Wide_String) return Database.Status.Result;
   --  Return load for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Load (Path : Wide_Wide_String) return Database.Status.Result;

   --  Perform clear for the supplied database state or arguments.
   procedure Clear;
end Database.Extensions;
