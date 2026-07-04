# Maintenance Recipes

This document gives repeatable recipes for common repository changes.

## Recipe: Add a New Public Function

1. Edit the package specification.
2. Add a GNATdoc comment immediately above the function.
3. Add one `@param` line per parameter.
4. Add one `@return` line.
5. Implement the function in the package body.
6. Add AUnit tests for success and failure cases.
7. Update docs/examples if the function is user-facing.
8. Run:
   ```sh
   gprbuild -P tools/tools.gpr
   tools/bin/check_all
   ```

## Recipe: Add a New Durable Format Field

1. Update the durable format package.
2. Update parser validation.
3. Update corruption rejection tests.
4. Update replay/recovery tests if WAL-visible.
5. Update backup/export/import tests if persisted externally.
6. Update `docs/storage-format.md`.
7. Preserve backward/forward validation rules explicitly.

## Recipe: Add a New Test Case Package

1. Add `tests/src/name_tests.ads`.
2. Add `tests/src/name_tests.adb`.
3. Define `Case_Type`.
4. Register routines in `Register_Tests`.
5. Add it to `tests/src/database_test_suite.adb` with:
   ```ada
   AUnit.Test_Suites.Add_Test (S, new Name_Tests.Case_Type);
   ```
6. Avoid passing access to local aliased test case objects.

## Recipe: Add a SPARK-Oriented Subset

1. Keep the subset small and deterministic.
2. Mark the package with `SPARK_Mode => On`.
3. Avoid file I/O and heap-heavy integration logic.
4. Add `Global` and `Depends` aspects.
5. Add preconditions/postconditions where useful.
6. Add loop invariants for traversal.
7. Add a dedicated `spark_*.gpr`.
8. Add AUnit behavioral tests.
9. Document expected `gnatprove` command.

## Recipe: Update Examples

1. Keep examples small and single-purpose.
2. Prefer complete workflows over fragments.
3. Show transaction use.
4. Show error/status handling.
5. Avoid SQL-like wording.
6. Update `examples/README.md`.

## Recipe: Run Final Local Validation

```sh
gprbuild -P tools/tools.gpr
tools/bin/check_all
gnatdoc -P database.gpr
gnatprove -P spark_checksums.gpr --level=2
gnatprove -P spark_wal_frame_parser.gpr --level=2
gnatprove -P spark_page_parser.gpr --level=2
gnatprove -P spark_record_serializer.gpr --level=2
gnatprove -P spark_free_list_manager.gpr --level=2
gnatprove -P spark_btree_invariants.gpr --level=2
```

Record any failures directly and do not claim completion until they are resolved.
