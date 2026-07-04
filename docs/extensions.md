# Ada-native extensions

`database` provides explicit Ada-native extension APIs. Extensions are ordinary Ada subprograms and metadata records registered with a `Database.Handle`. There is no SQL UDF syntax, no scripting engine, no parser, no runtime reflection, and no dynamic shared-library ABI.

## Architecture

The extension layer is split by responsibility:

- `Database.Extensions` owns extension definitions, persistent dependency metadata, dependency validation, and lifecycle operations.
- `Database.Functions` registers deterministic scalar functions used by expressions, checks, generated columns, and index-compatible expressions.
- `Database.Aggregate_Functions` registers aggregate callbacks with `Initialize`, `Step`, and `Finalize` lifecycle operations.
- `Database.Collations` registers deterministic Unicode text comparison callbacks for ordering and index-compatible ordering.
- `Database.Full_Text.Tokenizers` supports custom full-text tokenizers referenced by stable tokenizer names.
- `Database.Full_Text.Ranking` supports deterministic custom ranking functions.
- `Database.Validation_Hooks` supports row validation hooks that return structured `Database.Status.Result` values.
- `Database.Extension_Metadata` defines optimizer-visible and integrity-checkable metadata shared by all extension categories.

All ordinary failures return `Database.Status.Result`; extension APIs do not use exceptions for expected errors.

## Determinism model

Persistent database objects may only depend on deterministic extension objects. This includes generated columns, check constraints, partial indexes, expression indexes, indexed collations, full-text tokenizers, and materialized data derived from extension functions.

A registered scalar function exposes:

- name
- extension name
- version
- compatibility identifier
- deterministic flag
- nullable-result flag
- argument count and argument types
- result type
- index-compatibility and monotonicity hints
- estimated cost

The optimizer may use deterministic, monotonic, index-compatible, and cost metadata. If metadata is missing or uncertain, the optimizer must conservatively avoid unsafe rewrites.

## Dependency tracking

Persistent schema objects should record extension dependencies with:

- object kind
- object name
- required version
- compatibility identifier

Database reopen, import finalization, integrity checking, and recovery validation must reject missing or incompatible required extension objects with `Missing_Extension` or `Extension_Version_Mismatch`.

Changing function, collation, tokenizer, or ranking semantics without changing the compatibility identifier is invalid. Incompatible changes must use a new compatibility identifier and dependent indexes/materialized data must be rebuilt or rejected.

## Scalar functions

Register scalar functions through `Database.Functions.Register_Function`. The implementation receives a `Database.Values.Value_Vector` and returns a `Database.Values.Value`. Registration metadata enforces argument count, argument type, result type, nullability, determinism, and index eligibility.

Registered functions can be evaluated directly or called from `Database.Expressions.Registered_Function_Call`. Non-deterministic functions are rejected for persistent expression use.

## Aggregate functions

Register aggregates through `Database.Aggregate_Functions.Register_Aggregate`. Aggregates have an explicit state object and three callbacks:

1. `Initialize`
2. `Step`
3. `Finalize`

Aggregate callbacks must not mutate database state or perform hidden I/O during query execution. They must be transaction-safe and deterministic when marked deterministic.

## Collations

Register collations through `Database.Collations.Register_Collation`. A collation callback compares two `Wide_Wide_String` values and returns a negative, zero, or positive integer.

Indexed collations must be deterministic and index-compatible. Changing collation semantics invalidates all dependent indexes.

## Full-text tokenizers

Register custom tokenizers through `Database.Full_Text.Tokenizers.Register_Tokenizer`. Full-text index metadata stores the tokenizer identifier, not executable code. A database reopened without the required tokenizer must fail dependency validation before dependent full-text indexes are used.

## Ranking functions

Register custom ranking functions through `Database.Full_Text.Ranking.Register_Ranking_Function`. Ranking callbacks receive an explicit `Ranking_Context`. Deterministic ranking functions must not depend on wall-clock time, process-global mutable state, I/O, random values, or external services.

## Validation hooks

Register validation hooks through `Database.Validation_Hooks.Register_Validation_Hook`. Hooks receive the table schema and row and return `Database.Status.Result`. A validation hook may reject data but must not mutate the database or bypass transaction, MVCC, WAL, encryption, or recovery semantics.

## Import/export

Logical export/import must preserve extension dependency metadata, including function, collation, tokenizer, ranking, generated-column, and validation-hook references. Import finalization must validate that all required extensions exist and have compatible versions.

## Limitations

- No SQL UDF syntax.
- No dynamic shared-library plugin ABI.
- No scripting engine.
- No runtime reflection.
- No automatic Ada record persistence.
- No serialization of Ada record memory layout.
- Non-deterministic extension objects are prohibited in persistent/indexed expressions.
