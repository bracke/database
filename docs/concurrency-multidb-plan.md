# Plan: concurrent multi-database support

## Objective & scope

Allow multiple open `Database.Handle`s to be driven **concurrently from
different tasks** without corruption or deadlock. Single-handle concurrency
(many readers / one writer) already works; this closes the multi-handle gap.

**Non-goals (for now):** concurrent writers on the *same* handle (already
serialized by the per-handle lock), cross-process concurrency, lock-free
tuning. Correctness first.

## Foundation already in place

`MVCC`, `Metrics`, and `Memory_Store` (the in-memory backend) are protected, and
the id / state-key allocators are atomic — the last of these is covered by a
concurrency test (`concurrent begins assign unique transaction ids`) that was
verified to fail with a non-atomic allocator and pass with the protected one.
The remaining gap is the **per-subsystem "current database" selection**.

## Root cause (established)

Nine subsystems bind operations to a database through a **process-global**
`Current_Key`, set by `Select_Database` and read by `Current_State`:

`Catalog`, `Extensions`, `Functions`, `Aggregate_Functions`, `Collations`,
`Full_Text`, `Full_Text.Tokenizers`, `Full_Text.Ranking`, `Validation_Hooks`.

Two failure modes, both confirmed:

1. **Selection clobbering** — between one task's `Select_Database(k1)` and its
   use of `Current_State`, another task selects `k2`; the first task now reads
   the wrong database's state. (The multi-DB isolation test fails intermittently
   on this.)
2. **Registry races** — the shared `States` vector is appended (Open) and
   deleted (Close) without synchronization; concurrent Open/Close corrupts it.

`Tracing` also uses unsynchronized globals (buffer/sink/flags) but is off by
default.

## The lesson that shapes the design

The first fix attempt — a protected `State_Registry` whose creation path ran
`new Catalog_State` **while holding the registry lock** — deadlocked under
concurrent load (the engine ran fine before the change and hung after; blocked,
zero CPU). Design constraints that follow:

- **No work under a registry lock.** Allocate / finalize / call other subsystems
  *outside* the lock; hold it only to look up or insert a pointer.
- **A single documented lock order**, e.g.
  `per-handle Read_Write_Lock → subsystem registry lock → (nothing else)`,
  honored by every path. The deadlock lived in the
  handle-lock ↔ registry ↔ allocator triangle.
- **Verify with a tool** (ThreadSanitizer), not just by reasoning — this class of
  bug is too easy to reintroduce.

## Design options

**Model A — task-local selection + hardened registries (smaller change).**
`Current_Key` becomes thread-local (`pragma Thread_Local_Storage`); each
registry allocates state *outside* the lock, then a short critical section
inserts (double-checking for a concurrent creator) or looks up. API surface
unchanged. *Pro:* localized, incremental, API-compatible. *Con:* keeps the
implicit "current database" model; correctness depends on all 9 being
consistent.

**Model B — handle-anchored state, global-free (larger, cleaner).** The handle
carries a bundle of state-access pointers populated at Open; operations derive
state from the handle they already receive; the globals are deleted. *Pro:*
eliminates the entire bug class. *Con:* touches many operation
signatures/call sites.

**Recommendation:** land **Model A** first for correctness with contained risk,
then optionally migrate to **Model B** subsystem-by-subsystem behind the same
API. A gets us *safe*; B gets us *clean*.

## Phases

### Phase 0 — verification baseline first (no product changes)

Non-negotiable and done first: this session's failure came from fixing before a
verification baseline existed.

- The multi-DB isolation test plus a heavier soak variant, as a **standalone
  runnable** (not part of the always-green AUnit suite, because it fails until
  the fix lands). Assert-only-on-corruption with generous iteration counts.
- A **ThreadSanitizer** build (`-fsanitize=thread`) of that runnable; capture the
  current races as the baseline.
- Acceptance gate for every later phase: isolation + soak green **and** TSan
  clean, repeatedly, under a hang watchdog.

### Phase 1 — one subsystem (Catalog), get the pattern right

Implement Model A for Catalog only (always used, exercised by the test). This is
where the deadlock is solved and the lock order proven. Gate: isolation green +
TSan clean.

### Phase 2 — roll the proven pattern across the other 8

Mechanical once Phase 1 is solid, but add a *feature-exercising* concurrent test
per subsystem (concurrent DBs each using functions / collations / FTS) so each
is actually validated. Release gate is "all 9 + TSan clean," not "catalog."

### Phase 3 — residual shared state

Protect `Tracing`'s buffer/sink/flags (or document config-only); audit `Events`
registration vs. concurrent emit; sweep for any other operation-path globals.

### Phase 4 (optional) — Model B migration

Per-handle state bundle; retire the globals one subsystem at a time. Schedule
separately.

## Verification strategy (the crux)

- **Functional:** isolation + per-subsystem concurrent tests, high iteration
  counts, run N× in CI.
- **ThreadSanitizer:** whole-suite/soak TSan job, must be clean — the primary
  defense against the exact deadlock/race class hit this session.
- **Soak:** nightly long-running mixed multi-DB workload
  (read/write/rollback/open/close).
- **Deadlock watchdog:** hard-fail on any hang.
- **No-regression:** existing AUnit suite + full stack stay green throughout.

## Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Deadlock (demonstrated) | Documented lock order; no work under lock; TSan + hang watchdog |
| TLS assumptions wrong | Audit that every op re-selects/derives state within its own task; no cross-task selection hand-off |
| Inconsistent 9-subsystem rollout | Per-subsystem tests; "all 9 + TSan clean" is the release gate |
| Foundational blast radius | Everything behind the Phase-0 gate; each phase independently revertible |

## Rough sequencing

Phase 0 ≈ 0.5–1 day · Phase 1 ≈ 1 day (solves the deadlock) · Phase 2 ≈ 1–2 days
· Phase 3 ≈ 0.5 day · Phase 4 separate/larger. **Do not compress Phase 0.**

## Status

- [x] Plan written.
- [ ] Phase 0: standalone concurrent soak/isolation runnable.
- [ ] Phase 0: ThreadSanitizer build + baseline captured.
- [ ] Phase 1 … 4.
