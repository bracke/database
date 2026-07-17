with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
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
   use type Ada.Directories.File_Kind;

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
   Env      : constant String := Project_Tools.Processes.Locate_Command ("env");

   function Has_Argument (Value : String) return Boolean is
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (Index) = Value then
            return True;
         end if;
      end loop;

      return False;
   end Has_Argument;

   Strict_Proofs : constant Boolean := Has_Argument ("--proof-strict");

   procedure Require_Command (Name : String; Path : String) is
   begin
      if Path = "" then
         Project_Tools.Release_Checks.Fail
           (Name & " is required for database verification");
      end if;
   end Require_Command;

   procedure Require_GNAT_15_Toolchain is
      Output : Unbounded_String;
      Status : Integer;
   begin
      Status := Project_Tools.Processes.Run_Status
        ("Alire GNAT 15 toolchain",
         Root,
         Alr,
         [new String'("exec"), new String'("--"),
          new String'("gnatls"), new String'("--version")],
         Output,
         Quiet => True);

      if Status /= 0 then
         Project_Tools.Release_Checks.Fail
           ("could not run `alr exec -- gnatls --version`");
      end if;

      if Ada.Strings.Fixed.Index (To_String (Output), "GNATLS 15.") = 0 then
         Project_Tools.Release_Checks.Fail
           ("database verification must use Alire GNAT 15; got: "
            & To_String (Output));
      end if;
   end Require_GNAT_15_Toolchain;

   procedure Require_File (Relative_Path : String) is
   begin
      Project_Tools.Release_Checks.Require_File (Checks, Relative_Path);
   end Require_File;

   procedure Require_Sibling_File (Relative_Path : String) is
   begin
      if not Ada.Directories.Exists (Root & "/../" & Relative_Path) then
         Project_Tools.Release_Checks.Fail
           ("required sibling file is missing: ../" & Relative_Path);
      end if;
   end Require_Sibling_File;

   procedure Require_Text (Relative_Path : String; Text : String) is
   begin
      Project_Tools.Release_Checks.Require_Text (Checks, Relative_Path, Text);
   end Require_Text;

   procedure Ensure_Sibling_Directory (Relative_Path : String) is
   begin
      Ada.Directories.Create_Path (Root & "/../" & Relative_Path);
   end Ensure_Sibling_Directory;

   procedure Clean_Cryptolib_Generated_Artifacts is
   begin
      Project_Tools.Files.Delete_Tree (Root & "/../cryptolib/obj");
      Project_Tools.Files.Delete_Tree (Root & "/../cryptolib/lib");
      Ensure_Sibling_Directory ("cryptolib/obj/release");
      Ensure_Sibling_Directory ("cryptolib/lib");
   end Clean_Cryptolib_Generated_Artifacts;

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List;
      Quiet   : Boolean := False) renames Project_Tools.Release_Checks.Run;

   procedure Run_Expect_Failure
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List) is
      Output : Unbounded_String;
      Status : Integer;
   begin
      Status := Project_Tools.Processes.Run_Status
        (Label, Dir, Program, Args, Output, Quiet => True);

      if Status = 0 then
         Project_Tools.Release_Checks.Fail
           (Label & " unexpectedly succeeded");
      end if;
   end Run_Expect_Failure;

   procedure Run_Expect_Output
     (Label           : String;
      Dir             : String;
      Program         : String;
      Args            : GNAT.OS_Lib.Argument_List;
      Expected_Output : String) is
      Output : Unbounded_String;
      Status : Integer;
   begin
      Status := Project_Tools.Processes.Run_Status
        (Label, Dir, Program, Args, Output, Quiet => True);

      if Status /= 0 then
         Project_Tools.Release_Checks.Fail
           (Label & " failed with status" & Integer'Image (Status));
      elsif To_String (Output) /= Expected_Output then
         Project_Tools.Release_Checks.Fail
           (Label & " output mismatch; expected `"
            & Expected_Output & "` got `" & To_String (Output) & "`");
      end if;
   end Run_Expect_Output;

   procedure Clean_Generated_Artifacts is
      procedure Delete (Relative_Path : String) is
      begin
         Project_Tools.Files.Delete_Tree (Root & "/" & Relative_Path);
      end Delete;

      procedure Delete_Test_Files (Name_Pattern : String) is
         Search      : Ada.Directories.Search_Type;
         Search_Open : Boolean := False;
         Dir_Entry   : Ada.Directories.Directory_Entry_Type;
         Test_Root   : constant String := Root & "/tests";
      begin
         if not Ada.Directories.Exists (Test_Root) then
            return;
         end if;

         Ada.Directories.Start_Search (Search, Test_Root, Name_Pattern);
         Search_Open := True;
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
            if Ada.Directories.Kind (Dir_Entry) = Ada.Directories.Ordinary_File then
               Project_Tools.Files.Delete_File_If_Present
                 (Test_Root & "/" & Ada.Directories.Simple_Name (Dir_Entry));
            end if;
         end loop;
         Ada.Directories.End_Search (Search);
      exception
         when others =>
            if Search_Open then
               Ada.Directories.End_Search (Search);
            end if;
            raise;
      end Delete_Test_Files;
   begin
      Delete ("obj");
      Delete ("lib");
      if not Strict_Proofs then
         Delete ("gnatprove");
      end if;
      Delete ("tests/obj");
      Delete ("tests/bin");
      Delete ("tools/obj");
      Delete ("database_inspect/obj");
      Delete ("database_inspect/bin");
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
      Delete_Test_Files ("*.dbenc");
      Delete_Test_Files ("*.database");
      Delete_Test_Files ("*.database.*");
      Delete_Test_Files ("*.db");
      Delete_Test_Files ("*.db.*");
      Delete_Test_Files ("*.fts");
      Delete_Test_Files ("*.enc");
      Delete_Test_Files ("*.ready");
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
            To_Unbounded_String ("docs/database-inspect.md"),
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
         Require_Text ("docs/build-and-verification.md", "../cryptolib");
         Require_Text ("docs/build-and-verification.md", "../cryptolib/obj");
         Require_Text ("docs/build-and-verification.md", "GNAT 15");
         Require_Text ("docs/build-and-verification.md", "database_inspect");
         Require_Text ("docs/testing.md", "229");
         Require_Text ("docs/database-inspect.md", "database_inspect");
         Require_Text ("docs/database-inspect.md", "--help");
         Require_Text ("docs/database-inspect.md", "--version");
         Require_Text ("docs/database-inspect.md", "schemas");
         Require_Text ("docs/database-inspect.md", "indexes");
         Require_Text ("docs/database-inspect.md", "dump --all");
         Require_Text ("docs/database-inspect.md", "--encrypted");
         Require_Text ("docs/database-inspect.md", "DATABASE_INSPECT_PASSPHRASE");
         Require_Text ("docs/README.md", "../cryptolib");
         Require_Text ("docs/ai-usage-guide.md", "../cryptolib");
         Require_Text ("docs/package-inventory.md", "../cryptolib");
         Require_Text ("AI_CONTEXT.md", "../cryptolib");
         Require_Text ("AI_CONTEXT.md", "229");
         Require_Text ("ai-manifest.json", "registered_aunit_routines_detected");
         Require_Text ("ai-manifest.json", "1176");
         Require_Text ("ai-manifest.json", "229");
         Require_Text ("ai-manifest.json", "../cryptolib");
         Require_Text
           ("docs/getting-started.md", "../cryptolib");
         Require_Text
           ("docs/getting-started.md",
            "alr exec -- gprbuild -P examples/typed_table/typed_table.gpr");
         Require_Text
           ("docs/getting-started.md", "examples/typed_table/bin/main");
         Require_Text
           ("docs/ai-usage-guide.md",
            "alr exec -- gprbuild -P examples/typed_table/typed_table.gpr");
         Require_Text
           ("examples/typed_table/README.md", "examples/typed_table/bin/main");

      end Require_Documentation;
   begin
      Require_File ("README.md");
      Require_File ("AGENTS.md");
      Require_File ("database.gpr");
      Require_Text ("alire.toml", "gnat_native = ""=15.2.1""");
      Require_Text ("tests/alire.toml", "gnat_native = ""=15.2.1""");
      Require_Sibling_File ("cryptolib/cryptolib.gpr");
      Require_File ("tests/tests.gpr");
      Require_File ("tools/tools.gpr");
      Require_File ("tools/src/check_all.adb");
      Require_File ("database_inspect/alire.toml");
      Require_File ("database_inspect/database_inspect.gpr");
      Require_File ("database_inspect/src/database-inspect.ads");
      Require_File ("database_inspect/src/database-inspect.adb");
      Require_File ("database_inspect/src/database_inspect.adb");
      Require_File ("database_inspect/src/database_inspect_make_encrypted_fixture.adb");
      Require_Text ("database_inspect/alire.toml", "gnat_native = ""=15.2.1""");
      Require_Text ("database_inspect/alire.toml", "database = { path = "".."" }");

      Require_Text ("README.md", "project_tools");
      Require_Text ("README.md", "cryptolib");
      Require_Text ("README.md", "GNAT 15");
      Require_Text ("README.md", "gnat_native = ""=15.2.1""");
      Require_Text ("AGENTS.md", "gnat_native = ""=15.2.1""");
      Require_Text ("docs/build-and-verification.md", "gnat_native = ""=15.2.1""");
      Require_Text ("README.md", "229");
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
   Require_Command ("env", Env);

   Require_GNAT_15_Toolchain;

   Check_Static_Release_Surface;
   Clean_Generated_Artifacts;

   Run
     ("database build", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("database.gpr")]);
   Clean_Generated_Artifacts;
   Clean_Cryptolib_Generated_Artifacts;
   Run
     ("tests build", Root & "/tests", Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("tests.gpr")]);
   Run ("AUnit tests", Root & "/tests", "./bin/tests", []);
   Clean_Generated_Artifacts;
   Run
     ("database_inspect build", Root & "/database_inspect", Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-p"), new String'("-j1"), new String'("-P"),
       new String'("database_inspect.gpr")]);
   Run
     ("database_inspect help smoke", Root, "database_inspect/bin/database_inspect",
      [new String'("--help")],
      Quiet => True);
   Run_Expect_Output
     ("database_inspect version smoke", Root, "database_inspect/bin/database_inspect",
      [new String'("--version")],
      "database_inspect 0.14.0" & Character'Val (10));
   Run
     ("database_inspect schema smoke", Root, "database_inspect/bin/database_inspect",
      [new String'("tests/full_text_query_reopen_test_db"),
       new String'("schemas")],
      Quiet => True);
   Run
     ("database_inspect dump smoke", Root, "database_inspect/bin/database_inspect",
      [new String'("tests/full_text_query_reopen_test_db"),
       new String'("dump"), new String'("--all"), new String'("5")],
      Quiet => True);
   Run
     ("database_inspect index smoke", Root, "database_inspect/bin/database_inspect",
      [new String'("tests/full_text_query_reopen_test_db"),
       new String'("indexes")],
      Quiet => True);
   Run_Expect_Failure
     ("database_inspect rejects extra schema args",
      Root,
      "database_inspect/bin/database_inspect",
      [new String'("tests/full_text_query_reopen_test_db"),
       new String'("schemas"),
       new String'("extra")]);
   Run_Expect_Failure
     ("database_inspect rejects invalid dump limit",
      Root,
      "database_inspect/bin/database_inspect",
      [new String'("tests/full_text_query_reopen_test_db"),
       new String'("dump"),
       new String'("--all"),
       new String'("not-a-number")]);
   Run
     ("database_inspect encrypted fixture create",
      Root,
      "database_inspect/bin/database_inspect_make_encrypted_fixture",
      [new String'("tests/database_inspect_encrypted_smoke.database")],
      Quiet => True);
   Run
     ("database_inspect encrypted schema smoke",
      Root,
      Env,
      [new String'("DATABASE_INSPECT_PASSPHRASE=database-inspect-smoke"),
       new String'("database_inspect/bin/database_inspect"),
       new String'("--encrypted"),
       new String'("tests/database_inspect_encrypted_smoke.database"),
       new String'("schemas")],
      Quiet => True);
   Run
     ("database_inspect encrypted index smoke",
      Root,
      Env,
      [new String'("DATABASE_INSPECT_PASSPHRASE=database-inspect-smoke"),
       new String'("database_inspect/bin/database_inspect"),
       new String'("--encrypted"),
       new String'("tests/database_inspect_encrypted_smoke.database"),
       new String'("indexes")],
      Quiet => True);
   Run
     ("database_inspect encrypted dump smoke",
      Root,
      Env,
      [new String'("DATABASE_INSPECT_PASSPHRASE=database-inspect-smoke"),
       new String'("database_inspect/bin/database_inspect"),
       new String'("--encrypted"),
       new String'("tests/database_inspect_encrypted_smoke.database"),
       new String'("dump"),
       new String'("docs"),
       new String'("5")],
      Quiet => True);
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
     ("GNATdoc", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatdoc"),
       new String'("-P"), new String'("database.gpr"),
       new String'("-O"), new String'("/tmp/database_gnatdoc")]);
   Run
     ("SPARK checksums proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_checksums.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK log sequence proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_log_sequence.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK WAL frame parser proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_wal_frame_parser.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK WAL payload rules proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_wal_payload_rules.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK page parser proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_page_parser.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK record serializer proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_record_serializer.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK catalog rules proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_catalog_rules.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK versioning proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_versioning.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK transaction state rules proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_transaction_state_rules.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK visibility rules proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_visibility_rules.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK free-list proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_free_list_manager.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK table heap layout proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_table_heap_layout.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);
   Run
     ("SPARK B+ tree invariant proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("spark_btree_invariants.gpr"),
       new String'("--level=2"), new String'("--checks-as-errors=on")]);

   Clean_Generated_Artifacts;

   Put_Line ("database project_tools checklist passed");
exception
   when Program_Error =>
      null;
end Check_All;
