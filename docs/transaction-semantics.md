# Transaction Semantics

All reads and writes are transaction-scoped.

## Transaction Modes

The engine distinguishes read-only and read-write transactions. Concurrent
readers are allowed while write coordination enforces the configured single
writer behavior.

## MVCC

MVCC packages provide stable snapshots and visibility decisions. Version chains
are checked by visibility and invariant-checking code.

## Durability

Durability is based on WAL/replay and checkpointing. Recovery validates durable
artifacts and replays committed work deterministically.

## Failure Handling

Ordinary corruption, replay inconsistency, and validation failures are reported
with explicit status results. Exceptions are not used for ordinary corruption
detection.
