--  Ada-native deterministic text collation registry.
with Database.Extension_Metadata;
with Database.Status;

--  Custom collation registry support.
package Database.Collations is
   --  Collation_Function defines a public database type used by this package.
   type Collation_Function is access function (Left, Right : Wide_Wide_String) return Integer;
   --  Collation_Metadata stores the public fields for this database abstraction.
   type Collation_Metadata is record
      Name : Unbounded_Wide_Wide_String;
      Extension_Name : Unbounded_Wide_Wide_String;
      Version : Natural := 1;
      Compatibility_Id : Unbounded_Wide_Wide_String;
      Deterministic : Boolean := True;
      Index_Compatible : Boolean := True;
   end record;
   --  Return register collation for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Metadata metadata argument supplied to the operation.
   --  @param Fn fn argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Register_Collation
     (DB : in out Database.Handle;
      Metadata : Collation_Metadata;
      Fn : Collation_Function) return Database.Status.Result;
   --  Return compare for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Compare
     (State_Key : Natural;
      Name, Left, Right : Wide_Wide_String;
      Result : out Integer) return Database.Status.Result;
   --  Return exists for the supplied database state or arguments.
   --  @param State_Key handle-owned state key selecting the callable registry.
   --  @param Name logical name of the object.
   --  @return Result produced by the function.
   function Exists (State_Key : Natural; Name : Wide_Wide_String) return Boolean;
   --  Return validate index use for the supplied database state or arguments.
   --  @param State_Key handle-owned state key selecting the callable registry.
   --  @param Name logical name of the object.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Index_Use
     (State_Key : Natural; Name : Wide_Wide_String) return Database.Status.Result;
   --  Return registered metadata for the supplied database state or arguments.
   --  @param State_Key handle-owned state key selecting the callable registry.
   --  @return Status result describing whether the operation succeeded.
   function Registered_Metadata
     (State_Key : Natural)
      return Database.Extension_Metadata.Metadata_Vectors.Vector;

   --  Drops all transient callable registrations owned by one database handle.
   --  @param State_Key state key argument supplied to the operation.
   procedure Drop_Database (State_Key : Natural);

   --  Perform clear for the supplied database state or arguments.
   --  @param State_Key handle-owned state key selecting the callable registry.
   procedure Clear (State_Key : Natural);
end Database.Collations;
