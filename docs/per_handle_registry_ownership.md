# Per-handle Registry Ownership

The engine no longer treats catalog and extension dependency registries as single process-global mutable tables.
Each `Database.Handle` receives a stable registry state key when it is opened or created.
`Database.Catalog` and `Database.Extensions` keep independent registry state per key; package-level lookup functions operate on the currently selected handle state for compatibility with the existing Ada-native API.

## Selection model

Operations that receive a `Database.Handle` select the owning registry automatically before reading or mutating catalog state:

- `Register`
- `Update_Table`
- `Save`
- `Load`
- foreign-key/check/generated-column/view/materialized-view/full-text metadata mutation
- import into a database handle
- transaction begin paths
- extension registration/dependency mutation and extension sidecar save/load

The compatibility lookup APIs such as `Find_By_Name`, `Table_Count`, `Table_At`, and row-registry queries read the selected registry. Transaction begin and handle-scoped mutation select the correct registry before these APIs are used by normal table, query, import/export, check, and maintenance paths.

## Lifetime

`Database.Close` drops the catalog and extension registries owned by that handle. Closing one handle does not clear registry state for another open handle.

## Isolation guarantee

A table, relational metadata entry, full-text definition, cached row, extension definition, or extension dependency registered through one handle is not visible through another handle unless that second handle loaded the same durable database file into its own registry.

## Compatibility note

The old parameterless catalog APIs are retained to avoid breaking earlier phase APIs. New code should prefer operations that already carry a `Database.Handle`, or explicitly select with `Database.Catalog.Select_Database (Database.Catalog_State_Key (DB))` before direct diagnostic/test access to parameterless catalog queries.
