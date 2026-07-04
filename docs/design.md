# Design Overview

`database` is an Ada-native relational storage engine whose public model is based
on explicit Ada APIs rather than SQL.

## Core Principles

- Ada API first
- no SQL and no parser
- no runtime reflection
- explicit schema metadata
- explicit typed row values
- explicit mapping functions for Ada record integration
- transaction-scoped reads and writes
- correctness and diagnosability before performance

## Layered Architecture

### Typed Data Model

The typed data model defines column types, row values, schema metadata, UUIDs,
date/time values, and richer type metadata.

### Storage

The storage layer is page-oriented and includes durable page handling, record
serialization, file I/O, heap-table storage, and free-list management.

### Transactions and Recovery

The transaction layer coordinates rollback journal behavior, WAL logging,
checkpointing, replay, MVCC visibility, and transaction isolation.

### Indexing

The index layer includes B+ tree indexes, secondary indexes, expression/partial
index metadata, and SPARK-oriented B+ tree invariant validation.

### Query and Optimization

Query packages provide Ada-native query construction, aggregates, ordering,
joins, logical plans, execution plans, optimizer diagnostics, statistics, and
plan selection.

### Advanced Relational Features

Advanced relational metadata covers foreign keys, check constraints, generated
columns, expressions, views, materialized views, and durable metadata persistence.

### Full-Text Search

Full-text packages provide tokenization, normalization, inverted-index metadata,
postings, ranking, query composition, compression, and segment support.

### Backup, Import, Export, and Encryption

The operational layer supports physical backup/restore, logical export/import,
encrypted artifacts, sidecar/manifest consistency, authenticated integrity
checks, and key metadata.

### Extensions

Extension packages support handle-owned scalar functions, aggregate functions,
collations, extension metadata, and dependency tracking.

### Observability

Tracing, metrics, profiling, events, diagnostics, and runtime diagnostics expose
operational state without intentionally leaking secret material.

### Hardening and Verification

Hardening packages include deterministic fault injection, crash/power-loss
simulation, invariant traversal, randomized workloads, stress workloads, fuzzing,
and SPARK-oriented analysis packages.

## SPARK-Oriented Subsets

The project contains isolated SPARK-mode packages for:

- checksums
- WAL frame parsing
- durable page parsing
- record serialization envelopes
- free-list management
- B+ tree invariant validation

These subsets are intentionally isolated from the full engine because the full
engine uses I/O, heap allocation, controlled types, and integration code that is
not intended to be fully converted to SPARK.
