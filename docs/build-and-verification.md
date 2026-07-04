# Build and Verification

Project-local build, test, and release checks use the sibling
`../project_tools` crate. The database-specific checker owns this repository's
policy while reusing `Project_Tools.Release_Checks`,
`Project_Tools.Tree_Checks`, and process helpers.

## Recommended Release Check

```sh
gprbuild -P tools/tools.gpr
tools/bin/check_all
```

`tools/bin/check_all` validates the release surface, builds `database.gpr`,
builds the AUnit test crate, runs `tests/bin/tests`, builds the maintained examples, runs the typed-table quickstart example, generates GNATdoc output
under `/tmp/database_gnatdoc`, and runs GNATprove legality checks for the
SPARK project files.

## Direct Build Steps

```sh
gprbuild -P database.gpr
cd tests
alr build
./bin/tests
```

Run any dedicated crash, stress, fuzz, or child-process test executables after
the main AUnit suite.

## Recommended Documentation Step

```sh
gnatdoc -P database.gpr
```

## Recommended SPARK Steps

```sh
gnatprove -P spark_checksums.gpr --level=2
gnatprove -P spark_wal_frame_parser.gpr --level=2
gnatprove -P spark_page_parser.gpr --level=2
gnatprove -P spark_record_serializer.gpr --level=2
gnatprove -P spark_free_list_manager.gpr --level=2
gnatprove -P spark_btree_invariants.gpr --level=2
```

## Interpreting This Archive

`tools/bin/check_all` is the minimum release validation gate. The direct commands
below are useful when iterating on a specific subsystem.

## GNATdoc Readiness

Specification comments include source-level `@param` and `@return` tag coverage for public subprogram declarations. Generate API documentation locally with GNATdoc to validate rendered output.
