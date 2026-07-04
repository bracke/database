# MVCC

`database` uses snapshot-based multi-version concurrency control.
The library remains Ada-native and does not add SQL, a parser, reflection, or automatic Ada record persistence.

## Model

Each transaction receives:

- a transaction id
- a start/snapshot commit version
- a mode: read-only or read-write
- an end/commit version when it finishes

Rows are represented as versions. A row version has metadata describing the creating transaction, the version at which the row becomes visible, optional deletion metadata, and a link to a previous version when storage backends provide physical chains.

The centralized visibility predicate is `Database.Visibility.Is_Visible`.

## Snapshot semantics

A transaction sees:

- its own writes
- row versions whose create version is less than or equal to the transaction snapshot
- rows not deleted as of the transaction snapshot

A transaction does not see:

- uncommitted writes from other transactions
- committed versions newer than its snapshot
- rows deleted before or at its snapshot
- rollback-only versions whose future commit version never became the database commit version

Repeated reads in a transaction are stable with respect to committed data from other transactions. A reader that starts before a writer commits continues to read the old snapshot. A new reader that starts after the commit sees the new committed version.

## Concurrency rules

MVCC keeps the single-writer rule for correctness and recovery simplicity. This means:

- many read-only transactions may run concurrently
- one read-write transaction may run at a time
- readers do not block the writer
- the writer does not block readers
- a second writer receives `Transaction_Conflict`

Schema migrations, index rebuilds, and vacuum still require coordination beyond row visibility.

## Version lifecycle

1. Insert creates a new future-visible row version owned by the writer transaction.
2. Update logically deletes the old visible version at the writer future version and appends a replacement version.
3. Delete marks the visible version deleted at the writer future version.
4. Commit advances the database commit version, making future versions visible to later snapshots.
5. Rollback does not advance the database commit version; future versions remain invisible and delete markers remain beyond all valid snapshots.
6. Vacuum may reclaim versions only when no active snapshot can see them.

## Vacuum reclaim rule

`Database.MVCC.Oldest_Active_Snapshot` tracks active transaction snapshots. A version is reclaim-safe only if its obsolete/delete version is older than the oldest active snapshot. If no snapshots are active, obsolete committed versions may be reclaimed.

## Index semantics

Indexes may point to candidate row versions. Index lookup is not sufficient by itself; every candidate must be filtered through `Database.Visibility.Is_Visible` before it is returned. Unique checks consider versions visible to the writing transaction snapshot plus the writer's own writes.

## Recovery and WAL interaction

WAL is the durability mechanism. Version metadata is logged with the pages that contain row/index changes. Recovery replays committed frames and ignores incomplete transactions. Partially written metadata must never expose uncommitted versions after open/recovery.

## Limitations

- single writer still enforced
- no distributed MVCC
- no replication
- no SQL
- no parser
- no automatic record persistence

## Implementation Notes

The MVCC implementation uses transaction-lifecycle tracking in `Database.MVCC`
so in-memory row versions created or deleted by rolled-back transactions remain
invisible even after later unrelated commits advance the global commit version.
Persistent indexes are treated as candidate locators: primary and secondary
index entries may reference multiple older row versions, and table
operations perform a heap visibility check after index lookup before returning
rows or enforcing uniqueness. Deletes are logical MVCC deletes; index entries
are preserved until a future version-aware vacuum can safely remove obsolete
candidates.

Rollback semantics are intentionally conservative. Persistent rollback uses transaction-local before-images for the active process; durability is governed by WAL commit records. In-memory rollback is enforced by visibility rules over transaction lifecycle state. Vacuum/check integration validates MVCC slot metadata and must never reclaim a version whose create/delete version can still be seen by an active snapshot.
