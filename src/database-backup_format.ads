--  Backup manifest and checksum helpers for physical backup and restore.
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;
with Database.Log_Sequence;

--  Backup manifest and artifact format helpers.
package Database.Backup_Format is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Backup_Format_Version is a public constant used by this package.
   Backup_Format_Version : constant Natural := 1;

   --  Manifest stores the public fields for this database abstraction.
   type Manifest is record
      Database_Format_Version : Natural := 1;
      Backup_Format_Version   : Natural := 1;
      Source_Database_Id      : Unbounded_Wide_Wide_String;
      Created_At              : Unbounded_Wide_Wide_String;
      Page_Size               : Natural := 0;
      Page_Count              : Natural := 0;
      Checkpoint_LSN          : Database.Log_Sequence.Log_Sequence_Number := 0;
      Backup_Target_LSN       : Database.Log_Sequence.Log_Sequence_Number := 0;
      WAL_Start_LSN           : Database.Log_Sequence.Log_Sequence_Number := 0;
      WAL_End_LSN             : Database.Log_Sequence.Log_Sequence_Number := 0;
      Database_Checksum       : Natural := 0;
      WAL_Checksum            : Natural := 0;
      Catalog_Checksum        : Natural := 0;
      Encrypted_Page_Count    : Natural := 0;
      Encrypted_Page_Checksum : Natural := 0;
      Encrypted_WAL_Checksum  : Natural := 0;
   end record;

   --  Return manifest path for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @return Result produced by the function.
   function Manifest_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String;
   --  Return database image path for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @return Result produced by the function.
   function Database_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String;
   --  Return wal image path for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @return Result produced by the function.
   function WAL_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String;
   --  Return encrypted page image path for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @param Page page argument supplied to the operation.
   --  @return Result produced by the function.
   function Encrypted_Page_Image_Path
     (Backup_Path : Wide_Wide_String;
      Page         : Natural) return Wide_Wide_String;
   --  Return encrypted manifest image path for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @return Result produced by the function.
   function Encrypted_Manifest_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String;
   --  Return encrypted wal image path for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @return Result produced by the function.
   function Encrypted_WAL_Image_Path (Backup_Path : Wide_Wide_String) return Wide_Wide_String;

   --  Return compute file checksum for the supplied database state or arguments.
   --  @param Path filesystem path or artifact location used by the operation.
   --  @return Computed checksum or checksum-verification result.
   function Compute_File_Checksum (Path : Wide_Wide_String) return Natural;

   --  Return a deterministic checksum over the complete encrypted page sidecar
   --  set described by Page_Count. Missing sidecars contribute zero and will be
   --  rejected by Validate_Manifest when encrypted sidecars are expected.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @param Page_Count page count argument supplied to the operation.
   --  @return Computed checksum or checksum-verification result.
   function Compute_Encrypted_Page_Sidecar_Checksum
     (Backup_Path : Wide_Wide_String;
      Page_Count  : Natural) return Natural;

   --  Return write manifest for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @param Item item argument supplied to the operation.
   --  @return Result produced by the function.
   function Write_Manifest
     (Backup_Path : Wide_Wide_String;
      Item        : Manifest) return Database.Status.Result;

   --  Return read manifest for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @param Item item argument supplied to the operation.
   --  @return Result produced by the function.
   function Read_Manifest
     (Backup_Path : Wide_Wide_String;
      Item        : out Manifest) return Database.Status.Result;

   --  Return validate manifest for the supplied database state or arguments.
   --  @param Backup_Path backup path argument supplied to the operation.
   --  @param Item item argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Manifest
     (Backup_Path : Wide_Wide_String;
      Item        : Manifest) return Database.Status.Result;
end Database.Backup_Format;
