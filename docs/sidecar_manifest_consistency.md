# Sidecar / manifest consistency

This pass implements manifest-bound consistency for encrypted physical backup
sidecars.

## Implemented behavior

- `Database.Backup_Format.Manifest` now records:
  - `Encrypted_Page_Count`
  - `Encrypted_Page_Checksum`
  - `Encrypted_WAL_Checksum`
- `Database.Backup_Format.Compute_Encrypted_Page_Sidecar_Checksum` computes a
  deterministic checksum over the complete encrypted page sidecar set.
- `Database.Backup_Format.Validate_Manifest` rejects:
  - missing manifest-listed encrypted page sidecars,
  - encrypted page sidecar count/page-count mismatch,
  - encrypted page sidecar checksum mismatch,
  - missing encrypted WAL sidecar when the manifest lists one,
  - encrypted WAL sidecar checksum mismatch.
- `Database.Backup.Create_Encrypted_Physical_Backup` writes the sidecar
  consistency fields after all encrypted page/WAL sidecars are persisted and
  validates the manifest before returning success.
- `Database.Restore.Restore_Encrypted_Physical_Backup` runs manifest validation
  before authenticated decrypt/restore, so sidecar divergence fails before
  destination promotion.

## Test coverage

`Backup_Restore_Tests` now includes an encrypted physical backup test that
removes a manifest-listed encrypted page sidecar and verifies encrypted restore
rejects the backup.

## Scope

Full-text postings remain rebuildable cache sidecars by design. This change
specifically hardens authoritative encrypted backup sidecars that must match the
backup manifest exactly.
