# Write-Ahead Logging

WAL is the persistence mode for durable transactions. Persistent write paths append physical page frames to `database-file.wal` before commit durability is acknowledged.

## File lifecycle

For a database file named `app.db`, the WAL file is `app.db.wal`.

The WAL is append-only. Records are assigned monotonically increasing log sequence numbers (LSNs). A committed transaction is durable only after its commit record has been appended, stream-flushed, and `fsync`ed. Main database pages may lag behind the WAL until checkpointing applies committed frames back to the database file.

## Record model

WAL uses physical page logging. Each WAL record has a fixed header and an optional payload.

Header fields:

- magic/version marker
- record kind
- LSN
- transaction id
- page id
- page kind
- payload length
- header size
- checksum

Record kinds:

- page frame
- commit record
- checkpoint record
- full-text redo record
- full-text undo record

Page-frame payloads contain the serialized database page. Commit-record payloads contain the assigned commit version. Checkpoint records are reserved for explicit checkpoint boundaries. Full-text redo and undo records contain serialized full-text dictionary or posting pages only. Recovery applies committed full-text redo images and uncommitted full-text undo images, and rejects full-text WAL records whose payload is not a full-text page.

## Commit sequence

A read-write transaction follows this durability sequence:

1. write physical page frames to the WAL before the corresponding page is considered durable
2. append the commit record
3. flush the WAL stream and `fsync` the WAL file
4. mark the transaction committed in memory
5. checkpoint later merges committed page frames into the main database file

A transaction is committed if and only if its commit record is durable in the WAL. Incomplete transactions are ignored during replay.

## Replay algorithm

Recovery scans the WAL in LSN order. The first pass validates structure, checksums, and LSN monotonicity, and records transaction ids that have durable commit records. The second pass applies page frames only for committed transaction ids. Truncated tails are treated as interrupted appends and ignored safely; corrupted complete records are reported as WAL corruption.

Replay updates page LSN metadata before writing the page to the database file. If a page already carries an equal or newer Last_LSN, replay skips that frame so repeated replay/checkpoint passes are idempotent.

## Checkpoint algorithm

Checkpointing replays committed WAL frames into the main database file, flushes and `fsync`s the database file, and removes the WAL only when no active readers require the old snapshot horizon. File creation, WAL deletion, and rewrite/rename operations sync the parent directory so directory entries reach the filesystem durability boundary too. If readers are active, the WAL is preserved and can be replayed again later.

Supported checkpoint modes are:

- passive
- full
- forced

The current implementation exposes the mode in the API and uses one safe merge algorithm for all three modes.

## MVCC interaction

WAL replay restores durable physical pages, including row version metadata stored in those pages. Snapshot isolation remains coordinated by the MVCC and visibility layers. Checkpoint and vacuum must respect active snapshots: vacuum may not reclaim versions that are still visible to any active snapshot or required by replay/checkpoint safety.

## Crash safety guarantees

- committed WAL frames are replayed
- frames without a durable commit record are ignored
- invalid checksums are detected
- LSN ordering violations are detected
- a crash after commit but before checkpoint is recovered by replay
- a crash during checkpoint is recovered by replaying the remaining WAL again
- successful commit, checkpoint, create/delete, and rewrite/rename paths issue file or directory `fsync` calls before acknowledging completion

## Limitations

- The engine API is the supported query interface.
- SQL text parsing is outside the WAL layer scope.
- there is no replication
- there is no distributed WAL or consensus
- only one active writer is still enforced
- compressed WAL frames are future work
- real power-loss behavior still depends on the local filesystem, mount options, storage controller, and hardware honoring `fsync` and directory `fsync`
