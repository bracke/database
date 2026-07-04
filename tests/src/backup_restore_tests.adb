with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Text_IO;
with AUnit.Assertions;
with Database;
with Database.Backup;
with Database.Backup_Format;
with Database.Export;
with Database.Import;
with Database.Keys;
with Database.Encrypted_Persistence;
with Database.Restore;
with Database.Rows;
with Database.Schema;
with Database.Storage.Pages;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body Backup_Restore_Tests is
   use AUnit.Assertions;

   type User_Row is record
      Id   : Integer;
      Name : Wide_Wide_String (1 .. 16);
      Age  : Integer;
   end record;

   function To_Row (U : User_Row) return Database.Rows.Row is
      R : Database.Rows.Row;
   begin
      Database.Rows.Append (R, Database.Values.From_Integer (U.Id));
      Database.Rows.Append (R, Database.Values.From_Text (U.Name));
      Database.Rows.Append (R, Database.Values.From_Integer (U.Age));
      return R;
   end To_Row;

   function From_Row (R : Database.Rows.Row) return User_Row is
      use Ada.Strings.Wide_Wide_Unbounded;
      S : constant Wide_Wide_String :=
        To_Wide_Wide_String (Database.Rows.Get (R, 1).Text);
      U : User_Row :=
        (Id   => Database.Rows.Get (R, 0).Int,
         Name => (others => ' '),
         Age  => Database.Rows.Get (R, 2).Int);
   begin
      for I in 1 .. Integer'Min (16, S'Length) loop
         U.Name (I) := S (S'First + I - 1);
      end loop;
      return U;
   end From_Row;

   function Key_Of (U : User_Row) return Integer
   is (U.Id);
   function Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   package Users is new
     Database.Tables.Typed
       (User_Row,
        Integer,
        To_Row,
        From_Row,
        Key_Of,
        Key_Value);

   function Row_Identity (R : Database.Rows.Row) return Database.Rows.Row
   is (R);
   function Row_Key_Of (R : Database.Rows.Row) return Integer
   is (Database.Rows.Get (R, 0).Int);
   function Row_Key_Value (K : Integer) return Database.Values.Value
   is (Database.Values.From_Integer (K));

   package Raw_Rows is new
     Database.Tables.Typed
       (Database.Rows.Row,
        Integer,
        Row_Identity,
        Row_Identity,
        Row_Key_Of,
        Row_Key_Value);

   function Exact_Value_Schema return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("exact_values");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "txt", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "dec", Database.Types.Decimal_Value, False);
      Database.Schema.Add_Column (S, "blob", Database.Types.Blob_Value, False);
      return S;
   end Exact_Value_Schema;

   function Exact_Value_Row return Database.Rows.Row is
      R : Database.Rows.Row;
      B : Database.Values.Byte_Vectors.Vector;
   begin
      B.Append (0);
      B.Append (1);
      B.Append (16#FE#);
      B.Append (16#FF#);
      Database.Rows.Append (R, Database.Values.From_Integer (77));
      Database.Rows.Append (R, Database.Values.From_Text ("Grüße 🌍 日本"));
      Database.Rows.Append
        (R,
         Database.Values.From_Decimal
           ((Coefficient => -1234567890123, Scale => 5)));
      Database.Rows.Append (R, Database.Values.From_Blob (B));
      return R;
   end Exact_Value_Row;

   function User_Schema return Database.Schema.Table_Schema is
      S : Database.Schema.Table_Schema;
   begin
      S.Name :=
        Ada.Strings.Wide_Wide_Unbounded.To_Unbounded_Wide_Wide_String
          ("users");
      Database.Schema.Add_Column
        (S, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (S, "name", Database.Types.Text_Value, False);
      Database.Schema.Add_Column
        (S, "age", Database.Types.Integer_Value, False);
      return S;
   end User_Schema;

   overriding
   function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("backup, restore, export, import");
   end Name;

   procedure Remove_File (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_File;

   procedure Remove_Tree (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Tree (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_Tree;

   procedure Physical_Backup_And_Restore
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Restored : Database.Handle;
      R        : Database.Status.Result;
   begin
      Remove_File ("backup_source.database");
      Remove_File ("backup_restored.database");
      Remove_Tree ("backup_restore.backup");

      Database.Create (DB, "backup_source.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      R := Database.Backup.Create_Physical_Backup (DB, "backup_restore.backup");
      Assert (Database.Status.Is_Ok (R), "physical backup failed");
      Assert
        (Ada.Directories.Exists ("backup_restore.backup/manifest.dbbackup"),
         "manifest not written");
      Assert
        (Ada.Directories.Exists ("backup_restore.backup/database.image"),
         "database image not written");
      R :=
        Database.Restore.Restore_Physical_Backup
          ("backup_restore.backup", "backup_restored.database");
      Assert (Database.Status.Is_Ok (R), "restore failed");
      Database.Open (Restored, "backup_restored.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Restored)),
         "restored database did not open");
      Database.Close (Restored);
      Database.Close (DB);
      Remove_File ("backup_source.database");
      Remove_File ("backup_restored.database");
      Remove_Tree ("backup_restore.backup");
   end Physical_Backup_And_Restore;

   procedure Physical_Backup_Preserves_Rows_And_Indexes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Restored : Database.Handle;
      Tx       : Database.Transactions.Transaction;
      Read_Tx  : Database.Transactions.Transaction;
      S        : Database.Schema.Table_Schema := User_Schema;
      R        : Database.Status.Result;
      Out_User : User_Row;
   begin
      Remove_File ("backup_rows.database");
      Remove_File ("backup_rows_restored.database");
      Remove_Tree ("backup_rows.backup");

      Database.Create (DB, "backup_rows.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Users.Insert
          (Tx, DB, S, (Id => 7, Name => "Ada Backup      ", Age => 45));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R := Database.Transactions.Commit (Tx);
      Assert (Database.Status.Is_Ok (R), "commit failed");

      R := Database.Backup.Create_Physical_Backup (DB, "backup_rows.backup");
      Assert (Database.Status.Is_Ok (R), "physical backup failed");
      R :=
        Database.Restore.Restore_Physical_Backup
          ("backup_rows.backup", "backup_rows_restored.database");
      Assert (Database.Status.Is_Ok (R), "restore failed");

      Database.Open (Restored, "backup_rows_restored.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Restored)),
         "open restored failed");
      Database.Transactions.Begin_Read (Restored, Read_Tx);
      R := Users.Find (Read_Tx, Restored, S, 7, Out_User);
      Assert (Database.Status.Is_Ok (R), "restored indexed find failed");
      Assert (Out_User.Age = 45, "restored row payload mismatch");
      R := Database.Transactions.Commit (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");

      Database.Close (Restored);
      Database.Close (DB);
      Remove_File ("backup_rows.database");
      Remove_File ("backup_rows_restored.database");
      Remove_Tree ("backup_rows.backup");
   end Physical_Backup_Preserves_Rows_And_Indexes;

   procedure Backup_Rejects_Corrupt_Manifest
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      M  : Database.Backup_Format.Manifest;
      R  : Database.Status.Result;
   begin
      Remove_File ("backup_corrupt.database");
      Remove_Tree ("backup_corrupt.backup");
      Database.Create (DB, "backup_corrupt.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      R :=
        Database.Backup.Create_Physical_Backup (DB, "backup_corrupt.backup");
      Assert (Database.Status.Is_Ok (R), "backup failed");
      R := Database.Backup_Format.Read_Manifest ("backup_corrupt.backup", M);
      Assert (Database.Status.Is_Ok (R), "manifest read failed");
      M.Database_Checksum := M.Database_Checksum + 1;
      R :=
        Database.Backup_Format.Validate_Manifest ("backup_corrupt.backup", M);
      Assert (not Database.Status.Is_Ok (R), "corrupt manifest accepted");
      Database.Close (DB);
      Remove_File ("backup_corrupt.database");
      Remove_Tree ("backup_corrupt.backup");
   end Backup_Rejects_Corrupt_Manifest;

   procedure Physical_Backup_Rejects_Active_Writer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
      S  : Database.Schema.Table_Schema := User_Schema;
      R  : Database.Status.Result;
   begin
      Remove_File ("backup_writer.database");
      Remove_Tree ("backup_writer.backup");
      Database.Create (DB, "backup_writer.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)), "create failed");
      R := Users.Register (DB, S);
      Assert (Database.Status.Is_Ok (R), "register failed");
      Database.Transactions.Begin_Write (DB, Tx);
      R :=
        Users.Insert
          (Tx, DB, S, (Id => 11, Name => "Uncommitted     ", Age => 1));
      Assert (Database.Status.Is_Ok (R), "insert failed");
      R :=
        Database.Backup.Create_Physical_Backup (DB, "backup_writer.backup");
      Assert (not Database.Status.Is_Ok (R), "backup accepted active writer");
      R := Database.Transactions.Rollback (Tx);
      Assert (Database.Status.Is_Ok (R), "rollback failed");
      Database.Close (DB);
      Remove_File ("backup_writer.database");
      Remove_Tree ("backup_writer.backup");
   end Physical_Backup_Rejects_Active_Writer;

   procedure Logical_Export_And_Import
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source_DB : Database.Handle;
      Target_DB : Database.Handle;
      Read_Tx   : Database.Transactions.Transaction;
      Write_Tx  : Database.Transactions.Transaction;
      Verify_Tx : Database.Transactions.Transaction;
      S         : Database.Schema.Table_Schema := User_Schema;
      Imported  : User_Row;
      R         : Database.Status.Result;
   begin
      Remove_File ("export_import_source.database");
      Remove_File ("export_import_target.database");
      Remove_File ("export_import.native_export");
      Database.Create (Source_DB, "export_import_source.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Source_DB)),
         "source create failed");
      R := Users.Register (Source_DB, S);
      Assert (Database.Status.Is_Ok (R), "source register failed");
      Database.Transactions.Begin_Write (Source_DB, Write_Tx);
      R :=
        Users.Insert
          (Write_Tx,
           Source_DB,
           S,
           (Id => 12, Name => "Exported Row    ", Age => 99));
      Assert (Database.Status.Is_Ok (R), "source insert failed");
      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "source commit failed");

      Database.Transactions.Begin_Read (Source_DB, Read_Tx);
      R := Database.Export.Export_Database (Read_Tx, "export_import.native_export");
      Assert (Database.Status.Is_Ok (R), "logical export failed");
      R := Database.Transactions.Commit (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");

      Database.Create (Target_DB, "export_import_target.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Target_DB)),
         "target create failed");
      Database.Transactions.Begin_Write (Target_DB, Write_Tx);
      R := Database.Import.Import_Database (Write_Tx, "export_import.native_export");
      Assert (Database.Status.Is_Ok (R), "logical import failed");
      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "write commit failed");

      Database.Transactions.Begin_Read (Target_DB, Verify_Tx);
      R := Users.Find (Verify_Tx, Target_DB, S, 12, Imported);
      Assert (Database.Status.Is_Ok (R), "imported row not found");
      Assert (Imported.Age = 99, "imported row payload mismatch");
      R := Database.Transactions.Commit (Verify_Tx);
      Assert (Database.Status.Is_Ok (R), "verify commit failed");

      Database.Close (Target_DB);
      Database.Close (Source_DB);
      Remove_File ("export_import_source.database");
      Remove_File ("export_import_target.database");
      Remove_File ("export_import.native_export");
   end Logical_Export_And_Import;

   procedure Write_Legacy_Empty_Logical_Export (Path : String) is
      F : Ada.Streams.Stream_IO.File_Type;

      procedure Write_Byte (B : Natural) is
         S : Ada.Streams.Stream_Element_Array (1 .. 1);
      begin
         S (1) := Ada.Streams.Stream_Element (B mod 256);
         Ada.Streams.Stream_IO.Write (F, S);
      end Write_Byte;

      procedure Write_U32 (V : Natural) is
      begin
         Write_Byte ((V / 16#1000000#) mod 256);
         Write_Byte ((V / 16#10000#) mod 256);
         Write_Byte ((V / 16#100#) mod 256);
         Write_Byte (V mod 256);
      end Write_U32;

      procedure Write_Text (S : Wide_Wide_String) is
      begin
         Write_U32 (S'Length);
         for Ch of S loop
            Write_U32 (Wide_Wide_Character'Pos (Ch));
         end loop;
      end Write_Text;
   begin
      Ada.Streams.Stream_IO.Create (F, Ada.Streams.Stream_IO.Out_File, Path);
      Write_Text ("DATABASE_LOGICAL_EXPORT_26");
      Write_U32 (26);
      Write_U32 (0);
      Write_Text ("PHASE18_METADATA_V1");
      Write_U32 (0);
      Write_U32 (0);
      Write_U32 (0);
      Write_U32 (0);
      Write_U32 (0);
      Ada.Streams.Stream_IO.Close (F);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         raise;
   end Write_Legacy_Empty_Logical_Export;

   procedure Logical_Import_Accepts_Legacy_Metadata_Marker
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Target_DB : Database.Handle;
      Write_Tx  : Database.Transactions.Transaction;
      R         : Database.Status.Result;
   begin
      Remove_File ("export_legacy_marker_target.database");
      Remove_File ("export_legacy_marker.native_export");
      Write_Legacy_Empty_Logical_Export ("export_legacy_marker.native_export");

      Database.Create (Target_DB, "export_legacy_marker_target.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Target_DB)),
         "legacy marker target create failed");
      Database.Transactions.Begin_Write (Target_DB, Write_Tx);
      R :=
        Database.Import.Import_Database
          (Write_Tx, "export_legacy_marker.native_export");
      Assert (Database.Status.Is_Ok (R), "legacy metadata marker rejected");
      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "legacy marker import commit failed");

      Database.Close (Target_DB);
      Remove_File ("export_legacy_marker_target.database");
      Remove_File ("export_legacy_marker.native_export");
   end Logical_Import_Accepts_Legacy_Metadata_Marker;

   procedure Logical_Export_Import_Preserves_Exact_Values
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source_DB : Database.Handle;
      Target_DB : Database.Handle;
      Read_Tx   : Database.Transactions.Transaction;
      Write_Tx  : Database.Transactions.Transaction;
      Verify_Tx : Database.Transactions.Transaction;
      S         : Database.Schema.Table_Schema := Exact_Value_Schema;
      Imported  : Database.Rows.Row;
      Original  : constant Database.Rows.Row := Exact_Value_Row;
      R         : Database.Status.Result;
   begin
      Remove_File ("export_exact_source.database");
      Remove_File ("export_exact_target.database");
      Remove_File ("export_exact.native_export");

      Database.Create (Source_DB, "export_exact_source.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Source_DB)),
         "source create failed");
      R := Raw_Rows.Register (Source_DB, S);
      Assert (Database.Status.Is_Ok (R), "source register failed");
      Database.Transactions.Begin_Write (Source_DB, Write_Tx);
      R := Raw_Rows.Insert (Write_Tx, Source_DB, S, Original);
      Assert (Database.Status.Is_Ok (R), "source insert failed");
      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "source commit failed");

      Database.Transactions.Begin_Read (Source_DB, Read_Tx);
      R :=
        Database.Export.Export_Database
          (Read_Tx, "export_exact.native_export");
      Assert (Database.Status.Is_Ok (R), "logical export failed");
      R := Database.Transactions.Commit (Read_Tx);
      Assert (Database.Status.Is_Ok (R), "read commit failed");

      Database.Create (Target_DB, "export_exact_target.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Target_DB)),
         "target create failed");
      Database.Transactions.Begin_Write (Target_DB, Write_Tx);
      R :=
        Database.Import.Import_Database
          (Write_Tx, "export_exact.native_export");
      Assert (Database.Status.Is_Ok (R), "logical import failed");
      R := Database.Transactions.Commit (Write_Tx);
      Assert (Database.Status.Is_Ok (R), "write commit failed");

      Database.Transactions.Begin_Read (Target_DB, Verify_Tx);
      R := Raw_Rows.Find (Verify_Tx, Target_DB, S, 77, Imported);
      Assert (Database.Status.Is_Ok (R), "imported exact row not found");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Imported, 1), Database.Rows.Get (Original, 1)),
         "Unicode text did not round trip exactly");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Imported, 2), Database.Rows.Get (Original, 2)),
         "Decimal did not round trip exactly");
      Assert
        (Database.Values.Equal
           (Database.Rows.Get (Imported, 3), Database.Rows.Get (Original, 3)),
         "Blob did not round trip exactly");
      R := Database.Transactions.Commit (Verify_Tx);
      Assert (Database.Status.Is_Ok (R), "verify commit failed");

      Database.Close (Target_DB);
      Database.Close (Source_DB);
      Remove_File ("export_exact_source.database");
      Remove_File ("export_exact_target.database");
      Remove_File ("export_exact.native_export");
   end Logical_Export_Import_Preserves_Exact_Values;

   procedure Logical_Import_Rejects_Invalid_Export
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Target_DB : Database.Handle;
      Tx        : Database.Transactions.Transaction;
      F         : Ada.Text_IO.File_Type;
      R         : Database.Status.Result;
   begin
      Remove_File ("export_invalid_target.database");
      Remove_File ("export_invalid.native_export");

      Ada.Text_IO.Create
        (F, Ada.Text_IO.Out_File, "export_invalid.native_export");
      Ada.Text_IO.Put_Line (F, "not a database logical export");
      Ada.Text_IO.Close (F);

      Database.Create (Target_DB, "export_invalid_target.database");
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Target_DB)),
         "target create failed");
      Database.Transactions.Begin_Write (Target_DB, Tx);
      R :=
        Database.Import.Import_Database (Tx, "export_invalid.native_export");
      Assert
        (not Database.Status.Is_Ok (R), "invalid logical export accepted");
      R := Database.Transactions.Rollback (Tx);
      Assert
        (Database.Status.Is_Ok (R), "rollback after invalid import failed");

      Database.Close (Target_DB);
      Remove_File ("export_invalid_target.database");
      Remove_File ("export_invalid.native_export");
   end Logical_Import_Rejects_Invalid_Export;

   function Test_Key return Database.Keys.Encryption_Key is
      Bytes : Database.Keys.Binary_Key := (others => 0);
   begin
      for I in Bytes'Range loop
         Bytes (I) := Database.Storage.Pages.Byte ((I * 13 + 7) mod 251);
      end loop;
      return Database.Keys.From_Binary_Key (Bytes, 77);
   end Test_Key;

   function Alternate_Test_Key return Database.Keys.Encryption_Key is
      Bytes : Database.Keys.Binary_Key := (others => 0);
   begin
      for I in Bytes'Range loop
         Bytes (I) := Database.Storage.Pages.Byte ((I * 17 + 3) mod 251);
      end loop;
      return Database.Keys.From_Binary_Key (Bytes, 78);
   end Alternate_Test_Key;

   procedure Encrypted_Physical_Backup_And_Restore
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB       : Database.Handle;
      Restored : Database.Handle;
      Key      : constant Database.Keys.Encryption_Key := Test_Key;
      R        : Database.Status.Result;
   begin
      Remove_File ("encrypted_backup.database");
      Remove_File ("encrypted_backup_restored.database");
      Remove_Tree ("encrypted_backup.backup");

      Database.Create_Encrypted (DB, "encrypted_backup.database", Key);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "encrypted create failed");
      R :=
        Database.Backup.Create_Encrypted_Physical_Backup
          (DB, "encrypted_backup.backup", Key);
      Assert (Database.Status.Is_Ok (R), "encrypted physical backup failed");
      Assert
        (Ada.Directories.Exists ("encrypted_backup.backup/manifest.dbbackup.enc"),
         "encrypted manifest missing");
      Assert
        (Ada.Directories.Exists
           ("encrypted_backup.backup/database.page0.backup.enc"),
         "encrypted page image missing");
      R :=
        Database.Restore.Restore_Encrypted_Physical_Backup
          ("encrypted_backup.backup", "encrypted_backup_restored.database", Key);
      Assert (Database.Status.Is_Ok (R), "encrypted restore failed");
      Database.Open_Encrypted (Restored, "encrypted_backup_restored.database", Key);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (Restored)),
         "encrypted restored database did not open");
      Database.Close (Restored);
      Database.Close (DB);
      Remove_File ("encrypted_backup.database");
      Remove_File ("encrypted_backup_restored.database");
      Remove_Tree ("encrypted_backup.backup");
   end Encrypted_Physical_Backup_And_Restore;

   procedure Encrypted_Physical_Backup_Rejects_Tampered_Page
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB  : Database.Handle;
      Key : constant Database.Keys.Encryption_Key := Test_Key;
      R   : Database.Status.Result;
   begin
      Remove_File ("encrypted_backup_tamper.database");
      Remove_File ("encrypted_backup_tamper_restored.database");
      Remove_Tree ("encrypted_backup_tamper.backup");
      Database.Create_Encrypted (DB, "encrypted_backup_tamper.database", Key);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "encrypted create failed");
      R :=
        Database.Backup.Create_Encrypted_Physical_Backup
          (DB, "encrypted_backup_tamper.backup", Key);
      Assert (Database.Status.Is_Ok (R), "encrypted backup failed");
      R :=
        Database.Encrypted_Persistence.Tamper_Byte
          ("encrypted_backup_tamper.backup/database.page0.backup.enc", 120);
      Assert (Database.Status.Is_Ok (R), "tamper setup failed");
      R :=
        Database.Restore.Restore_Encrypted_Physical_Backup
          ("encrypted_backup_tamper.backup",
           "encrypted_backup_tamper_restored.database",
           Key);
      Assert
        (not Database.Status.Is_Ok (R),
         "tampered encrypted backup page accepted");
      Database.Close (DB);
      Remove_File ("encrypted_backup_tamper.database");
      Remove_File ("encrypted_backup_tamper_restored.database");
      Remove_Tree ("encrypted_backup_tamper.backup");
   end Encrypted_Physical_Backup_Rejects_Tampered_Page;

   procedure Encrypted_Physical_Backup_Rejects_Missing_Page_Sidecar
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB  : Database.Handle;
      Key : constant Database.Keys.Encryption_Key := Test_Key;
      R   : Database.Status.Result;
   begin
      Remove_File ("encrypted_backup_missing_sidecar.database");
      Remove_File ("encrypted_backup_missing_sidecar_restored.database");
      Remove_Tree ("encrypted_backup_missing_sidecar.backup");
      Database.Create_Encrypted
        (DB, "encrypted_backup_missing_sidecar.database", Key);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "encrypted create failed");
      R :=
        Database.Backup.Create_Encrypted_Physical_Backup
          (DB, "encrypted_backup_missing_sidecar.backup", Key);
      Assert (Database.Status.Is_Ok (R), "encrypted backup failed");
      Ada.Directories.Delete_File
        ("encrypted_backup_missing_sidecar.backup/database.page0.backup.enc");
      R :=
        Database.Restore.Restore_Encrypted_Physical_Backup
          ("encrypted_backup_missing_sidecar.backup",
           "encrypted_backup_missing_sidecar_restored.database",
           Key);
      Assert
        (not Database.Status.Is_Ok (R),
         "encrypted backup accepted missing page sidecar");
      Database.Close (DB);
      Remove_File ("encrypted_backup_missing_sidecar.database");
      Remove_File ("encrypted_backup_missing_sidecar_restored.database");
      Remove_Tree ("encrypted_backup_missing_sidecar.backup");
   end Encrypted_Physical_Backup_Rejects_Missing_Page_Sidecar;

   procedure Encrypted_Physical_Backup_Rejects_Wrong_Key
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      DB        : Database.Handle;
      Key       : constant Database.Keys.Encryption_Key := Test_Key;
      Wrong_Key : constant Database.Keys.Encryption_Key := Alternate_Test_Key;
      R         : Database.Status.Result;
   begin
      Remove_File ("encrypted_backup_wrong_key.database");
      Remove_File ("encrypted_backup_wrong_key_restored.database");
      Remove_Tree ("encrypted_backup_wrong_key.backup");
      Database.Create_Encrypted (DB, "encrypted_backup_wrong_key.database", Key);
      Assert
        (Database.Status.Is_Ok (Database.Last_Result (DB)),
         "encrypted create failed");
      R :=
        Database.Backup.Create_Encrypted_Physical_Backup
          (DB, "encrypted_backup_wrong_key.backup", Key);
      Assert (Database.Status.Is_Ok (R), "encrypted backup failed");
      R :=
        Database.Restore.Restore_Encrypted_Physical_Backup
          ("encrypted_backup_wrong_key.backup",
           "encrypted_backup_wrong_key_restored.database",
           Wrong_Key);
      Assert
        (not Database.Status.Is_Ok (R),
         "encrypted backup accepted wrong restore key");
      Database.Close (DB);
      Remove_File ("encrypted_backup_wrong_key.database");
      Remove_File ("encrypted_backup_wrong_key_restored.database");
      Remove_Tree ("encrypted_backup_wrong_key.backup");
   end Encrypted_Physical_Backup_Rejects_Wrong_Key;

   overriding
   procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Physical_Backup_And_Restore'Access,
         "physical backup and restore create an openable database");
      Register_Routine
        (T,
         Physical_Backup_Preserves_Rows_And_Indexes'Access,
         "physical backup preserves table rows and indexed find");
      Register_Routine
        (T,
         Backup_Rejects_Corrupt_Manifest'Access,
         "corrupt physical backup manifest is rejected");
      Register_Routine
        (T,
         Physical_Backup_Rejects_Active_Writer'Access,
         "physical backup rejects active uncommitted writer in conservative mode");
      Register_Routine
        (T,
         Encrypted_Physical_Backup_And_Restore'Access,
         "encrypted physical backup and restore authenticate persisted pages");
      Register_Routine
        (T,
         Encrypted_Physical_Backup_Rejects_Tampered_Page'Access,
         "encrypted physical backup rejects tampered page artifact");
      Register_Routine
        (T,
         Encrypted_Physical_Backup_Rejects_Missing_Page_Sidecar'Access,
         "encrypted physical backup rejects missing manifest-listed page sidecar");
      Register_Routine
        (T,
         Encrypted_Physical_Backup_Rejects_Wrong_Key'Access,
         "encrypted physical backup rejects wrong restore key");
      Register_Routine
        (T,
         Logical_Export_And_Import'Access,
         "database-native export and import preserve rows");
      Register_Routine
        (T,
         Logical_Import_Accepts_Legacy_Metadata_Marker'Access,
         "database-native import accepts legacy metadata marker");

      Register_Routine
        (T,
         Logical_Export_Import_Preserves_Exact_Values'Access,
         "database-native export and import preserve Unicode Decimal and Blob exactly");
      Register_Routine
        (T,
         Logical_Import_Rejects_Invalid_Export'Access,
         "database-native import rejects malformed export files");
   end Register_Tests;
end Backup_Restore_Tests;
