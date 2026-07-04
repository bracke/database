# SPARK-Oriented Verification

The project uses SPARK selectively. It does not attempt to convert the entire
database engine to SPARK.

## Included SPARK-Mode Packages

- `Database.Checksums`
- `Database.WAL.Frame_Parser`
- `Database.Storage.Page_Parser`
- `Database.Storage.Record_Serializer`
- `Database.Storage.Free_List_Manager`
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

When GNATprove is available:

```sh
gnatprove -P spark_checksums.gpr --level=2
gnatprove -P spark_wal_frame_parser.gpr --level=2
gnatprove -P spark_page_parser.gpr --level=2
gnatprove -P spark_record_serializer.gpr --level=2
gnatprove -P spark_free_list_manager.gpr --level=2
gnatprove -P spark_btree_invariants.gpr --level=2
```

Higher levels can be used for deeper proof attempts.

## Boundary

The full database engine includes file I/O, heap allocation, controlled types,
registries, and integration code. These are intentionally kept outside the
SPARK-mode subset.
