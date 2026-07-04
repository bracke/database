# Encrypted physical backup and restore

Encrypted physical backup is a separate authenticated path from ordinary
physical backup. It does not copy live database pages as plaintext backup
images. Instead, each page is read through the database page API and written as
an authenticated encrypted backup artifact.

Artifacts written by encrypted backup:

- `manifest.dbbackup`: non-secret bootstrap manifest containing page count,
  page size, checksums for compatibility marker files, and source metadata.
- `manifest.dbbackup.enc`: authenticated encrypted manifest copy used by
  encrypted restore to reject manifest tampering/key mismatch.
- `database.image`: marker file only; it is not a plaintext page image for
  encrypted backups.
- `database.page N.backup.enc`: authenticated encrypted backup artifact for
  page `N`.
- `database.wal.enc`: authenticated encrypted WAL artifact when a WAL file is
  present and WAL inclusion is enabled.

Restore behavior:

1. Read the plaintext bootstrap manifest only to learn expected page count and
   page size.
2. Verify `manifest.dbbackup.enc` with the supplied restore key.
3. Verify every encrypted page artifact before writing the destination.
4. Verify the encrypted WAL artifact when present.
5. Create the destination as an encrypted database file.
6. Decrypt every page artifact and write it through `Storage.File_IO` so normal
   page validation and authenticated encrypted page persistence are used.
7. Restore the encrypted WAL artifact when present.
8. Reopen the restored database with the supplied key when verification is
   requested.

Security and corruption guarantees:

- Wrong-key restore fails before destination promotion.
- Truncated or tampered page artifacts fail authentication.
- Truncated or tampered encrypted WAL artifacts fail authentication.
- Truncated or tampered encrypted manifest artifacts fail authentication.
- The temporary restore file is not promoted unless all encrypted artifacts are
  verified and written successfully.
- Ordinary corruption is reported through `Database.Status.Result`; expected
  corruption is not represented with exceptions.

Limitations:

- Encrypted logical export/import is a separate path.
- The plaintext bootstrap manifest intentionally contains no row payloads or
  page data.

## Sidecar/manifest consistency

Encrypted backup sidecars are now manifest-bound.  The plaintext bootstrap
manifest records the expected encrypted page sidecar count, a deterministic
checksum over the complete encrypted page sidecar set, and the encrypted WAL
sidecar checksum when a WAL sidecar is present.  `Database.Backup_Format` checks
these values before encrypted restore verifies or decrypts any artifact.

This gives the restore path an early structural fail-closed check for:

- missing encrypted page sidecars,
- stale sidecars copied from another backup directory,
- truncated sidecars before authentication is attempted,
- encrypted WAL sidecar mismatch,
- manifest/page-count disagreement.

The encrypted manifest remains the authenticated source for key and tamper
validation.  The plaintext manifest is only a bootstrap index and consistency
contract; it is never trusted for page payloads, keys, or plaintext data.
