# database

`database` is an Ada 2022, Ada-native, strictly typed relational storage engine.

It intentionally does **not** implement SQL, a SQL parser, a server mode, or
distributed clustering. Applications use Ada APIs, explicit schemas, typed row
values, and explicit mapping functions.

## Current Scope

The source tree contains the full core engine surface:

- typed values, rows, schemas, and metadata
- transaction-scoped access
- process-level persistent file locking
- persistent page/file/record storage
- rollback journal and WAL recovery
- B+ tree indexes
- schema evolution
- Ada-native query composition and optimization
- MVCC and visibility checks
- advanced relational metadata
- full-text search
- backup/restore and logical import/export
- maintained database file inspection subcrate
- encrypted persistence helpers
- extension registries
- expanded native type support
- tracing, metrics, profiling, and runtime diagnostics
- hardening, fuzzing, crash simulation, invariant checking, and SPARK-oriented verification subsets

## Deliberate Non-Goals

- SQL
- a parser
- automatic Ada record memory persistence
- runtime reflection
- distributed clustering
- server mode

## Verification Status

Project tooling is Ada-based and uses the sibling `../project_tools` crate.
Cryptographic primitives are provided by the sibling `../cryptolib` crate.
The project requires Alire GNAT 15 (`gnat_native = "=15.2.1"`); the release
checker fails if `alr exec -- gnatls --version` does not report GNATLS 15.x. Do
not run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, `gprbuild`,
`gnatdoc`, or `gprinstall` in this workspace. Build and release checks are run through `tools/bin/check_all`, which builds
the library, builds and runs the AUnit suite, generates GNATdoc output, and
runs GNATprove legality checks for the SPARK-oriented subsets.

## Test Suite Snapshot

Current AUnit coverage:

- tests run by `tools/bin/check_all`: 229
- failed assertions in the latest release-check run: 0
- unexpected errors in the latest release-check run: 0
- packages with missing direct source-level test coverage: 0
- unregistered AUnit case packages: 0
- unsafe local AUnit registrations: 0

## Documentation

Important documents:

- `docs/README.md`
- `docs/design.md`
- `docs/testing.md`
- `docs/hardening.md`
- `docs/storage-format.md`
- `docs/database-inspect.md`
- `docs/transaction-semantics.md`
- `docs/spark-verification.md`
- `docs/package-inventory.md`
- `docs/build-and-verification.md`

## Getting Started

Start with `docs/getting-started.md`.

## Build And Test

```sh
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

For a complete typed Ada record/table mapping example, see
`examples/typed_table`.


## AI Agent Entry Points

AI coding agents should start with:

- `AI_CONTEXT.md`
- `ai-manifest.json`
- `docs/ai-usage-guide.md`
- `docs/maintenance-recipes.md`
