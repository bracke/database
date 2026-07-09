# Database Inspect Subcrate

`database_inspect` is a maintained Alire subcrate for inspecting persistent
database files from the command line. It is intended for local debugging,
release triage, and simple fixture investigation. It is not a SQL shell and does
not add a parser to the engine.

## Build

```sh
cd database_inspect
alr exec -- gprbuild -P database_inspect.gpr
```

The subcrate pins the root `database` crate through `database = { path = ".." }`
and requires GNAT 15 through `gnat_native = "=15.2.1"`.

## Commands

Print usage:

```sh
database_inspect/bin/database_inspect --help
```

Print the inspector version:

```sh
database_inspect/bin/database_inspect --version
```

List schemas and indexes:

```sh
database_inspect/bin/database_inspect path/to/app.database schemas
```

`tables` is accepted as an alias for `schemas`.

List index metadata grouped by table:

```sh
database_inspect/bin/database_inspect path/to/app.database indexes
```

Dump one table:

```sh
database_inspect/bin/database_inspect path/to/app.database dump table_name
```

Dump every table, with an optional row limit per table:

```sh
database_inspect/bin/database_inspect path/to/app.database dump --all 25
```

Inspect an encrypted database by deriving the runtime key from an environment
variable passphrase and the engine default salt:

```sh
DATABASE_INSPECT_PASSPHRASE='secret' \
database_inspect/bin/database_inspect --encrypted path/to/app.database schemas
```

Use a different environment variable name with:

```sh
APP_DB_PASSPHRASE='secret' \
database_inspect/bin/database_inspect --encrypted --passphrase-env APP_DB_PASSPHRASE path/to/app.database dump --all 25
```

Rows are rendered as plain text using the engine's typed value model. Text,
numbers, UUIDs, date/time values, arrays, enums, decimals, NULLs, and blob sizes
are displayed directly. Blob payload bytes are summarized by length rather than
printed inline.

## Scope

The tool opens ordinary persistent database files with `Database.Open`, or
encrypted persistent database files with `Database.Open_Encrypted` when
`--encrypted` is supplied. Open replays the WAL through the normal engine path,
then the tool lists catalog schemas and scans persistent table heaps through a
read-only transaction. It reads the same main database, WAL, encrypted page
sidecars, and full-text sidecar files that normal open uses.

The CLI does not accept plaintext passphrases as positional command-line
arguments because command lines are commonly captured in shell history and
process listings. The supplied passphrase is still present in the process
environment, so this is a debugging interface, not a high-assurance secret-entry
mechanism.

## Release Smoke Coverage

`tools/bin/check_all` builds the subcrate, runs help and version output,
plaintext schema and dump smoke checks plus plaintext index listing against an
existing persistent fixture, creates a temporary encrypted database with
`database_inspect_make_encrypted_fixture`, and verifies that
`database_inspect --encrypted` can list schemas, list indexes, and dump a row
through the documented passphrase environment-variable path. The temporary
encrypted files are created under `tests/` and removed by the normal
generated-artifact cleanup.
