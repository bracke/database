--  Top-level encryption coordinator for local embedded storage protection.
with Database.Status;
with Database.Keys;

--  Encrypted persistence configuration and operations.
package Database.Encryption is
   --  Encryption_Mode enumerates the supported values for this database abstraction.
   type Encryption_Mode is (No_Encryption, Encrypted);
   --  Encryption_Config stores the public fields for this database abstraction.
   type Encryption_Config is record
      Mode : Encryption_Mode := No_Encryption;
      Key  : Database.Keys.Encryption_Key := Database.Keys.Empty_Key;
   end record;

   --  Encryption_Metadata stores the public fields for this database abstraction.
   type Encryption_Metadata is record
      Mode           : Encryption_Mode := No_Encryption;
      Format_Version : Natural := 1;
      Key_Id         : Database.Keys.Key_Id := 0;
      WAL_Encrypted  : Boolean := False;
   end record;

   --  Return enable encryption for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Config configuration values controlling the operation.
   --  @return Result produced by the function.
   function Enable_Encryption
     (DB     : in out Database.Handle;
      Config : Encryption_Config) return Database.Status.Result;

   --  Return disable encryption for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Disable_Encryption
     (DB : in out Database.Handle) return Database.Status.Result;

   --  Return rotate key for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param New_Key new key argument supplied to the operation.
   --  @return Result produced by the function.
   function Rotate_Key
     (DB      : in out Database.Handle;
      New_Key : Database.Keys.Encryption_Key) return Database.Status.Result;

   --  Return metadata for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @return Result produced by the function.
   function Metadata (DB : Database.Handle) return Encryption_Metadata;
end Database.Encryption;
