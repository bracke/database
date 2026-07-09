# SPARK-Oriented Verification

The project uses SPARK selectively. It does not attempt to convert the entire
database engine to SPARK.

The `spark_stubs/` directory contains proof-only parent namespace specs used by
the dedicated `spark_*.gpr` projects. Those stubs keep GNATprove focused on the
selected deterministic slices instead of pulling in the full database handle API.

## Included SPARK-Mode Packages

- `Database.Checksums`
- `Database.Log_Sequence.Rules`
- `Database.WAL.Frame_Parser`
- `Database.WAL.Payload_Rules`
- `Database.Storage.Page_Parser`
- `Database.Storage.Record_Serializer`
- `Database.Catalog.Rules`
- `Database.Versioning`
- `Database.Transactions.State_Rules`
- `Database.Visibility.Rules`
- `Database.Storage.Free_List_Manager`
- `Database.Storage.Table_Heap_Layout`
- `Database.Indexes.BTree_Invariants`

## Verification Goals

These packages are isolated because they are deterministic, bounded, and useful
for corruption detection or structural validation.

They use combinations of:

- `SPARK_Mode => On`
- explicit `Global` aspects
- explicit `Depends` aspects
- preconditions and postconditions
- loop invariants
- explicit status values

## Expected Local Commands

When GNATprove is available, the release checker runs these proof targets:

```sh
alr exec -- gnatprove -P spark_checksums.gpr --level=2
alr exec -- gnatprove -P spark_log_sequence.gpr --level=2
alr exec -- gnatprove -P spark_wal_frame_parser.gpr --level=2
alr exec -- gnatprove -P spark_wal_payload_rules.gpr --level=2
alr exec -- gnatprove -P spark_page_parser.gpr --level=2
alr exec -- gnatprove -P spark_record_serializer.gpr --level=2
alr exec -- gnatprove -P spark_catalog_rules.gpr --level=2
alr exec -- gnatprove -P spark_versioning.gpr --level=2
alr exec -- gnatprove -P spark_transaction_state_rules.gpr --level=2
alr exec -- gnatprove -P spark_visibility_rules.gpr --level=2
alr exec -- gnatprove -P spark_free_list_manager.gpr --level=2
alr exec -- gnatprove -P spark_table_heap_layout.gpr --level=2
alr exec -- gnatprove -P spark_btree_invariants.gpr --level=2
```

Use the strict proof mode when iterating on deeper contracts:

```sh
tools/bin/check_all --proof-strict
```

Strict mode preserves `gnatprove/` reports during cleanup for proof iteration.

## Boundary

The full database engine includes file I/O, heap allocation, controlled types,
registries, and integration code. These are intentionally kept outside the
SPARK-mode subset.
