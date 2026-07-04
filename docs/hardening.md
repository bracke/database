# Hardening Architecture

The hardening layer validates reliability and corruption-detection behavior.

## Fault Injection

Fault injection provides deterministic controls for failure scenarios such as
page-write interruption, WAL failure, checkpoint failure, restore failure, import
failure, and encryption verification failure.

## Crash and Power-Loss Simulation

Crash and power-loss helpers model:

- crash before commit marker
- crash after commit marker
- checkpoint interruption
- torn or partial durable artifacts
- truncated WAL frames
- encrypted artifact corruption

## Invariant Checking

Invariant checks validate storage, catalog, index, MVCC, WAL, free-list, and
cross-reference consistency. Corruption is reported through explicit status
values rather than ordinary exceptions.

## Fuzzing

Fuzzing targets malformed durable artifacts, including pages, WAL frames, record
envelopes, backup manifests, import/export structures, encrypted metadata, and
full-text structures.

## Stress

Stress workloads are deterministic and bounded. They cover randomized
transactions, open/close cycles, recovery cycles, backup/restore cycles,
import/export cycles, and concurrent reader/writer scenarios.

## Observability

Hardening integrates with diagnostics, metrics, tracing, profiling, and events.
Diagnostics should report enough detail for reproducibility while avoiding
unintentional plaintext or key material leakage.
