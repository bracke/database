--  Physical backup restore support.
with Database.Status;
with Database.Keys;

--  Restore operations for physical backups.
package Database.Restore is
   --  Restore_Options stores the public fields for this database abstraction.
   type Restore_Options is record
      Overwrite : Boolean := False;
      Verify    : Boolean := True;
   end record;

   --  Return restore physical backup for the supplied database state or arguments.
   --  @param Source filesystem path or artifact location used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @return Result produced by the function.
   function Restore_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String) return Database.Status.Result;

   --  Return restore physical backup for the supplied database state or arguments.
   --  @param Source filesystem path or artifact location used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Restore_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String;
      Options     : Restore_Options) return Database.Status.Result;

   --  Return restore encrypted physical backup for the supplied database state or arguments.
   --  @param Source filesystem path or artifact location used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Key key value used to identify the row or object.
   --  @return Result produced by the function.
   function Restore_Encrypted_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key) return Database.Status.Result;

   --  Return restore encrypted physical backup for the supplied database state or arguments.
   --  @param Source filesystem path or artifact location used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Options configuration values controlling the operation.
   --  @return Result produced by the function.
   function Restore_Encrypted_Physical_Backup
     (Source      : Wide_Wide_String;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key;
      Options     : Restore_Options) return Database.Status.Result;
end Database.Restore;
