# Real encrypted persistence

This patch adds `Database.Encrypted_Persistence`, a durable encrypted artifact container used by tests and recovery/security validation to exercise persisted encrypted data rather than only in-memory crypto buffers.

## Container guarantees

Each persisted artifact stores:

- explicit magic/version bytes,
- encrypted artifact kind,
- encryption format version,
- key identifier,
- object id,
- LSN,
- nonce,
- authentication tag,
- ciphertext payload.

The authentication associated data is produced by `Database.Crypto_Checks.Artifact_Associated_Data`, so ciphertext is bound to its durable artifact class and identity. Copying encrypted bytes between page/WAL/backup/export/full-text/key-metadata containers, changing object id, changing LSN, using a different key id, truncating the file, or flipping ciphertext bytes is rejected through structured `Database.Status.Result` failures.

## Covered artifact classes

`Database.Encrypted_Persistence` supports all encrypted durable artifact kinds enumerated by `Database.Crypto_Checks`:

- encrypted page artifacts,
- encrypted WAL frame artifacts,
- encrypted backup payloads,
- encrypted logical exports,
- encrypted key metadata,
- encrypted backup manifests,
- encrypted full-text durable structures.

## Tests

The encryption test suite now includes file-backed checks for:

- write, close, verify, and reopen of a persisted encrypted page artifact,
- ciphertext tamper rejection for persisted encrypted exports,
- truncation rejection for persisted encrypted WAL artifacts.

These tests complement the exhaustive artifact-matrix validation by proving that the validation is applied to durable bytes read back from disk.

## Limitations

The package is an explicit encrypted durable-artifact layer. It does not serialize Ada record memory layout and it does not introduce SQL, parser support, server mode, or distributed behavior. Ordinary corruption and authentication failures are returned as status results, not exceptions.
