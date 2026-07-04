# Direct Support Package Behavioral Tests

This file documents the direct support-package AUnit coverage for helper
packages that are easy to exercise only indirectly through feature tests.

The support test suite is intentionally separate from feature tests. Its purpose
is to prove that helper packages have observable behavior, not merely that their
specifications elaborate.

## Packages covered directly

- `Database.Status`
  - success/failure result construction
  - message preservation
  - non-exceptional hardening/security error codes
- `Database.Optional`
  - `None`/`Some` presence semantics
  - value round-tripping for multiple values
- `Database.Events`
  - null-handler rejection by omission
  - handler dispatch
  - handler clearing
  - failing-handler isolation through `Database.Status.Result`
- `Database.Tracing`
  - disabled no-op behavior
  - enable/disable state
  - category filtering
  - custom sink dispatch
  - failing-sink isolation
  - buffer clearing
  - monotonic timestamps
  - sensitive-message redaction
  - explicit sensitive trace enablement
  - file sink creation/write path
- `Database.Metrics`
  - reset behavior
  - every public increment/add operation
  - snapshot consistency for every counter in `Metrics_Snapshot`
- `Database.Profiling`
  - status-returning profiling
  - row-count reporting
  - operator-profile creation
  - optimizer-enabled/disabled diagnostic text
  - metrics integration
- `Database.Diagnostics.Runtime`
  - active reader diagnostics
  - active writer diagnostics
  - lock statistics mirroring
  - in-memory WAL absence reporting
  - cache metric mirroring
- `Database.Diagnostics`
  - in-memory storage diagnostics
  - encryption diagnostic defaults
  - full-text diagnostic calls for missing indexes
- Additional support packages retained from the previous pass:
  - `Database.Fault_Hooks`
  - `Database.Replay`
  - `Database.Versioning`
  - `Database.Visibility`
  - `Database.Statistics`
  - `Database.Indexes.BTree`

## Test design rules

The tests avoid SQL, parsers, runtime reflection, and automatic Ada record
persistence. They use explicit Ada-native APIs and assert ordinary failure
states through `Database.Status.Result` instead of exceptions.

## Remaining validation requirement

These tests are compiled and run by the project_tools-backed `tools/bin/check_all` entrypoint.
