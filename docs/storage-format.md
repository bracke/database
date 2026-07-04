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
payloads with slot metadata. Deletions mark row locations unavailable; vacuum can
rewrite reachable rows into compacted heap pages.

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

Primary and secondary indexes use B+ tree pages. Leaf nodes map keys to row
references. Internal nodes route by sorted keys. Index validation checks key
ordering, key support, row references, root reachability, and page kind
correctness.

Secondary indexes may be unique or non-unique. `Null` secondary keys are not
entered.

## Catalog storage

The catalog records table names, stable table ids, schema versions, stable column
ids, heap roots, primary index roots, and secondary index metadata. Schema
changes update catalog metadata transactionally.

## Write-ahead log

For a database file `app.db`, the WAL path is `app.db.wal`. The WAL contains append-only physical page frames, durable commit records, and checkpoint records. Page headers carry their last-applied LSN so replay and checkpoint can skip already-applied frames safely.

## Recovery strategy

Opening a persistent database checks the WAL before loading catalog state. Recovery validates record structure, checksums, and LSN ordering, then replays only frames belonging to transactions with durable commit records. Truncated tails are treated as interrupted appends and ignored safely.

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
