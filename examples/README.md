# Examples

Each example is a small standalone GPR project that depends on `../../database.gpr`.

Build from an example directory, for example:

```sh
alr exec -- gprbuild -P minimal.gpr
```

Examples:

- `minimal` opens and closes an in-memory database.
- `persistent` creates a persistent database, inserts a row, reopens it, and reads it back.
- `queries` demonstrates row pipeline composition and aggregation.
- `migrations` registers a typed table and applies an explicit add-column migration.
- `concurrency` demonstrates multiple readers and single-writer exclusion.
- `integrity_check` runs integrity checking and diagnostics in a transaction.

## typed_table

Demonstrates the core user-facing workflow:

- Ada record row model
- explicit schema
- `To_Row`
- `From_Row`
- `Key_Of`
- typed table registration
- transaction-scoped CRUD
- predicate-based filtering without SQL
