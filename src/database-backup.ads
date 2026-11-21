--  Online physical backup support.
with Database.Status;
with Database.Keys;

--  Physical backup creation and validation.
package Database.Backup is
   --  How a physical backup is made. A backup holds the write lock while it runs, so it is refused beside an active
   --  writer while readers may continue.
   type Backup_Options is record
      --  Copy the WAL beside the database file, so a restore can recover what the WAL still has to undo.
      Include_WAL       : Boolean := True;
      --  Validate the copied images against the manifest after writing it.
      Verify_After_Copy : Boolean := True;
      --  Checkpoint before copying, so the database image alone is complete. Recommended when Include_WAL is
      --  False: without it, an image taken after a failed rollback still holds the pages the WAL would undo.
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
