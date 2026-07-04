# SPARK Analysis for Free-List Management

`Database.Storage.Free_List_Manager` isolates deterministic free-list state
management in a SPARK-mode package.

## Scope

The package is marked:

```ada
with SPARK_Mode => On
```

It manages a bounded sorted set of reusable page ids.

The package validates:
- count bounds
- no `No_Page` entries inside the active range
- no reserved page ids
- no out-of-range page ids
- no duplicate page ids
- sorted order

## Operations

The package provides:
- `Clear`
- `Contains`
- `Validate`
- `Add_Free_Page`
- `Allocate_Free_Page`
- `Remove_Free_Page`

All operations return explicit status values rather than using exceptions for
ordinary corruption or operation failure.

## Verification-Oriented Properties

The manager has:
- no global state
- explicit `Depends` contracts
- bounded storage
- loop invariants for traversal and shifting operations
- deterministic allocation policy
- corruption detection before mutation

## Failure Modes

The manager rejects:
- invalid page ids
- reserved page ids
- out-of-range page ids
- duplicate free pages
- removal of non-free pages
- allocation from an empty free-list
- mutation of a corrupt free-list

## Expected GNATprove Command

When GNATprove is available:

```sh
gnatprove -P spark_free_list_manager.gpr --level=2
```

For deeper proof attempts:

```sh
gnatprove -P spark_free_list_manager.gpr --level=4
```

## Integration Policy

The existing storage free-list package should use this SPARK-friendly manager for
the core sorted-page-set logic while keeping persistence, page I/O, and catalog
interaction in the non-SPARK storage layer.

## Test Coverage

AUnit tests cover:
- clearing and validation
- sorted insert behavior
- duplicate rejection
- reserved-page rejection
- out-of-range rejection
- deterministic allocation
- removal
- duplicate corruption detection
- unsorted corruption detection
