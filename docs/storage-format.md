# Storage format

The storage format is intentionally documented for maintainability. It is not a
promise that applications should manipulate database files directly.

## File structure

A persistent database is a fixed-page file.

- Page size: 4096 bytes
- Page 0: database header
- Page 1: catalog metadata
- Page 2 and above: table heaps, B+ tree nodes, and free pages

All page ids are zero-based natural numbers. Page id 0 is reserved for the file
header and is never a user data root.

## File header

The header page identifies the file as a `database` file and stores the storage
format version. Opening a file validates the header before loading catalog
metadata. Invalid magic, unsupported version, truncated page data, or malformed
page headers return structured status failures.

## Page header

Every page carries:

- page id
- page kind
- next-page link where applicable
- used-payload byte count
- payload bytes

Header bytes 36 .. 39 hold a checksum: the sum of every other byte of the page.
Every page read from the file is verified against it.

The engine validates page id consistency, page kind consistency, used-payload
bounds, and page-chain reachability during integrity checks.

## Page kinds

- `Header_Page`
- `Catalog_Page`
- `Table_Heap_Page`
- `Free_Page`
- `BTree_Internal_Page`
- `BTree_Leaf_Page`

Unknown or inappropriate page kinds are corruption indicators.

## Heap layout

A table heap is a linked chain of heap pages. Rows are stored as serialized row
payloads with slot metadata. Deletions mark row locations unavailable.
Version-aware vacuum tombstones safely reclaimable deleted payloads while
preserving slot boundaries, and removes matching obsolete index candidates for
those reclaimed row references.

Integrity checks validate slot bounds, payload boundaries, deserialization, page
chain shape, and orphan pages.

## Row serialization

Rows are serialized as ordered database values. The format records value kind and
payload. Text values are stored as Unicode scalar data through the engine value
model; Ada record memory is never serialized. Decimal values are exact
coefficient/scale pairs.

The record format is fuzz-tested through deterministic round-trip tests.
Malformed data returns `Serialization_Error` or corruption status rather than
being treated as a valid row.

## Index layout

Primary and secondary indexes use B+ tree pages. Every index entry is one
(key, row reference) pair; entries are ordered by key and then by reference, so
equal keys of a non-unique index are adjacent and each entry is distinct. Leaf
pages (`BTree_Leaf_Page`) hold entries and link to their right sibling through
the page's next-page field. Internal pages (`BTree_Internal_Page`) hold a first
child and separators, each with the child that holds the entries at or above
it.

A node's payload starts with the marker `BPT1`, then the node type (0 leaf,
1 internal), the entry count (u16), and the first child (u32, internal nodes
only); then per entry the key length (u16), the key, the row reference page and
slot (u32 each), and for internal nodes the child page (u32). A key is its
value kind followed by a fixed big-endian encoding of the value; text and enum
keys are UTF-8. An encoded key holds at most 1,000 bytes, so every node holds at
least three entries; a longer key is rejected as `Row_Too_Large`.

The root page of an index never moves, so catalog references stay valid: when
the root splits, its two halves move to new pages and the root becomes their
parent. Nodes split when full and are not merged; a leaf emptied by deletes
stays in the tree. Every node is written through its transaction, so index
changes are logged in the WAL and rolled back with the transaction. Rebuilding
an index empties a sound tree in place: the root keeps its page and the other
pages become free pages. A tree that fails validation is replaced by a new root
instead, and its pages are left alone, because pages named by a corrupt tree
cannot be told apart from pages other structures use. The integrity check then
reports them as orphan pages until vacuum frees them: vacuum returns every table
heap and index page that no catalog root reaches to the free list, but only when
every heap chain and index tree can be followed to its end, since the pages
behind a broken link would otherwise look unreachable. Its report says how many
pages it freed, or that it freed none for that reason.

Pages a transaction allocates or frees are written through the transaction as
well. A rollback therefore returns a reused free page to the free list, removes
pages added at the end of the file, and restarts the allocator from the restored
file.

Earlier versions kept index entries in process memory and wrote nothing to the
root page they allocated. Such a root (a leaf page without the marker) is an
unbuilt index: lookups bypass it by scanning the table, and the next insert into
the table rebuilds it in place from the table rows. Earlier versions also kept
catalog changes when a transaction rolled back, so a file they wrote can name a
root whose page the rollback removed or reused; such a root is replaced by a new
one, which the catalog records.

Index validation checks that every node is readable, carries the marker, and
holds its entries in strictly ascending order; that every entry of a subtree
lies between the separators around it; that all leaves are at the same depth
and chained left to right; that no page is reached twice; and that the tree is
at most 64 levels high. Internal nodes are never merged and keep at least one
separator, so a real tree of 2^32 pages has at most 32 levels; a deeper path
comes from a corrupt file and is reported instead of followed. An unwritten
root is valid; any other root without the marker is corrupt. The integrity
check marks every index page as reachable. The SPARK model in
`Database.Indexes.BTree_Invariants` describes trees of integer keys with fixed
node limits and is proved separately; it does not describe stored trees.

Secondary indexes may be unique or non-unique. `Null` secondary keys are not
entered.

## Catalog storage

The catalog records table names, stable table ids, schema versions, stable column
ids, heap roots, primary index roots, and secondary index metadata. Schema
changes update catalog metadata transactionally.

While a write transaction is active, catalog changes are staged in memory. They
are checked to fit the page when they are made, and the commit writes the catalog
page through the transaction, so it is logged in the WAL, recovered after a crash,
and restored by a rollback like any other page; a rollback reloads the catalog
from its page. Only a database without an active writer, such as one being
created, opened, or closed, writes the catalog page directly. A table registered
in a write transaction gets its heap page through that transaction; registering a
table without one runs in a write transaction of its own.

## Write-ahead log

For a database file `app.db`, the WAL path is `app.db.wal`. The WAL contains append-only physical page frames, durable commit records, and checkpoint records. Page headers carry their last-applied LSN so replay and checkpoint can skip already-applied frames safely.

A transaction's first page write is preceded by a begin record holding the number
of pages the file had, and the first write to each page the file already had by an
undo record holding the page as it was. A transaction that rolls back restores its
pages from memory, cuts the file back, and appends an abort record. Record kinds:
page frame 1, commit 2, checkpoint 3, full-text redo 4, full-text undo 5, page undo
6, begin 7, abort 8.

## Recovery strategy

Opening a persistent database checks the WAL before loading catalog state. Recovery validates record structure, checksums, and LSN ordering, then replays only frames belonging to transactions with durable commit records. Truncated tails are treated as interrupted appends and ignored safely.

A transaction with neither a commit nor an abort record was interrupted, for
example by the process ending, and its page writes are already in the file.
Recovery undoes it: in log order it writes back the page images of its undo
records, stamped with their LSN so the frames of later committed transactions are
written over them again, and then cuts the file back to the length of its begin
record, unless a committed transaction wrote a page past it. It then appends an
abort record for the transaction, so a later replay of the same log leaves it
alone. Full-text undo records follow the same rule. Recovery reads the WAL twice,
once to learn how each transaction ended and once to apply its records, and the
first pass also yields the highest commit version, the committed transactions for
MVCC visibility, and the highest transaction id; new transaction ids start past
it, because replay tells transactions apart by id. A checkpoint replays the WAL
the same way and then finds the free pages and the end of the file again, since a
transaction whose rollback failed may have been undone.

## Versioning strategy

The file header carries a storage version. Future incompatible changes should
increase the version and provide explicit migration/open behavior. Applications
must not depend on undocumented byte offsets beyond this document and the source
implementation.

## Corruption detection

Corruption detection is defensive and explicit. The checker reports invalid
headers, invalid page kinds, malformed rows, invalid indexes, orphan pages, bad
free-list state, truncated files, and malformed WAL records through result records.

## WAL file format

A sidecar write-ahead log lives at `<database>.wal`. WAL records use a fixed-size header followed by an optional payload. Physical page-frame payloads contain serialized `Database.Storage.Pages.Page` values. Commit records contain the commit version. LSNs are monotonically increasing and page replay stores the latest applied 64-bit LSN in page metadata. The main file may lag behind the WAL until checkpointing replays committed frames.
