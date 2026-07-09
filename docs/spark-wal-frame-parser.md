# SPARK Analysis for WAL Frame Parsing

`Database.WAL.Frame_Parser` isolates WAL frame parsing and validation in a
SPARK-mode package.

## Scope

The package is marked:

```ada
with SPARK_Mode => On
```

It validates a bounded, explicit WAL frame layout:

- magic bytes
- format version
- frame kind
- reserved bytes
- LSN
- previous LSN
- page id
- payload length
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
- short frames
- invalid magic
- unsupported format version
- invalid reserved bytes
- unknown frame kinds
- excessive/truncated payload lengths
- header checksum mismatch
- payload checksum mismatch
- previous-LSN ordering violations

## Expected GNATprove Command

When GNATprove is available:

```sh
alr exec -- gnatprove -P spark_wal_frame_parser.gpr --level=2
```

For deeper proof attempts:

```sh
alr exec -- gnatprove -P spark_wal_frame_parser.gpr --level=4
```

## Integration Policy

The full WAL replay layer should use this parser before applying any frame to
database state. Parsing remains separate from replay side effects so the parser
can stay SPARK-friendly and deterministic.

## Test Coverage

AUnit tests cover:
- valid frame parsing
- short frame rejection
- magic rejection
- LSN ordering rejection
- header tamper rejection
- payload tamper rejection
