# Query Optimizer

`database` has an Ada-native query optimizer. It does not parse SQL and it does not introduce a string query language. Query meaning is represented by typed logical plan nodes and is lowered to physical execution plan nodes under transaction scope.

## Logical and physical plans

`Database.Plans` represents logical operations: table scan, filter, project, order, limit, offset, aggregate, group, and inner join. Logical plans preserve semantics and carry typed predicate, aggregate, ordering, index, and statistics metadata.

`Database.Execution_Plans` represents implementation choices: heap scan, index lookup, index range scan, filter, projection, sort, limit, aggregate, hash group, nested loop join, index nested loop join, and materialization. `Explain` returns stable diagnostic text; an empty physical plan explains as `<empty physical plan>`.

## Optimizer rules

`Database.Optimizer.Optimize` is deterministic and correctness-first. If a rule cannot be proven safe, the optimizer emits a conservative plan.

Implemented rules:

- equality predicate on an indexed column uses `Index_Lookup`;
- range predicate on an indexed column uses `Index_Range_Scan`;
- `and` predicates are inspected for a usable indexed conjunct and keep a residual `Filter` when required;
- unindexed predicates use `Heap_Scan` plus `Filter`;
- ascending order on an indexed column eliminates a materialized sort;
- descending order falls back to `Sort` unless reverse scan support is added later;
- projection emits a pruning boundary so unused columns do not have to be carried through materialized pipelines;
- joins default to safe nested-loop execution and may use an index nested-loop plan when the declared inner join column is indexed;
- aggregates use the normal aggregate node unless an exact shortcut is available through metadata.

## Physical execution integration

Typed table scans remain transaction-scoped. Persistent scans now inspect structural predicates and use existing B+ tree indexes for equality and range access when safe. The index path reads row references from the B+ tree, fetches rows from the table heap, and rechecks the original predicate before yielding rows. This preserves NULL, duplicate secondary key, rollback/recovery, and cursor lifetime semantics.

Unoptimized heap scan remains the fallback path.

## Statistics

`Database.Statistics` exposes optimizer-facing table and index statistics using exact counters from `Database.Diagnostics` where available:

- table row count;
- table page count;
- index page count;
- index depth;
- unique/non-unique flag.

`Analyze` and `Analyze_Table` are public synchronization points. The maintained counters are exact enough for the rule-based optimizer, so analyze does not rewrite data pages.

## Limitations

The optimizer is deliberately conservative. It does not implement SQL-style text explain, parser-driven rewrites, arbitrary outer join reordering, reverse index scans, histogram selectivity, or adaptive runtime optimization. Unsupported optimizations are not unsupported queries; the engine falls back to correct heap/materialized execution.

## MVCC

Snapshot-based MVCC gives read-only transactions a stable snapshot and keeps them from blocking the single writer. The writer remains exclusive against other writers, but readers can continue during writes and keep seeing their original committed snapshot. Row visibility is centralized in `Database.Visibility`, row version metadata is defined in `Database.Versioning`, and active snapshot tracking for safe cleanup is provided by `Database.MVCC`. See `docs/mvcc.md` for the detailed visibility algorithm, version lifecycle, vacuum rules, index semantics, and limitations.
