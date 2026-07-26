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

## Phase 0 baseline (captured)

Runnable: `tests/src/concurrency_soak.adb` (main `concurrency_soak`, not part of
the AUnit suite). Each worker drives its own in-memory database; exit 0 = all
isolated, 1 = corruption.

```sh
# functional baseline (fails today)
alr build && ./bin/concurrency_soak 8
#   -> "SOAK FAIL: concurrent databases were not isolated" (and intermittently
#      "double free or corruption" -> SIGABRT)

# ThreadSanitizer baseline (races today). -R disables ASLR, which TSan needs.
alr exec -- gprbuild -P tests.gpr -XSANITIZE=thread
TSAN_OPTIONS="halt_on_error=0 exitcode=66" setarch "$(uname -m)" -R ./bin/concurrency_soak 2
```

TSan result at baseline: **17 data races + 1 heap-use-after-free**, all in the
per-subsystem state registries — concurrent `Insert` into the unsynchronized
`States` vectors of `Catalog`, `Extensions`, `Functions`, … and concurrent
`__gnat_free` of state objects. This is exactly the root cause above, and is the
acceptance target: after the fix, both runs must be clean, repeatedly.

Note: `-fsanitize=thread` instruments only Ada code compiled here, not the
prebuilt GNAT runtime, so some reports have runtime frames; the app-side frames
(the `database__*__*_vectors__insert` entries) are the actionable ones.

## Status

- [x] Plan written and committed.
- [x] Phase 0: standalone concurrent soak/isolation runnable (fails today, as
      expected — documents the bug).
- [x] Phase 0: ThreadSanitizer build (`-XSANITIZE=thread`) + baseline captured
      (17 races + 1 UAF, pinpointing the subsystem state registries).
- [x] Phase 0: soak + TSan wired into CI as a dedicated non-blocking
      `concurrency-baseline` job (currently red by design; flip
      `continue-on-error` to false once green).
- [x] **Phase 1 (Catalog): done and verified.** `Current_Key` is thread-local;
      the catalog state registry is a protected object over a fixed, packed
      plain array with **no allocation/deallocation under the lock** (states are
      allocated/freed by the caller outside the protected action). This is the
      design that avoids the earlier deadlock.
      - No deadlock, no regression: AUnit **235/235**, full stack ALL GREEN.
      - TSan: **catalog races eliminated (0)**; total races 17 → 13, all
        remaining ones in the other 8 subsystems (extensions, functions,
        aggregate_functions, collations, full_text + tokenizers + ranking,
        validation_hooks) — the Phase 2 targets.
      - Design lesson applied: fixed array (no container tampering, no growth) +
        allocate-outside-lock + Find is a protected function / Insert/Remove are
        protected procedures.
- [x] **Phase 2: done and verified.** The Phase-1 pattern was factored into a
      generic `Database.State_Registry` (fixed, packed, allocation-free
      protected registry) and applied to all remaining subsystems:
      - Six uniform "registry-of-vector" subsystems (functions,
        aggregate_functions, collations, validation_hooks, full_text.tokenizers,
        full_text.ranking): thread-local `Current_Key`, generic registry,
        allocate-outside-lock.
      - Two "value-swap" subsystems (extensions, full_text) converted from the
        `Store_Current_State`/`Load_State` model to the same pointer model
        (per-database state held by access in the registry; operations use
        `Current.all.<field>`).
      - Verified: AUnit **235/235** (no hang, no regression), full stack ALL
        GREEN, the `concurrency_soak` functional runnable **green**, and under
        ThreadSanitizer **0 data races / 0 warnings** (race count 17 → 13 → 3 →
        0 across the phase).
      - CI `concurrency-baseline` flipped from informational to a gate (the
        functional soak blocks; the TSan step tolerates runner ASLR quirks).
- [ ] Phase 3: residual shared state (Tracing buffer/sink/flags; Events handler
      registration vs concurrent emit). Not on the operation hot path and off by
      default, so lower priority.
- [ ] Phase 4 (optional): Model B (handle-anchored state) cleanup.
