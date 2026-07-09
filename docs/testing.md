# Testing Strategy

Testing is AUnit-based and organized as unit, integration, hardening, fuzzing,
stress, crash, and SPARK-oriented validation suites.

## Coverage Snapshot

The project_tools-backed release check currently runs the full AUnit suite:

- tests run: 229
- failed assertions: 0
- unexpected errors: 0
- packages with missing direct source-level test coverage: 0
- unregistered AUnit case packages: 0
- unsafe local AUnit registrations: 0

## Test Categories

### Unit Tests

Unit tests validate package-local behavior for typed values, rows, schemas,
status handling, optional values, storage helpers, checksums, parsers, and
support packages.

### Integration Tests

Integration tests cover transactions, persistent storage, indexes, migrations,
queries, MVCC, WAL, backup/restore, encryption, extensions, observability, and
advanced relational features.

### Hardening Tests

Hardening tests cover fault injection, crash simulation, power-loss cases,
invariant checks, fuzzing, randomized workloads, and bounded stress scenarios.

### SPARK-Oriented Behavioral Tests

The source tree includes behavioral AUnit tests for the SPARK-oriented subsets:

- `Database.Checksums`
- `Database.WAL.Frame_Parser`
- `Database.Storage.Page_Parser`
- `Database.Storage.Record_Serializer`
- `Database.Storage.Free_List_Manager`
- `Database.Indexes.BTree_Invariants`

## Required Validation

The normal test and release entrypoint is the project_tools-backed checker. It
expects the sibling `../project_tools` tooling crate and the sibling
`../cryptolib` crypto dependency to be present:

```sh
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

That checker validates the release surface, builds `database.gpr`, builds the
AUnit test crate through Alire, runs `tests/bin/tests`, generates GNATdoc output,
and runs GNATprove legality checks for the SPARK project files.
