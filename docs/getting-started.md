# Getting Started

This guide shows the intended user-facing workflow for `database`.

`database` is not a SQL database. You define schemas explicitly, map Ada records
to typed database rows explicitly, and perform all reads and writes through
transaction objects.

## Prerequisites

Local builds expect the sibling `../cryptolib` crate because `database.gpr`
depends on `../cryptolib/cryptolib.gpr`. Release checks also expect the sibling
`../project_tools` crate.

## Quickstart

Build and run the verified typed-table example:

```sh
alr exec -- gprbuild -P examples/typed_table/typed_table.gpr
examples/typed_table/bin/main
```

Expected output:

```text
found user: Ada Lovelace
active user: Ada
typed table example complete
```

For the smallest handle lifecycle smoke test, build and run:

```sh
alr exec -- gprbuild -P examples/minimal/minimal.gpr
examples/minimal/bin/main
```

## Minimal Workflow

A typical application does the following:

1. Open or create a database handle.
2. Define a schema.
3. Define an Ada record type.
4. Provide explicit mapping functions:
   - `To_Row`
   - `From_Row`
   - `Key_Of`
5. Register a typed table.
6. Start a transaction.
7. Insert, find, update, delete, or scan rows.
8. Commit or roll back the transaction.

## Example Record

```ada
type User_Id is new Natural;

type User is record
   Id     : User_Id;
   Name   : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   Active : Boolean;
end record;
```

The database never serializes the Ada record memory layout. Instead, the
application explicitly converts the record to and from database row values.

## Schema

A schema describes the database row shape. Public text APIs use
`Wide_Wide_String` or `Unbounded_Wide_Wide_String`.

The schema API uses `Database.Schema.Table_Schema` plus explicit columns:

```ada
Schema.Name := To_Unbounded_Wide_Wide_String ("users");

Database.Schema.Add_Column
  (Schema,
   Name        => "id",
   Kind        => Database.Types.Integer_Value,
   Nullable    => False,
   Primary_Key => True);

Database.Schema.Add_Column
  (Schema,
   Name     => "name",
   Kind     => Database.Types.Text_Value,
   Nullable => False);

Database.Schema.Add_Column
  (Schema,
   Name     => "active",
   Kind     => Database.Types.Boolean_Value,
   Nullable => False);
```

## Mapping Functions

### `To_Row`

`To_Row` converts an Ada record to a `Database.Rows.Row`.

```ada
function To_Row (Item : User) return Database.Rows.Row is
   Row : Database.Rows.Row;
begin
   Database.Rows.Append (Row, Database.Values.From_Integer (Integer (Item.Id)));
   Database.Rows.Append (Row, Database.Values.From_Text (To_Wide_Wide_String (Item.Name)));
   Database.Rows.Append (Row, Database.Values.From_Boolean (Item.Active));
   return Row;
end To_Row;
```

### `From_Row`

`From_Row` converts a database row back to an Ada record.

```ada
function From_Row (Row : Database.Rows.Row) return User is
begin
   return
     (Id     => User_Id (Database.Rows.Get (Row, 0).Int),
      Name   => Database.Rows.Get (Row, 1).Text,
      Active => Database.Rows.Get (Row, 2).Bool);
end From_Row;
```

### `Key_Of`

`Key_Of` extracts the primary key from the Ada record.

```ada
function Key_Of (Item : User) return User_Id is
begin
   return Item.Id;
end Key_Of;
```

`Key_Value` converts the typed key to a database value:

```ada
function Key_Value (Key : User_Id) return Database.Values.Value is
begin
   return Database.Values.From_Integer (Integer (Key));
end Key_Value;
```

## Typed Table Package

The typed table API is generic. A user instantiates it with the Ada record type,
key type, schema, and mapping functions.

```ada
package User_Tables is new Database.Tables.Typed
  (Row_Type     => User,
   Key_Type     => User_Id,
   To_Row       => To_Row,
   From_Row     => From_Row,
   Key_Of       => Key_Of,
   Key_Value    => Key_Value);
```

## Transactions

All reads and writes go through a transaction object.

```ada
Database.Transactions.Begin_Write (DB, Tx);

User_Tables.Insert
  (Tx,
   DB,
   Schema,
   (Id => 1,
    Name => To_Unbounded_Wide_Wide_String ("Ada"),
    Active => True));

Database.Transactions.Commit (Tx);
```

Use rollback for abandoned work:

```ada
Database.Transactions.Rollback (Tx);
```

RAII transaction style is preferred where the package-level API supports it.

## Basic Operations

```ada
Status := User_Tables.Insert (Tx, DB, Schema, New_User);
Status := User_Tables.Find (Tx, DB, Schema, 1, Found_User);
Status := User_Tables.Update (Tx, DB, Schema, Updated_User);
Status := User_Tables.Delete (Tx, DB, Schema, 1);
Status := User_Tables.Scan (Tx, DB, Schema, Predicate, Cursor);
```

## Filtering

Filtering uses typed predicates, not SQL strings.

```ada
Predicate :=
  Database.Predicates.Column_Equals
    (Index => 2,
     Value => Database.Values.From_Boolean (True));

Status := User_Tables.Scan (Tx, DB, Schema, Predicate, Cursor);
```

## Query Composition

Higher-level query packages provide projection, ordering, limits, aggregates,
joins, and optimizer-visible plans. These are Ada-native query structures, not
SQL text.

## Persistence

Use persistent open/create APIs to store data on disk. WAL/checkpointing,
recovery, backup/restore, and encryption facilities are available through their
respective packages.

## Complete Example

See:

- `examples/typed_table`

That example is built by the project toolchain and contains a complete record
mapping workflow, typed table registration, transactions, CRUD operations,
filtered scan structure, and notes about persistent storage.
