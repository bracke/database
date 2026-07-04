# AI Usage Guide

This guide explains how an AI coding agent should work with this repository.

## First Files to Read

1. `AI_CONTEXT.md`
2. `ai-manifest.json`
3. `README.md`
4. `docs/getting-started.md`
5. `docs/design.md`
6. `docs/package-inventory.md`
7. `docs/testing.md`
8. `docs/build-and-verification.md`

## First Commands to Run

```sh
gprbuild -P tools/tools.gpr
tools/bin/check_all
gprbuild -P examples/typed_table/typed_table.gpr
examples/typed_table/bin/main
```

Use `examples/typed_table/src/main.adb` as the current quickstart source of
truth for typed record mapping, schema construction, transactions, and
predicate scans.

## How to Understand the Codebase

Use this order:

1. Read `Database.Status` and `Database.Values`.
2. Read `Database.Schema` and `Database.Rows`.
3. Read `Database.Transactions`.
4. Read `Database.Tables`.
5. Read storage packages under `Database.Storage`.
6. Read WAL/recovery packages.
7. Read index packages.
8. Read query/optimizer packages.
9. Read MVCC/visibility packages.
10. Read hardening and SPARK-oriented packages.

## How to Add a Public API

When adding a public API:

1. Add the declaration to the `.ads`.
2. Add GNATdoc-style comments immediately above it.
3. Include `@param` for every parameter.
4. Include `@return` for every function.
5. Add or update the `.adb` implementation.
6. Add AUnit tests.
7. Add example/docs updates if user-facing.
8. Update `ai-manifest.json` if package inventory or validation commands change.

## How to Add a Package

When adding a package:

1. Add `src/database-...ads`.
2. Add `src/database-...adb` if the spec requires a body.
3. Ensure parent child packages exist.
4. Add package-level GNATdoc comments.
5. Add tests under `tests/src`.
6. Register the AUnit case in the main test suite.
7. Add package to docs where appropriate.
8. Update `docs/package-inventory.md` and `ai-manifest.json`.

## How to Add a Test

1. Create `tests/src/<feature>_tests.ads`.
2. Create `tests/src/<feature>_tests.adb`.
3. Define `Case_Type`.
4. Register routines using `Register_Routine`.
5. Add the case to `tests/src/database_test_suite.adb`.
6. Avoid local aliased test case registrations that escape scope.
7. Use real assertions, not smoke-only tests.

## How to Modify Storage or Recovery

For storage/WAL/recovery changes:

1. Identify durable format impact.
2. Update storage docs.
3. Add corruption rejection tests.
4. Add recovery/replay tests.
5. Update invariant checks if structure changes.
6. Preserve deterministic recovery behavior.
7. Do not silently accept malformed pages, records, WAL frames, or encrypted artifacts.

## How to Modify User-Facing Behavior

For user-facing API changes:

1. Update `docs/getting-started.md`.
2. Update relevant examples.
3. Update README if the workflow changes.
4. Preserve no-SQL and explicit mapping semantics.
5. Keep examples transaction-scoped.

## Do Not Do These

- Do not add SQL.
- Do not add parser infrastructure.
- Do not persist Ada record memory layout.
- Do not add runtime reflection.
- Do not bypass transaction objects.
- Do not replace explicit status results with ordinary exceptions for corruption.
- Do not remove Unicode-wide text support.
