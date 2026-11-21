# Transaction Semantics

All reads and writes are transaction-scoped.

## Transaction Modes

The engine distinguishes read-only and read-write transactions. Concurrent
readers are allowed while write coordination enforces the configured single
writer behavior.

## Tasks

A database handle may be shared by several tasks, but a write transaction is
used only by the task that began it: it holds the handle's write lock for that
task. A write through another task's transaction is refused with
`Invalid_Argument`.

Some operations write the database file directly instead of through a
transaction: a checkpoint, a physical backup, a catalog change made outside a
transaction, and `Close`. Each holds the write lock while it writes.

- A checkpoint or a backup is refused while another writer is active.
- `Close` is refused while any transaction or such operation is active; while it
  closes, new readers wait and a non-blocking read is refused, and a transaction
  that waited for the lock finds the database closed.
- A catalog change outside a transaction waits for the running writer, including
  another task's transaction, and is then written. Code that runs inside a
  checkpoint or backup, such as an event handler, gets `Transaction_Conflict`
  instead, since it would wait for itself.
- A task that holds the write lock gets `Transaction_Conflict` when it begins a
  write transaction, and the task closing a database gets it when it begins a
  read: this covers an event handler of a checkpoint, backup or close, and a
  task whose write transaction is still open.
- A task waiting for the write lock, for example in `Begin_Write`, can be
  aborted. Taking or releasing the lock and recording it cannot be separated by
  an abort, so an aborted transaction or operation always gives the lock back.

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
