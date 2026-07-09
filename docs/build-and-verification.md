# Build and Verification

Project-local build, test, and release checks use the sibling
`../project_tools` crate. Cryptographic builds use the sibling
`../cryptolib` crate through `database.gpr`. All project builds must use Alire
GNAT 15 (`gnat_native = "=15.2.1"` in the root, tests, and
`database_inspect` crates). Confirm with `alr exec -- gnatls --version`. Do not
run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, `gprbuild`,
`gnatdoc`, or `gprinstall` in this workspace. The
database-specific checker owns this repository's policy while reusing
`Project_Tools.Release_Checks`, `Project_Tools.Tree_Checks`, and process
helpers.

## Recommended Release Check

```sh
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

`tools/bin/check_all` validates the release surface, verifies that `alr exec`
selects GNATLS 15.x, builds `database.gpr` through
`alr exec -- gprbuild`, builds the AUnit test crate, runs `tests/bin/tests`,
builds the `database_inspect` subcrate and smoke-tests it against a persistent
fixture, builds the maintained examples, runs the typed-table quickstart
example, generates GNATdoc output under `/tmp/database_gnatdoc`, and runs
GNATprove legality checks for the SPARK project files.

Building `database.gpr` may create generated `obj` and `lib` directories under
`../cryptolib`, because that crate owns its own build artifact directories. The
database checker validates that the sibling cryptolib project is present and
refreshes cryptolib generated artifacts before the tests build so dependency
state is deterministic. It cleans generated artifacts inside the database tree;
`../cryptolib/obj` and `../cryptolib/lib` may remain because they belong to the
sibling dependency crate.

## Direct Build Steps

```sh
alr exec -- gprbuild -P database.gpr
cd tests
alr build
./bin/tests
```

Build the inspection subcrate directly with:

```sh
cd database_inspect
alr exec -- gprbuild -P database_inspect.gpr
bin/database_inspect ../tests/full_text_query_reopen_test_db schemas
```

Run any dedicated crash, stress, fuzz, or child-process test executables after
the main AUnit suite.

## Recommended Documentation Step

```sh
alr exec -- gnatdoc -P database.gpr
```

## Recommended SPARK Steps

The normal release gate is:

```sh
tools/bin/check_all
```

For targeted GNATprove runs that match the normal gate:

```sh
alr exec -- gnatprove -P spark_checksums.gpr --level=2
alr exec -- gnatprove -P spark_log_sequence.gpr --level=2
alr exec -- gnatprove -P spark_wal_frame_parser.gpr --level=2
alr exec -- gnatprove -P spark_wal_payload_rules.gpr --level=2
alr exec -- gnatprove -P spark_page_parser.gpr --level=2
alr exec -- gnatprove -P spark_record_serializer.gpr --level=2
alr exec -- gnatprove -P spark_catalog_rules.gpr --level=2
alr exec -- gnatprove -P spark_versioning.gpr --level=2
alr exec -- gnatprove -P spark_transaction_state_rules.gpr --level=2
alr exec -- gnatprove -P spark_visibility_rules.gpr --level=2
alr exec -- gnatprove -P spark_free_list_manager.gpr --level=2
alr exec -- gnatprove -P spark_table_heap_layout.gpr --level=2
alr exec -- gnatprove -P spark_btree_invariants.gpr --level=2
```

The `spark_*.gpr` projects use proof-only parent namespace specs from
`spark_stubs/` so GNATprove does not analyze unrelated full-engine API parents.

For deeper proof-development runs with retained GNATprove reports:

```sh
tools/bin/check_all --proof-strict
```

## Interpreting This Archive

`tools/bin/check_all` is the minimum release validation gate. The direct commands
below are useful when iterating on a specific subsystem.

## GNATdoc Readiness

Specification comments include source-level `@param` and `@return` tag coverage for public subprogram declarations. Generate API documentation locally with GNATdoc to validate rendered output.
