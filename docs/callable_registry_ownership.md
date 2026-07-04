# True Per-Handle Callable Registries

Callable extension objects are owned by the database handle's catalog state key rather than by process-global mutable registries.

Affected callable registries:

- `Database.Functions`
- `Database.Aggregate_Functions`
- `Database.Collations`
- `Database.Full_Text.Tokenizers`
- `Database.Full_Text.Ranking`
- `Database.Validation_Hooks`

Each package maintains registry vectors behind an internal state map keyed by `Database.Catalog_State_Key (DB)`. Registration APIs select the calling handle before mutation. Legacy name-only lookup APIs continue to operate on the currently selected handle registry; `Database.Open_*` selects the handle-owned state, and direct tests can select a handle explicitly through package-local `Select_Database`.

`Database.Extensions.Clear` now clears the selected handle's callable registries as well as extension metadata/dependencies. Because callable registries are handle-owned, clearing or closing one handle no longer invalidates callable registrations in another open handle.

`Database.Close` drops callable state for the closing handle through each registry package's `Drop_Database`, preventing stale callable objects from surviving handle reuse while preserving other handles' state.

## Guarantees

- Registering a scalar function, aggregate, collation, tokenizer, ranking function, or validation hook on one handle does not make it visible to another handle.
- Closing one handle does not clear another handle's callable objects.
- Persistent extension dependency validation observes the selected handle's callable registry.
- Test-only and production paths use the same registry ownership mechanism.

## Limitation

Existing lookup/evaluation APIs remain name-only for compatibility. Callers that interleave operations across multiple open handles must ensure the intended handle's registry is selected, either by entering database operations through handle-scoped APIs or by calling the explicit `Select_Database` hook in internal/test code.
