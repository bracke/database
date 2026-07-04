# Observability

`database` provides in-process operational visibility through Ada-native APIs.
It does not provide SQL, a parser, distributed tracing, a network telemetry
agent, or an external monitoring-stack dependency.

## Tracing

`Database.Tracing` emits structured `Trace_Event` records. Categories are:

- `Transaction_Trace`
- `WAL_Trace`
- `Query_Trace`
- `Storage_Trace`
- `Optimizer_Trace`
- `Locking_Trace`
- `Backup_Trace`
- `Encryption_Trace`
- `Integrity_Trace`
- `Extension_Trace`

Tracing is disabled by default. Call `Enable` to collect events. Category filters
can be changed with `Enable_Category` and `Disable_Category`. Events are retained
in a bounded in-memory buffer and can also be delivered to console, file, or
custom sinks.

Sensitive trace messages are redacted by default. Use sensitive traces only for
controlled local debugging. Plaintext encryption keys, decrypted page dumps, and
secret-derived values must not be intentionally emitted.

## Metrics

`Database.Metrics.Snapshot_Metrics` returns a deterministic process-local
snapshot. Metrics include transaction counts, WAL bytes and flush counts,
checkpoint counts and duration fields, page reads/writes, cache hits/misses,
index lookups, optimizer plan counts, heap-scan fallback counts, query execution
counts, rows scanned/returned, full-text query counts, backup/restore counts,
import/export counts, encryption operation counts, extension invocation counts,
lock waits, blocked operations, integrity checks, and validation failures.

`Reset_Metrics` clears counters for deterministic tests.

## Profiling

`Database.Profiling.Profile_Query` produces a `Query_Profile` for an Ada-native
`Database.Queries.Query`. The profile contains logical plan text, physical plan
text, optimizer decision text, aggregate row counts, cost/timing fields, and a
vector of operator profiles.

Profiling reports runtime behavior but does not change query semantics.

## Events

`Database.Events` supports synchronous operational hooks for lifecycle events:
transaction begin/commit/rollback, checkpoint start/end, backup start/end,
restore completion, integrity-check failure, WAL replay start/end, extension
registration, and encryption key rotation.

Handlers are isolated. A failing handler returns `Event_Handler_Error` from the
status-returning dispatch API and must not corrupt database state.

## Runtime diagnostics

`Database.Diagnostics.Runtime` exposes live snapshots:

- `Active_Transactions`
- `Active_Snapshots`
- `WAL_State`
- `Checkpoint_State`
- `Cache_Statistics`
- `Lock_Statistics`

These APIs are inspection-only and must not mutate storage, transaction state,
MVCC visibility, locks, WAL state, or schema metadata.

## Security and privacy

The default tracing configuration is conservative. Sensitive traces are disabled
and redacted. Observability APIs must not expose plaintext encryption keys,
decrypted page contents, or secret-derived metadata. Operational diagnostics
should describe state, counts, and lifecycle transitions rather than raw sensitive
payloads.

## Limitations

The observability layer is local to the process. It does not ship events to a
remote service, does not implement distributed tracing, and does not dynamically
inject instrumentation into user extensions.
