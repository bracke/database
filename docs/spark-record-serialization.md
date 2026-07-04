# SPARK Analysis for Record Serialization

`Database.Storage.Record_Serializer` isolates deterministic low-level record
serialization in a SPARK-mode package.

## Scope

The package is marked:

```ada
with SPARK_Mode => On
```

It validates and builds a bounded record envelope:

- magic bytes
- format version
- field count
- reserved bytes
- payload length
- field directory
- payload bytes

The package does not encode high-level database values. It provides a verified
serialization envelope used below `Database.Storage.Record_Format`.

## Verification-Oriented Properties

The serializer has:
- no global state
- explicit `Depends` contracts
- bounded field count
- bounded payload length
- explicit status results
- no exception-based ordinary parse failure
- postcondition guaranteeing a well-formed header on successful parse
- directory validation for field bounds and field ordering

## Failure Modes

The parser/builder rejects:
- short records
- invalid magic
- unsupported format version
- invalid reserved bytes
- excessive field count
- excessive payload length
- truncated field directories
- truncated payloads
- field spans outside payload bounds
- out-of-order or overlapping fields
- undersized output buffers

## Expected GNATprove Command

When GNATprove is available:

```sh
gnatprove -P spark_record_serializer.gpr --level=2
```

For deeper proof attempts:

```sh
gnatprove -P spark_record_serializer.gpr --level=4
```

## Integration Policy

`Database.Storage.Record_Format` should use this package as the deterministic
binary envelope for serialized row records. High-level type encoding remains
outside this SPARK subset, while the byte envelope and field directory checks
remain proof-oriented and bounded.

## Test Coverage

AUnit tests cover:
- deterministic build/parse round trip
- bad magic rejection
- reserved byte rejection
- truncated directory rejection
- field bounds rejection
- field order rejection
- small output buffer rejection
