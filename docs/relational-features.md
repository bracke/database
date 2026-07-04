# Relational features

`database` is not a SQL database. Relational features are defined and consumed through Ada APIs only.

## Expressions

`Database.Expressions` provides deterministic expression trees. Expressions can reference columns by stable column id, evaluate literals, perform integer arithmetic, compare values, combine boolean terms, test `NULL`, and call a fixed set of deterministic functions. These expressions are used by check constraints, generated columns, partial indexes, expression indexes, views, and materialized views.

No expression may perform I/O, inspect wall-clock time, mutate external state, or depend on process-global non-determinism.

## Foreign keys

`Database.Foreign_Keys.Foreign_Key_Definition` stores the referencing table, referenced table, referencing column ids, referenced column ids, delete action, update action, and whether enforcement is deferred.

Rules:

- referencing and referenced column vectors must have the same non-zero arity
- referenced columns must form a primary-key or unique identity in the schema/index layer
- corresponding value kinds must match
- if any referencing column is `NULL`, the foreign-key check succeeds without probing the parent table
- non-null referencing keys must match a visible parent row
- immediate constraints are checked during row mutation
- deferred constraints are checked at commit and ordinary failure rolls back the transaction

Supported actions are `Restrict`, `Cascade`, and `Set_Null`. `Set_Default` is intentionally not part of the current API.

## Composite keys and indexes

Composite keys are ordered lexicographically. The first unequal part determines the key order. Composite primary keys and unique composite indexes reject `NULL` parts. Composite secondary indexes may use the same ordering model for equality and range scans.

## Check constraints

Check constraints are row-level deterministic boolean expressions. A row is accepted only when the expression evaluates to `True`. A false expression returns `Constraint_Error`; expression type errors return an ordinary status failure.

## Generated columns

Stored generated columns are persisted physically as normal row values. Insert and update paths must recompute them before validation and persistence. `Validate_Stored` detects stale stored generated values during integrity checks.

Virtual generated columns are represented by the API type but are not persisted by the storage path.

## Partial indexes

A partial index contains only rows for which its deterministic predicate evaluates to `True`. Rows outside the predicate are excluded. Optimizer selection is conservative: if predicate implication is uncertain, the optimizer must not use the partial index.

## Expression indexes

An expression index stores a deterministic expression result rather than a raw column value. The expression must be stable for the row contents and must be maintained transactionally during inserts, updates, deletes, WAL replay, and MVCC vacuum.

## Views

Logical views are read-only query-backed relations. They are expanded during planning and evaluated under the caller's transaction snapshot. Nested view support is allowed when expansion can be proven acyclic.

## Materialized views

Materialized views store a persisted snapshot of a query result. The implementation uses full refresh only. Refresh requires a write transaction and must be WAL/MVCC safe.

## MVCC and WAL interaction

All enforcement must use transaction-scoped operations. Foreign-key probes, cascade updates, generated-column recomputation, partial/expression index maintenance, and materialized-view refreshes must observe the active transaction snapshot and write through WAL-backed mutation paths.

## Limitations

- no SQL syntax
- no parser
- no runtime reflection
- no non-deterministic generated columns or expression indexes
- no updatable views
- no incremental materialized-view refresh

## Implementation integration pass

Relational metadata is registered through `Database.Catalog` rather than SQL DDL. The table mutation path consults this metadata:

- stored generated columns are recomputed before ordinary row validation;
- registered check constraints are evaluated before insertion/update succeeds;
- immediate foreign keys are checked against transaction-visible parent rows;
- referenced-row delete actions are evaluated before the referenced row is marked deleted;
- composite, partial, and expression index definitions are stored as index metadata for optimizer and maintenance use.

Deferred constraints are represented in metadata and are skipped by immediate mutation checks. Commit-time deferred validation is the intended enforcement boundary; callers should register deferred constraints only when the transaction layer has been wired to validate the pending transaction set before durable commit.

No SQL parser is introduced. All definitions remain Ada-native values.
