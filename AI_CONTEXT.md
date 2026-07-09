# AI Context for `database`

This file is the high-signal entry point for AI coding agents working on this
repository.

## Project Identity

`database` is an Ada 2022, Ada-native, strictly typed relational storage engine.

It is **not** a SQL database.

The public user model is:

- explicit schemas
- typed values and rows
- Ada records as the application-facing row model
- explicit mapping functions:
  - `To_Row`
  - `From_Row`
  - `Key_Of`
- all reads and writes through transaction objects

## Non-Goals

Do not add:

- SQL
- a SQL parser
- runtime reflection
- automatic Ada record memory persistence
- serialization of Ada record memory layout
- distributed clustering
- server mode

## Core Style Rules

- Use Ada 2022.
- Prefer correctness over performance.
- Prefer explicit status results for ordinary validation/corruption failures.
- Do not use exceptions for ordinary corruption detection.
- Do not use `goto`.
- Do not use Ada reserved words as identifiers.
- Public text APIs use `Wide_Wide_String` or `Unbounded_Wide_Wide_String`.
- Stable public specifications should have GNATdoc-style comments.
- Public subprogram comments should include `@param` and `@return` tags.
- Tests use AUnit.
- Builds must use Alire-selected GNAT 15 (`gnat_native = "=15.2.1"`); never run
  plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, `gprbuild`,
  `gnatdoc`, or `gprinstall`.
- RAII transaction style is preferred where the package API supports it.

## Current Source-Level Status

- Source packages: 102
- Test bodies: 35
- Test assertions detected: 1176
- Registered AUnit routines detected: 229
- SPARK project files: 13
- Examples: 16

Project-local tooling uses the sibling `../project_tools` crate, and
cryptographic primitives come from the sibling `../cryptolib` crate. Build the
checker with `alr exec -- gprbuild -P tools/tools.gpr` and use `tools/bin/check_all` as the
default validation entrypoint.

## Main Documentation

Read these first:

1. `README.md`
2. `docs/getting-started.md`
3. `docs/design.md`
4. `docs/package-inventory.md`
5. `docs/testing.md`
6. `docs/build-and-verification.md`
7. `docs/spark-verification.md`
8. `docs/ai-usage-guide.md`
9. `docs/maintenance-recipes.md`

## Examples

Start with:

- `examples/typed_table`
- `examples/minimal`
- `examples/persistent`
- `examples/queries`
- `examples/migrations`
- `examples/concurrency`
- `examples/integrity_check`

## Validation Commands

Default release validation:

```sh
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

Quickstart example validation:

```sh
alr exec -- gprbuild -P examples/typed_table/typed_table.gpr
examples/typed_table/bin/main
```

Generate docs:

```sh
alr exec -- gnatdoc -P database.gpr
```

Run SPARK-oriented proof attempts:

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
tools/bin/check_all --proof-strict
```

The `spark_*.gpr` proof projects include `spark_stubs/` before `src/` to supply
minimal parent namespace specs for the isolated SPARK slices.

## Safe Modification Checklist

When changing code:

1. Identify the package spec and body.
2. Update tests or add a new AUnit case.
3. Update examples if the user-facing API changes.
4. Update docs if behavior, invariants, or usage changes.
5. Preserve non-goals.
6. Preserve transaction-scoped access.
7. Preserve explicit row mapping.
8. Preserve GNATdoc `@param` / `@return` coverage.
9. Run `tools/bin/check_all`, plus GNATdoc/GNATprove when those surfaces are affected.
10. Record any known limitation honestly.

## Package Groups

- advanced_relational: 6 packages
- backup_import_export: 5 packages
- core: 14 packages
- encryption: 5 packages
- extensions: 5 packages
- full_text: 11 packages
- hardening: 8 packages
- indexes: 3 packages
- observability: 6 packages
- query_optimization: 8 packages
- storage: 8 packages
- transactions_mvcc: 5 packages
- typed_data_model: 7 packages
- wal_recovery: 5 packages
