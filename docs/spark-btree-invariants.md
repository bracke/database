# SPARK Analysis for B+ Tree Invariants

`Database.Indexes.BTree_Invariants` isolates structural B+ tree validation in a
SPARK-mode package.

## Scope

The package is marked:

```ada
with SPARK_Mode => On
```

It validates bounded node descriptors rather than performing page I/O or mutating
the production B+ tree. The production index layer can export node descriptors
for verification while keeping storage and cache management outside this SPARK
subset.

## Invariants Checked

The checker validates:

- non-empty tree
- valid root page id
- unique page ids
- no `No_Page` active nodes
- valid key counts
- valid child counts
- strictly sorted keys
- internal node child-count relation: children = keys + 1
- leaf nodes have no children
- child references exist
- parent references exist
- child parent pointers match
- child key ranges are bounded by parent separator keys
- all leaves are at the same depth
- leaf next/previous links are reciprocal
- linked leaves are key ordered
- every active node is reachable from the root

## Verification-Oriented Properties

The checker has:

- no global state
- explicit `Depends` contracts
- bounded node capacity
- bounded key/child capacity
- explicit validation statuses
- loop invariants over traversal, linkage, and reachability checks
- no exception-based ordinary validation failure

## Expected GNATprove Command

When GNATprove is available:

```sh
gnatprove -P spark_btree_invariants.gpr --level=2
```

For deeper proof attempts:

```sh
gnatprove -P spark_btree_invariants.gpr --level=4
```

## Integration Policy

The production `Database.Indexes.BTree` package should expose or construct
`Node_Descriptor` values for debug/invariant validation. This keeps proof-friendly
invariant logic independent from persistence, caching, transactions, WAL replay,
and MVCC visibility.

## Test Coverage

AUnit tests cover:

- valid tree acceptance
- unsorted key rejection
- duplicate page id rejection
- missing/bad parent rejection
- child key-range violation
- leaf depth mismatch
- leaf link mismatch
- unreachable node detection path
- leaf-with-children rejection
