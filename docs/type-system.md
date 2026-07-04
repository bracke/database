# Type system

`database` is an Ada-native, strictly typed relational storage engine. The logical value model supports expanded native scalar and collection-oriented values without adding SQL, parser support, runtime reflection, or automatic Ada record persistence.

## Logical model

A column has a stable `Database.Types.Value_Kind` and optional `Database.Types.Type_Descriptor` metadata.  The descriptor records the serialization format version and, where relevant, decimal precision/scale, bounded text length, enum identity, array element kind, and collation name.  Metadata is explicit and is validated by `Database.Type_Metadata`.

## Serialization guarantees

Values are serialized value-by-value.  Ada record memory layout, platform time layouts, locale formatting, and pointer representations are never serialized.  Text is stored as deterministic Unicode code points.  Date/time values are stored as numeric fields.  UUIDs are stored as sixteen canonical bytes.

## Date and time

`Database.Date_Time` defines native `Date`, `Time`, `Date_Time`, and `Time_Span` records (`Duration_Value` at the logical value-kind level).  Dates use a proleptic Gregorian calendar in the range 0001-01-01 through 9999-12-31.  Times use hour, minute, second, and nanosecond fields.  `Date_Time` is a logical timestamp with documented UTC-normalized semantics at the database layer; no hidden locale or timezone conversion is performed during serialization.

Ordering is lexicographic by date fields, then time fields.  Time span ordering is by seconds then nanoseconds.  Date/time arithmetic is explicit through typed expressions: `Date_Time + Time_Span` yields `Date_Time`; `Date_Time - Date_Time` yields a `Duration_Value` containing a `Time_Span`.

## UUID

`Database.UUIDs` provides `Generate_UUID`, `Parse_UUID`, and `UUID_To_String`.  Text form is canonical lower-case `8-4-4-4-12` hexadecimal.  Persistent ordering is bytewise over the 16-byte representation, which is stable and index-friendly.

## Decimal

Decimal values remain exact coefficient/scale pairs.  `Decimal_Descriptor` can require precision and scale.  Validation rejects precision overflow and scale mismatch with explicit status results such as `Decimal_Overflow`; floating-point rounding is not used for decimal validation.

## Bounded text

`Bounded_Text_Descriptor` records a maximum Unicode character count and optional collation name.  The default rule is rejection, not truncation: values exceeding `Maximum_Length` fail with `Bounded_Text_Overflow`.

## Enumerations

Enum descriptors preserve a symbolic enum name and literal names.  Persistent representation is name-based by default to avoid accidental meaning changes when Ada enum ordering changes.  Incompatible enum changes require explicit migration.

## Collections

Collection support is intentionally conservative: `Array_Value` stores deterministic logical text with explicit element-kind metadata. Arbitrary nested object persistence is deferred until a complete nested schema model is defined.

## Import/export, WAL, MVCC, encryption

New values use deterministic row serialization and therefore remain compatible with WAL replay, MVCC visibility, encrypted storage, backup/restore, and logical import/export.  Integrity checks can validate type metadata versions, decimal metadata, bounded text constraints, UUID byte shape, and date/time ranges.
