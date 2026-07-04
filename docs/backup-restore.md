# Backup and Restore

`database` provides database-native backup and restore facilities. The feature is
strictly non-SQL: no parser, no SQL dump format, and no serialized Ada record
memory layout are introduced.

## Physical backup layout

A physical backup destination is a directory containing:

- `manifest.dbbackup` — textual manifest with format versions, page size, page
  count, LSN fields, and checksums.
- `database.image` — byte-for-byte database file image.
- `database.wal` — optional WAL image when a WAL file exists and the backup
  options include WAL.

The manifest begins with:

```text
DATABASE_BACKUP_MANIFEST 1
```

The remaining lines are `key=value` pairs:

- `database_format_version`
- `backup_format_version`
- `source_database_id`
- `created_at`
- `page_size`
- `page_count`
- `checkpoint_lsn`
- `backup_target_lsn`
- `wal_start_lsn`
- `wal_end_lsn`
- `database_checksum`
- `wal_checksum`
- `catalog_checksum`

Checksums are database-native implementation checksums intended to detect
missing or mismatched backup files during restore. They are not cryptographic
signatures.

## Creating a backup

Use `Database.Backup.Create_Physical_Backup` on an open persistent database:

```ada
R := Database.Backup.Create_Physical_Backup (DB, "backup-dir");
```

The advanced overload accepts `Backup_Options`:

```ada
Options.Include_WAL       := True;
Options.Verify_After_Copy := True;
Options.Force_Checkpoint  := False;
R := Database.Backup.Create_Physical_Backup (DB, "backup-dir", Options);
```

The implementation flushes the database file, optionally forces a checkpoint,
copies the database image, copies the WAL image if present, writes the manifest,
and validates checksums when verification is enabled.

## Snapshot and concurrency semantics

The backup represents a committed persistent state of the database file and WAL
at the chosen copy point. Readers may remain active. A concurrent writer is
rejected for the initial implementation because correctness is preferred over
copying a database file while pages are being mutated. This is the documented
reduced-concurrency implementation of the snapshot backup contract.

Future incremental backup support can use the manifest LSN fields and page LSN
tracking to include only changed pages plus a WAL range.

## Restoring a backup

Use `Database.Restore.Restore_Physical_Backup`:

```ada
R := Database.Restore.Restore_Physical_Backup
  ("backup-dir", "restored.database");
```

The default restore never overwrites an existing destination. Use
`Restore_Options` to opt in to overwriting:

```ada
Options.Overwrite := True;
Options.Verify    := True;
R := Database.Restore.Restore_Physical_Backup
  ("backup-dir", "restored.database", Options);
```

Restore validates the manifest and checksums before finalizing the destination.
It restores into a temporary file first and then renames it into place. An
interrupted or failed restore must not leave a valid-looking corrupt destination.

## Failure handling

Ordinary failures are returned as `Database.Status.Result` values. Backup and
restore add explicit status categories such as `Backup_Error`, `Restore_Error`,
`Incompatible_Backup`, `Corrupt_Backup`, and `Backup_Verification_Failed`.
Exceptions are not used as ordinary control flow.

## Limitations

- No SQL dumps.
- No parser.
- No replication.
- Incremental backup is groundwork only in this phase.
- The first physical backup implementation rejects active writers rather than
  attempting lock-free page copying.

## Encrypted backup and restore

See `docs/encrypted-backup-restore.md` for the authenticated encrypted physical backup path.

## Encrypted sidecar consistency

For encrypted physical backups the manifest also includes sidecar consistency
fields:

- `encrypted_page_count`
- `encrypted_page_checksum`
- `encrypted_wal_checksum`

`Validate_Manifest` rejects backups where the listed encrypted page sidecar set
is missing or does not match the deterministic sidecar checksum.  Encrypted
restore invokes this manifest validation before decrypting pages, so missing or
swapped sidecars are detected before destination promotion.
