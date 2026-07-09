# Encryption and secure storage

`database` provides a local-storage encryption surface. The feature is strictly for embedded, local files. It is not SQL, not a parser, not a network security layer, and not a remote authentication mechanism.

## Threat model

Encryption protects database pages, WAL frames, physical backups, and logical export containers against offline inspection and tampering. It is intended for a stolen file, copied backup, or modified WAL/database image.

It does not protect against a fully compromised running process, debugger access, memory scraping, OS paging, swap leakage, DMA attacks, malicious kernel code, or compromised application code after a key has been supplied.

## Package structure

The encryption surface uses four packages:

- `Database.Keys` derives, validates, identifies, and clears encryption keys.
- `Database.Crypto` provides authenticated encryption/decryption, MAC calculation, nonce generation, and buffer clearing.
- `Database.Crypto_Checks` verifies encrypted buffers and encryption metadata without exposing secrets.
- `Database.Encryption` coordinates encryption mode, metadata, and key rotation at the database-handle level.

The cryptographic abstraction is intentionally centralized. Storage, WAL, backup, restore, export, and import code must call through these packages rather than embedding ad-hoc encryption logic.

## Key model

Raw plaintext keys are not persisted in database files. A runtime key is represented by the private `Database.Keys.Encryption_Key` type.

Keys can be created from:

- a passphrase plus salt via `Derive_Key`, or
- an explicit 32-byte binary key via `From_Binary_Key`.

Temporary keys can be cleared with `Database.Keys.Clear`. Clearing is best-effort because Ada runtimes, operating systems, swap, crash dumps, and compiler optimizations may retain previous memory contents outside the library's control.

## Authenticated encryption model

Every encrypted object is authenticated with:

- object-specific nonce,
- associated data,
- ciphertext,
- authentication tag.

Associated data is where callers bind ciphertext to context such as page id, page LSN, WAL frame number, backup manifest identity, format version, and object kind. Callers must reject authentication failures before using decrypted content.

## Page encryption model

The intended storage model is page-level authenticated encryption:

1. Page metadata required for locating the object remains sufficient to read the object.
2. Page payload is encrypted.
3. Page id and page LSN are included as associated data.
4. The authentication tag is verified before any decrypted page content is trusted.
5. Page swap and stale-page attacks are rejected when the associated data binds the ciphertext to page id and LSN.

The page format is versioned. Unsupported encryption format versions return `Unsupported_Encryption_Format`. Failed authentication returns `Authentication_Failure` or a more specific storage-level status such as `Corrupt_Encrypted_Page`.

## WAL encryption model

WAL frames are encrypted and authenticated independently. Recovery must validate a frame before replay. A tampered frame fails safely; a partial or truncated frame is treated as incomplete WAL, not as trusted data.

WAL associated data should include frame kind, transaction id, LSN, page id for page frames, and encryption format version.

## Backup and export encryption

Physical backups and logical exports may be encrypted. The manifest or export header is authenticated, and import/restore validates authentication before writing restored database pages.

Encrypted exports are portable containers. They must include explicit format metadata and must never include plaintext keys.

## Key rotation

The simple key-rotation model is:

1. checkpoint the database,
2. rewrite encrypted storage using the new key,
3. rewrite or invalidate old WAL state,
4. atomically replace the old image,
5. validate the rewritten image before reporting success.

A failed rotation returns `Key_Rotation_Failed` or a more specific error. Ordinary rotation failures are status results, not exceptions.

## Diagnostics and checks

Diagnostics may report:

- encryption enabled/disabled,
- encryption format version,
- key id,
- encrypted WAL enabled/disabled,
- backup/export encryption enabled/disabled.

Diagnostics must not expose keys, derived key bytes, nonces used with secret material, decrypted page payloads, plaintext WAL payloads, or sensitive intermediate buffers.

`Database.Check` integration validates encryption metadata consistency, authentication tags, format versions, and encrypted object integrity without leaking decrypted content.

## Required operational limitations

- Nonces must not be reused with the same key and object identity.
- Authentication failures must stop reads, WAL replay, restore, and import.
- Debug output must not contain decrypted payloads.
- Plaintext temporary buffers should be cleared where feasible.
- Secure erase of already-written storage is not guaranteed by filesystems, SSD firmware, snapshots, journaling filesystems, or backups.

## Database-owned compatibility glue

The cryptographic primitives come from CryptoLib, while `database` still owns the durable artifact contract around them. `Database.Crypto.Generate_Nonce` derives the public 24-byte nonce from object id and LSN, and the AES-CTR IV is derived from that nonce with CryptoLib SHA-256 so the existing nonce type remains stable. The authentication message also remains database-owned: it includes a `DBENC1` domain marker plus length-prefixed nonce, associated data, and ciphertext bytes before CryptoLib HMAC-SHA256 is applied.

This keeps encrypted artifact identity, associated-data binding, and the current 24-byte nonce / 32-byte tag API stable for storage, WAL, backup, restore, export, and import callers.

## Current implementation note

`database.gpr` depends on the sibling `../cryptolib/cryptolib.gpr` project. The implementation uses CryptoLib PBKDF2-HMAC-SHA256 for passphrase key derivation, AES-256-CTR for byte transformation, HMAC-SHA256 for the 32-byte authentication tag, CryptoLib constant-time comparison for tag checks, and CryptoLib secure wipe for key and plaintext buffer clearing.

The public `Database.Keys` and `Database.Crypto` contracts remain centralized so storage, WAL, backup, restore, export, and import code do not embed ad-hoc cryptographic logic.
