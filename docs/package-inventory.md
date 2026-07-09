# Package Inventory

Current source packages grouped by subsystem.


## Advanced Relational Features

- `Database.Check_Constraints` — `src/database-check_constraints.ads`
- `Database.Expressions` — `src/database-expressions.ads`
- `Database.Foreign_Keys` — `src/database-foreign_keys.ads`
- `Database.Generated_Columns` — `src/database-generated_columns.ads`
- `Database.Materialized_Views` — `src/database-materialized_views.ads`
- `Database.Views` — `src/database-views.ads`

## Backup, Restore, Import, Export

- `Database.Backup` — `src/database-backup.ads`
- `Database.Backup_Format` — `src/database-backup_format.ads`
- `Database.Export` — `src/database-export.ads`
- `Database.Import` — `src/database-import.ads`
- `Database.Restore` — `src/database-restore.ads`

## Core

- `Database` — `src/database.ads`
- `Database.Catalog` — `src/database-catalog.ads`
- `Database.Check` — `src/database-check.ads`
- `Database.Checksums` — `src/database-checksums.ads`
- `Database.Constraints` — `src/database-constraints.ads`
- `Database.Cursors` — `src/database-cursors.ads`
- `Database.Migrations` — `src/database-migrations.ads`
- `Database.Optional` — `src/database-optional.ads`
- `Database.Predicates` — `src/database-predicates.ads`
- `Database.Status` — `src/database-status.ads`
- `Database.Storage` — `src/database-storage.ads`
- `Database.Tables` — `src/database-tables.ads`
- `Database.Vacuum` — `src/database-vacuum.ads`
- `Database.Validation_Hooks` — `src/database-validation_hooks.ads`

## Command-Line Subcrates

- `Database.Inspect` — `database_inspect/src/database-inspect.ads`
- `database_inspect` — `database_inspect/src/database_inspect.adb`
- `database_inspect_make_encrypted_fixture` — `database_inspect/src/database_inspect_make_encrypted_fixture.adb`

## Encryption

Encryption primitives are provided by the sibling `../cryptolib` crate; the
database packages below own the storage-facing contracts and artifact metadata.

- `Database.Crypto` — `src/database-crypto.ads`
- `Database.Crypto_Checks` — `src/database-crypto_checks.ads`
- `Database.Encrypted_Persistence` — `src/database-encrypted_persistence.ads`
- `Database.Encryption` — `src/database-encryption.ads`
- `Database.Keys` — `src/database-keys.ads`

## Extensions

- `Database.Aggregate_Functions` — `src/database-aggregate_functions.ads`
- `Database.Collations` — `src/database-collations.ads`
- `Database.Extension_Metadata` — `src/database-extension_metadata.ads`
- `Database.Extensions` — `src/database-extensions.ads`
- `Database.Functions` — `src/database-functions.ads`

## Full-Text Search

- `Database.Full_Text` — `src/database-full_text.ads`
- `Database.Full_Text.Compression` — `src/database-full_text-compression.ads`
- `Database.Full_Text.Indexes` — `src/database-full_text-indexes.ads`
- `Database.Full_Text.Normalization` — `src/database-full_text-normalization.ads`
- `Database.Full_Text.Postings` — `src/database-full_text-postings.ads`
- `Database.Full_Text.Queries` — `src/database-full_text-queries.ads`
- `Database.Full_Text.Ranking` — `src/database-full_text-ranking.ads`
- `Database.Full_Text.Segments` — `src/database-full_text-segments.ads`
- `Database.Full_Text.Snippets` — `src/database-full_text-snippets.ads`
- `Database.Full_Text.Storage` — `src/database-full_text-storage.ads`
- `Database.Full_Text.Tokenizers` — `src/database-full_text-tokenizers.ads`

## Hardening

- `Database.Crash_Harness` — `src/database-crash_harness.ads`
- `Database.Fault_Hooks` — `src/database-fault_hooks.ads`
- `Database.Fault_Injection` — `src/database-fault_injection.ads`
- `Database.Fuzzing` — `src/database-fuzzing.ads`
- `Database.Invariant_Checks` — `src/database-invariant_checks.ads`
- `Database.Randomized` — `src/database-randomized.ads`
- `Database.Stress` — `src/database-stress.ads`
- `Database.Testing` — `src/database-testing.ads`

## Indexes

- `Database.Indexes` — `src/database-indexes.ads`
- `Database.Indexes.BTree` — `src/database-indexes-btree.ads`
- `Database.Indexes.BTree_Invariants` — `src/database-indexes-btree_invariants.ads`

## Observability

- `Database.Diagnostics` — `src/database-diagnostics.ads`
- `Database.Diagnostics.Runtime` — `src/database-diagnostics-runtime.ads`
- `Database.Events` — `src/database-events.ads`
- `Database.Metrics` — `src/database-metrics.ads`
- `Database.Profiling` — `src/database-profiling.ads`
- `Database.Tracing` — `src/database-tracing.ads`

## Query and Optimization

- `Database.Aggregates` — `src/database-aggregates.ads`
- `Database.Execution_Plans` — `src/database-execution_plans.ads`
- `Database.Joins` — `src/database-joins.ads`
- `Database.Optimizer` — `src/database-optimizer.ads`
- `Database.Ordering` — `src/database-ordering.ads`
- `Database.Plans` — `src/database-plans.ads`
- `Database.Queries` — `src/database-queries.ads`
- `Database.Statistics` — `src/database-statistics.ads`

## Storage

- `Database.Storage.File_IO` — `src/database-storage-file_io.ads`
- `Database.Storage.Free_List` — `src/database-storage-free_list.ads`
- `Database.Storage.Free_List_Manager` — `src/database-storage-free_list_manager.ads`
- `Database.Storage.Page_Parser` — `src/database-storage-page_parser.ads`
- `Database.Storage.Pages` — `src/database-storage-pages.ads`
- `Database.Storage.Record_Format` — `src/database-storage-record_format.ads`
- `Database.Storage.Record_Serializer` — `src/database-storage-record_serializer.ads`
- `Database.Storage.Table_Heap` — `src/database-storage-table_heap.ads`

## Transactions and MVCC

- `Database.Locking` — `src/database-locking.ads`
- `Database.MVCC` — `src/database-mvcc.ads`
- `Database.Transactions` — `src/database-transactions.ads`
- `Database.Versioning` — `src/database-versioning.ads`
- `Database.Visibility` — `src/database-visibility.ads`

## Typed Data Model

- `Database.Date_Time` — `src/database-date_time.ads`
- `Database.Rows` — `src/database-rows.ads`
- `Database.Schema` — `src/database-schema.ads`
- `Database.Type_Metadata` — `src/database-type_metadata.ads`
- `Database.Types` — `src/database-types.ads`
- `Database.UUIDs` — `src/database-uuids.ads`
- `Database.Values` — `src/database-values.ads`

## WAL and Recovery

- `Database.Checkpointing` — `src/database-checkpointing.ads`
- `Database.Log_Sequence` — `src/database-log_sequence.ads`
- `Database.Replay` — `src/database-replay.ads`
- `Database.WAL` — `src/database-wal.ads`
- `Database.WAL.Frame_Parser` — `src/database-wal-frame_parser.ads`
