# Public API stability

This document records the public API stabilization policy for
`database`.

## Stable public packages

The following package families are intended to be stable public API surfaces:

- `Database`
- `Database.Status`
- `Database.Optional`
- `Database.Types`
- `Database.Values`
- `Database.Rows`
- `Database.Schema`
- `Database.Constraints`
- `Database.Transactions`
- `Database.Catalog`
- `Database.Tables`
- `Database.Predicates`
- `Database.Queries`
- `Database.Aggregates`
- `Database.Ordering`
- `Database.Joins`
- `Database.Indexes`
- `Database.Migrations`
- `Database.Locking`
- `Database.Check`
- `Database.Vacuum`
- `Database.Diagnostics`
- `Database.Statistics`

`Database.Storage.*`, `Database.WAL`, `Database.Replay`, and `Database.Checkpointing` are documented
for maintainers and tests. Applications should prefer the typed table,
transaction, migration, check, and diagnostic APIs unless they are deliberately
building low-level maintenance tooling.

## Result and error policy

Ordinary database failures return `Database.Status.Result`. They should not be
reported by raising Ada exceptions. Examples include duplicate keys, schema
mismatches, read-only transaction writes, corruption reports, invalid migration
requests, and transaction conflicts.

Programming errors may still be exposed by Ada assertions in development builds.
Assertions are used for internal invariants that indicate defects in the engine
or incorrect low-level use.

## Naming conventions

- `Begin_Read` starts a read-only transaction.
- `Begin_Write` starts a read-write transaction.
- `Try_*` transaction routines never block and return `Granted`.
- `Register` attaches a typed API/schema to a database catalog.
- `Create_Index` and `Rebuild_Index` are explicit and transaction-scoped.
- `Try_Project`, `Try_Order_By`, and `Try_Inner_Join` return structured failures.
  Convenience versions return empty results on invalid input.

## Stability rules

Avoid breaking changes unless required to correct an unsound API. Additive
changes should preserve:

- explicit schemas
- explicit row mappings
- transaction-scoped operations
- Unicode text APIs
- no SQL and no parser
- no automatic record-layout persistence

## Ownership and lifetime

`Database.Handle` owns database state and storage handles. `Transaction` objects
hold read/write lock ownership while active and are controlled objects. Cursors
created by typed scans are bound to the transaction that created them; iteration
outside that transaction lifetime is invalid and returns `Transaction_Error` when
checked by operations.

## Null semantics

`Database.Values.Null` represents absence of a database value. Not-null columns
reject `Null`. Secondary indexes skip `Null` keys, including unique secondary
indexes, so multiple rows may have `Null` in a unique secondary indexed column.
Aggregates ignore `Null` except `Count_All`; grouping treats `Null` as a key;
ordering places `Null` last.

## Cursor API stabilization

`Database.Cursors` is the public terminology package for cursor lifetime rules.
Typed table cursors remain private to each `Database.Tables.Typed` instantiation,
but cursor ownership and validity are described by `Cursor_State` and converted
to `Database.Status.Result` through `To_Result`.

The stable rule is: a cursor belongs to the transaction that created it. It may
be advanced only while that transaction is active and while its snapshot remains
current.  A cursor that is used with the wrong transaction, after transaction
end, or without a current element returns a structured status result rather than
exposing cursor internals.
