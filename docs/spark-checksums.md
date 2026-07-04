# SPARK Analysis for Checksums

The checksum layer is intentionally isolated into `Database.Checksums`.

## Scope

`Database.Checksums` is marked:

```ada
with SPARK_Mode => On
```

The package contains:
- `Adler32`
- `Adler32_Update`
- `Verify_Adler32`
- `Page_Checksum`
- `Verify_Page_Checksum`

These routines have:
- `Global => null`
- explicit `Depends` contracts
- verification postconditions for the public verification helpers
- loop invariants for the Adler-32 accumulation loop

## Why This Is Isolated

The full database engine includes heap allocation, file I/O, controlled types,
dynamic registries, test harnesses, encryption adapters, and other features that
are not intended to be fully converted to SPARK.

The checksum code is a good SPARK candidate because it is:
- deterministic
- side-effect-free
- low-level
- security/corruption relevant
- small enough for direct proof-oriented review

## Expected GNATprove Command

When GNATprove is available:

```sh
gnatprove -P spark_checksums.gpr --level=2
```

For a deeper run:

```sh
gnatprove -P spark_checksums.gpr --level=4
```

## Behavioral Tests

AUnit coverage verifies:
- empty Adler-32 input
- standard Adler-32 vector for `Wikipedia`
- incremental update convergence
- page-id binding for page checksums
- tamper rejection

## Integration Policy

Storage, WAL, backup, import/export, and encryption validation should call this
package for checksum logic instead of duplicating checksum loops.

Authenticated encryption tags remain distinct from checksums. Checksums detect
accidental corruption and structural mismatch; authentication tags detect
tampering in encrypted artifacts.
