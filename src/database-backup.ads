--  Online physical backup support.
with Database.Status;
with Database.Keys;

--  Physical backup creation and validation.
package Database.Backup is
   --  Backup_Options stores the public fields for this database abstraction.
   type Backup_Options is record
      Include_WAL       : Boolean := True;
      Verify_After_Copy : Boolean := True;
      Force_Checkpoint  : Boolean := False;
   end record;

   --  Return create physical backup for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String) return Database.Status.Result;

   --  Return create physical backup for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Options configuration values controlling the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Options     : Backup_Options) return Database.Status.Result;

   --  Create an authenticated encrypted physical backup. Page images are not
   --  copied as plaintext;
   --  each restored page is persisted as an encrypted
   --  backup artifact and verified during restore.
   --  @param DB database handle used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Key key value used to identify the row or object.
   --  @return Status result describing whether the operation succeeded.
   function Create_Encrypted_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key) return Database.Status.Result;

   --  Return create encrypted physical backup for the supplied database state or arguments.
   --  @param DB database handle used by the operation.
   --  @param Destination filesystem path or artifact location used by the operation.
   --  @param Key key value used to identify the row or object.
   --  @param Options configuration values controlling the operation.
   --  @return Status result describing whether the operation succeeded.
   function Create_Encrypted_Physical_Backup
     (DB          : in out Database.Handle;
      Destination : Wide_Wide_String;
      Key         : Database.Keys.Encryption_Key;
      Options     : Backup_Options) return Database.Status.Result;
end Database.Backup;
