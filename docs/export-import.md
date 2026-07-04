# Logical export and import

`database` provides database-native logical export/import. The format is not SQL and
contains no parser-facing text. It serializes logical catalog metadata and row
values, not database pages and not Ada record memory layout.

## Export format

The current format is a binary stream:

1. UTF-32BE magic text: `DATABASE_LOGICAL_EXPORT_26`
2. format version: unsigned 32-bit integer, currently `20`
3. table count
4. for each table:
   - logical table schema: table id, schema version, next column id, table name,
     columns, primary-key column ids, and logical index metadata
   - visible row count for the export transaction snapshot
   - each row as typed values

Values are serialized with explicit type tags:

- null
- boolean
- integer
- long integer
- float image
- exact decimal coefficient and scale
- Unicode text as UTF-32BE code points
- blob bytes with byte length
- timestamp fields
- enum text

The format deliberately excludes physical heap page numbers and B+ tree root page
numbers. Import allocates new heap pages and rebuilds primary/secondary index
roots in the destination database.

## Snapshot semantics

`Database.Export.Export_Database` requires an active read transaction. Heap scans
use MVCC-aware visibility, so the export contains only rows visible to that
transaction snapshot. Uncommitted rows and commits after the snapshot are not
exported.

## Import algorithm

`Database.Import.Import_Database` requires an active write transaction on a
persistent destination database. Import validates the binary header and version,
clears transient full-text state, registers exported schemas, appends logical rows
through the table heap, rebuilds primary-key indexes and exported secondary index
metadata, registers rows for integrity checks, saves the catalog, flushes storage,
and optionally runs `Database.Check`.

The import format is intended for new or empty destination databases. It rejects
malformed headers and malformed row/value payloads with `Import_Error` rather
than exceptions for ordinary failures.

## Round-trip guarantees

The logical stream preserves Unicode text, exact Decimal coefficient/scale pairs,
Blob bytes, timestamp fields, schema column ids, schema versions, primary-key
column metadata, and index metadata needed to rebuild indexes.

## Limitations

- No SQL dumps are produced or accepted.
- No SQL parser is introduced.
- Full-text posting caches are rebuildable operational state; durable full-text
  definitions are catalog metadata.
- Replication is still out of scope.

## View body export/import

Logical export/import writes the persistent query image for every view and materialized view. The image stores the actual query row body using the same typed value model as rows: Unicode text, blobs, UUIDs, date/time values, decimals, enums, arrays, booleans, numeric values, and NULL are round-tripped explicitly. Import rejects malformed query images instead of silently replacing a view body with an empty query.
