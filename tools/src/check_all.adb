with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Tree_Checks;

procedure Check_All is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;

   function Project_Root return String is
      Root : constant String :=
        Project_Tools.Files.Find_Root_Upward
          (Ada.Directories.Current_Directory, "database.gpr");
   begin
      if Root = "" then
         Put_Line (Standard_Error, "check_all must be run inside the database tree");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
      return Root;
   end Project_Root;

   Root    : constant String := Project_Root;
   Checks  : constant Project_Tools.Release_Checks.Checker :=
     Project_Tools.Release_Checks.Create (Root);
   Alr      : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Gprbuild : constant String := Project_Tools.Processes.Locate_Command ("gprbuild");
   Gnatdoc  : constant String := Project_Tools.Processes.Locate_Command ("gnatdoc");
   Gnatprove : constant String := Project_Tools.Processes.Locate_Command ("gnatprove");

   procedure Require_Command (Name : String; Path : String) is
   begin
      if Path = "" then
         Project_Tools.Release_Checks.Fail
           (Name & " is required for database verification");
      end if;
   end Require_Command;

   procedure Require_File (Relative_Path : String) is
   begin
      Project_Tools.Release_Checks.Require_File (Checks, Relative_Path);
   end Require_File;

   procedure Require_Text (Relative_Path : String; Text : String) is
   begin
      Project_Tools.Release_Checks.Require_Text (Checks, Relative_Path, Text);
   end Require_Text;

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List;
      Quiet   : Boolean := False) renames Project_Tools.Release_Checks.Run;

   procedure Clean_Generated_Artifacts is
      procedure Delete (Relative_Path : String) is
      begin
         Project_Tools.Files.Delete_Tree (Root & "/" & Relative_Path);
      end Delete;
   begin
      Delete ("obj");
      Delete ("lib");
      Delete ("gnatprove");
      Delete ("tests/obj");
      Delete ("tests/bin");
      Delete ("tools/obj");
      Delete ("examples/minimal/obj");
      Delete ("examples/minimal/bin");
      Delete ("examples/persistent/obj");
      Delete ("examples/persistent/bin");
      Delete ("examples/queries/obj");
      Delete ("examples/queries/bin");
      Delete ("examples/migrations/obj");
      Delete ("examples/migrations/bin");
      Delete ("examples/concurrency/obj");
      Delete ("examples/concurrency/bin");
      Delete ("examples/integrity_check/obj");
      Delete ("examples/integrity_check/bin");
      Delete ("examples/typed_table/obj");
      Delete ("examples/typed_table/bin");
      Project_Tools.Files.Delete_Tree ("/tmp/database_gnatdoc");
   end Clean_Generated_Artifacts;

   procedure Check_Static_Release_Surface is
      Errors : Natural := 0;
      Forbidden : constant Project_Tools.Tree_Checks.Text_List :=
        [To_Unbounded_String ("TODO"),
         To_Unbounded_String ("FIXME"),
         To_Unbounded_String ("Not_Implemented"),
         To_Unbounded_String ("not implemented")];

      procedure Require_Example (Name : String) is
      begin
         Require_File ("examples/" & Name & "/" & Name & ".gpr");
         Require_File ("examples/" & Name & "/src/main.adb");
      end Require_Example;

      procedure Require_Documentation is
         Required_Docs : constant Project_Tools.Tree_Checks.Text_List :=
           [To_Unbounded_String ("docs/README.md"),
            To_Unbounded_String ("docs/getting-started.md"),
            To_Unbounded_String ("docs/design.md"),
            To_Unbounded_String ("docs/build-and-verification.md"),
            To_Unbounded_String ("docs/testing.md"),
            To_Unbounded_String ("docs/maintenance-recipes.md"),
            To_Unbounded_String ("docs/transactions.md"),
            To_Unbounded_String ("docs/transaction-semantics.md"),
            To_Unbounded_String ("docs/mvcc.md"),
            To_Unbounded_String ("docs/storage-format.md"),
            To_Unbounded_String ("docs/wal.md"),
            To_Unbounded_String ("docs/query-optimizer.md"),
            To_Unbounded_String ("docs/relational-features.md"),
            To_Unbounded_String ("docs/type-system.md"),
            To_Unbounded_String ("docs/backup-restore.md"),
            To_Unbounded_String ("docs/encrypted-backup-restore.md"),
            To_Unbounded_String ("docs/encryption.md"),
            To_Unbounded_String ("docs/export-import.md"),
            To_Unbounded_String ("docs/extensions.md"),
            To_Unbounded_String ("docs/full-text-search.md"),
            To_Unbounded_String ("docs/observability.md"),
            To_Unbounded_String ("docs/callable_registry_ownership.md"),
            To_Unbounded_String ("docs/per_handle_registry_ownership.md"),
            To_Unbounded_String ("docs/real_encrypted_persistence.md"),
            To_Unbounded_String ("docs/sidecar_manifest_consistency.md"),
            To_Unbounded_String ("docs/hardening.md"),
            To_Unbounded_String ("docs/external-crash-harness.md"),
            To_Unbounded_String ("docs/spark-verification.md"),
            To_Unbounded_String ("docs/spark-checksums.md"),
            To_Unbounded_String ("docs/spark-wal-frame-parser.md"),
            To_Unbounded_String ("docs/spark-page-parser.md"),
            To_Unbounded_String ("docs/spark-record-serialization.md"),
            To_Unbounded_String ("docs/spark-free-list-management.md"),
            To_Unbounded_String ("docs/spark-btree-invariants.md"),
            To_Unbounded_String ("docs/api-stability.md"),
            To_Unbounded_String ("docs/package-inventory.md"),
            To_Unbounded_String ("docs/ai-usage-guide.md"),
            To_Unbounded_String ("docs/support_package_tests.md")];
      begin
         for Doc of Required_Docs loop
            Require_File (To_String (Doc));
            if To_String (Doc) /= "docs/README.md" then
               Require_Text ("docs/README.md", To_String (Doc) (6 .. Length (Doc)));
            end if;
         end loop;

         Require_Text ("README.md", "docs/README.md");
         Require_Text ("README.md", "docs/getting-started.md");
         Require_Text ("docs/build-and-verification.md", "tools/bin/check_all");
         Require_Text ("docs/build-and-verification.md", "../project_tools");
      Require_Text ("docs/getting-started.md", "gprbuild -P examples/typed_table/typed_table.gpr");
      Require_Text ("docs/getting-started.md", "examples/typed_table/bin/main");
      Require_Text ("docs/ai-usage-guide.md", "gprbuild -P examples/typed_table/typed_table.gpr");
      Require_Text ("examples/typed_table/README.md", "examples/typed_table/bin/main");

      end Require_Documentation;
   begin
      Require_File ("README.md");
      Require_File ("database.gpr");
      Require_File ("tests/tests.gpr");
      Require_File ("tools/tools.gpr");
      Require_File ("tools/src/check_all.adb");

      Require_Text ("README.md", "project_tools");
      Require_Documentation;

      Require_Example ("minimal");
      Require_Example ("persistent");
      Require_Example ("queries");
      Require_Example ("migrations");
      Require_Example ("concurrency");
      Require_Example ("integrity_check");
      Require_Example ("typed_table");

      Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
        (Errors, Root & "/src", Forbidden, "stable source");
      Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
        (Errors, Root & "/tests/src", Forbidden, "test source");
      Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
        (Errors, Root & "/examples", Forbidden, "examples");
      Project_Tools.Tree_Checks.Check_No_Generated_Python (Errors, Root & "/src");
      Project_Tools.Tree_Checks.Check_No_Generated_Python (Errors, Root & "/tests/src");
      Project_Tools.Tree_Checks.Check_No_Generated_Python (Errors, Root & "/examples");

      if Errors > 0 then
         Project_Tools.Release_Checks.Fail ("static release checks failed");
      end if;
   end Check_Static_Release_Surface;

begin
   Require_Command ("alr", Alr);
   Require_Command ("gprbuild", Gprbuild);
   Require_Command ("gnatdoc", Gnatdoc);
   Require_Command ("gnatprove", Gnatprove);

   Check_Static_Release_Surface;
   Clean_Generated_Artifacts;

   Run
     ("database build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("database.gpr")]);
   Clean_Generated_Artifacts;
   Run ("tests build", Root & "/tests", Alr, [1 => new String'("build")]);
   Run ("AUnit tests", Root & "/tests", "./bin/tests", []);
   Clean_Generated_Artifacts;
   Run
     ("minimal example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/minimal/minimal.gpr")]);
   Run
     ("persistent example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/persistent/persistent.gpr")]);
   Run
     ("queries example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/queries/queries.gpr")]);
   Run
     ("migrations example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/migrations/migrations.gpr")]);
   Run
     ("concurrency example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/concurrency/concurrency.gpr")]);
   Run
     ("integrity_check example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/integrity_check/integrity_check.gpr")]);
   Run
     ("typed_table example build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("examples/typed_table/typed_table.gpr")]);
   Run ("typed_table example run", Root, "examples/typed_table/bin/main", []);
   Project_Tools.Files.Delete_Tree ("/tmp/database_gnatdoc");
   Ada.Directories.Create_Path (Root & "/obj");
   Ada.Directories.Create_Path (Root & "/lib");
   Run
     ("GNATdoc", Root, Gnatdoc,
      [new String'("-P"), new String'("database.gpr"),
       new String'("-O"), new String'("/tmp/database_gnatdoc")]);
   Run
     ("SPARK checksums legality", Root, Gnatprove,
      [new String'("-P"), new String'("spark_checksums.gpr"),
       new String'("--level=0"), new String'("--mode=check")]);
   Run
     ("SPARK WAL frame parser legality", Root, Gnatprove,
      [new String'("-P"), new String'("spark_wal_frame_parser.gpr"),
       new String'("--level=0"), new String'("--mode=check")]);
   Run
     ("SPARK page parser legality", Root, Gnatprove,
      [new String'("-P"), new String'("spark_page_parser.gpr"),
       new String'("--level=0"), new String'("--mode=check")]);
   Run
     ("SPARK record serializer legality", Root, Gnatprove,
      [new String'("-P"), new String'("spark_record_serializer.gpr"),
       new String'("--level=0"), new String'("--mode=check")]);
   Run
     ("SPARK free-list legality", Root, Gnatprove,
      [new String'("-P"), new String'("spark_free_list_manager.gpr"),
       new String'("--level=0"), new String'("--mode=check")]);
   Run
     ("SPARK B+ tree invariant legality", Root, Gnatprove,
      [new String'("-P"), new String'("spark_btree_invariants.gpr"),
       new String'("--level=0"), new String'("--mode=check")]);

   Clean_Generated_Artifacts;

   Put_Line ("database project_tools checklist passed");
exception
   when Program_Error =>
      null;
end Check_All;
