# SPARK Analysis for Durable Page Parsing

`Database.Storage.Page_Parser` isolates durable page parsing and checksum
validation in a SPARK-mode package.

## Scope

The package is marked:

```ada
with SPARK_Mode => On
```

It validates a bounded durable page layout:

- magic bytes
- format version
- page kind
- reserved bytes
- page id
- previous/next page links
- used payload length
- page LSN
- payload checksum
- header checksum
- payload bytes

## Verification-Oriented Properties

The parser has:
- no global state
- explicit `Depends` contracts
- bounded payload size
- explicit status results
- no exception-based ordinary parse failure
- postcondition guaranteeing a well-formed header on `Parse_OK`
- checksum validation through `Database.Checksums`

## Failure Modes

The parser rejects:
- short pages
- invalid magic
- unsupported page format
- invalid reserved bytes
- unknown page kinds
- zero page ids
- direct self-linkage
- stale page LSNs
- excessive/truncated used payload length
- header checksum mismatch
- payload checksum mismatch

## Expected GNATprove Command

When GNATprove is available:

```sh
gnatprove -P spark_page_parser.gpr --level=2
```

For a deeper run:

```sh
gnatprove -P spark_page_parser.gpr --level=4
```

## Integration Policy

The storage `File_IO` and recovery layers should validate durable page bytes with
this parser before accepting a page as structurally valid. Higher-level packages
remain responsible for semantic invariants such as B+ tree ordering, MVCC chains,
catalog references, and free-list reachability.

## Test Coverage

AUnit tests cover:
- valid page parsing
- short page rejection
- magic rejection
- zero page id rejection
- self-link rejection
- stale page LSN rejection
- header tamper rejection
- payload tamper rejection
