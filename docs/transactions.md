# Transactions

All user-visible reads and writes go through `Database.Transactions.Transaction`.

## Lifecycle

A transaction begins in `Active` state and ends as `Committed`, `Rolled_Back`, or
`Failed`.

- `Begin_Read` starts a read-only transaction.
- `Begin_Write` starts a read-write transaction.
- `Try_Begin_Read` and `Try_Begin_Write` return `Granted` instead of blocking.

`Commit` and `Rollback` are available as functions returning
`Database.Status.Result` and as procedures that store the result in the
transaction object.

## RAII semantics

`Transaction` is a controlled limited type. If an active transaction is finalized
without an explicit commit or rollback, finalization rolls it back. This protects
against accidental uncommitted writes escaping a scope.

## Read-only vs read-write

Read-only transactions may perform finds, scans, query execution, integrity
checks, and diagnostics. They may not register tables through transaction-aware
write APIs, insert, update, delete, create indexes, rebuild indexes, run
migrations, or vacuum. Such attempts return `Read_Only_Transaction` or a related
structured failure.

Read-write transactions hold the writer lock and may modify catalog, heap,
indexes, and storage.

## Isolation model

The implementation uses snapshot-based MVCC with one writer and multiple
non-blocking readers inside an open handle. A reader sees committed versions at
or below its snapshot version plus its own writes. It does not see uncommitted
writes from other transactions, committed versions newer than its snapshot, or
deletes committed at or before its snapshot.

Persistent `Create`, `Open`, and `Open_Encrypted` acquire an exclusive
process-level advisory lock on the database carrier file. A second process that
tries to open the same persistent database receives `Lock_Error` instead of
racing WAL replay, checkpoint, or file writes. The lock is released by
`Database.Close` and by the operating system if the process exits. In-memory
databases keep the in-process lock model only.

## Commit guarantees

A successful persistent commit means the engine has appended physical WAL page frames, appended a commit record, flushed the Ada stream buffer, and called POSIX `fsync` on the WAL file before advancing the durable LSN. The main database file may lag until checkpoint; checkpoint flushes and `fsync`s the carrier file before removing the WAL. File creation, WAL removal, and rewrite/rename paths also sync the parent directory.

The durability contract assumes a local POSIX filesystem and storage stack that honor `fsync` and directory `fsync`. The engine cannot force disk controllers, virtualized storage, network filesystems, or mount options that acknowledge barriers without actually preserving the bytes.

## Rollback guarantees

Rollback restores before-images for overwritten pages and truncates pages
allocated after the transaction began. Rollback is automatic on finalization for
active transactions.

## Recovery semantics

Opening a persistent database runs WAL replay before loading the catalog. Committed frames are replayed in LSN order. Incomplete transactions are ignored. Malformed WAL state is reported explicitly.

## Cursor lifetime

Typed table cursors are bound to the transaction id and snapshot that produced
them. Iterating a cursor after commit, rollback, or under another transaction is
invalid and is rejected by transaction-aware cursor operations.


## Cursor lifetime API

`Database.Cursors` defines the shared cursor state vocabulary used by public
scan APIs.  Table cursors are private, but their lifetime is not implicit:
`Valid` means the cursor has a current element and belongs to the active
transaction; `No_Element`, `Wrong_Transaction`, `Expired_Snapshot`, and
`Closed_Transaction` explain why reading or advancing is invalid.

## MVCC

Snapshot-based MVCC gives read-only transactions a stable snapshot and keeps them from blocking the single writer. The writer remains exclusive against other writers, but readers can continue during writes and keep seeing their original committed snapshot. Row visibility is centralized in `Database.Visibility`, row version metadata is defined in `Database.Versioning`, and active snapshot tracking for safe cleanup is provided by `Database.MVCC`. See `docs/mvcc.md` for the detailed visibility algorithm, version lifecycle, vacuum rules, index semantics, and limitations.

## WAL commit durability

Persistent read-write transactions append physical WAL page frames and then a durable commit record. A transaction is considered committed only after the WAL commit record has been flushed and `fsync` has completed successfully. Recovery ignores frames for transactions that do not have a durable commit record. WAL is the persistent transaction mode.
