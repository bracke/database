# typed_table example

This example demonstrates the core user-facing model of `database`.

It shows:

- an Ada record used as the application row model
- explicit schema construction
- explicit `To_Row`
- explicit `From_Row`
- explicit `Key_Of`
- typed table instantiation
- table registration
- transaction-scoped insert/find/update/delete/scan
- predicate-based filtering without SQL

The code is written as a clear reference example. Depending on the exact state of
the public constructors in the current crate, use this example as the quickstart
source of truth for typed table workflows.

Build and run:

```sh
alr exec -- gprbuild -P examples/typed_table/typed_table.gpr
examples/typed_table/bin/main
```
