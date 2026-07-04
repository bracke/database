--  Ada-native row and schema validation hooks registered by extensions.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Extension_Metadata;
with Database.Rows;
with Database.Schema;
with Database.Status;

--  Public specification for this database subsystem.
package Database.Validation_Hooks is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Validation_Hook defines a public database type used by this package.
   type Validation_Hook is access function
     (Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Database.Status.Result;

   --  Validation_Metadata stores the public fields for this database abstraction.
   type Validation_Metadata is record
      Name             : Unbounded_Wide_Wide_String;
      Extension_Name   : Unbounded_Wide_Wide_String;
      Version          : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Deterministic    : Boolean := True;
   end record;

   --  Return register validation hook for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Hook hook argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Validation_Hook
     (DB       : in out Database.Handle;
      Metadata : Validation_Metadata;
      Hook     : Validation_Hook) return Database.Status.Result;

   --  Return validate for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate
     (Name   : Wide_Wide_String;
      Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row) return Database.Status.Result;

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
end Database.Validation_Hooks;
