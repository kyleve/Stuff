# PatchlightCore – Module Shape

UI-free Patchlight domain/infrastructure; see [`README.md`](README.md) and the
product/root [`AGENTS.md`](../AGENTS.md), [`AGENTS.md`](../../AGENTS.md).

Depend only on `StuffCore`, `ImageDiffKit`, and Apple non-UI system frameworks.
Keep GitHub/provider primitives at HTTP boundaries, SwiftData models inside the
`@ModelActor`, persisted enum values as explicit stable codes, and all sensitive
bodies/payloads encrypted before storage. Never automatically retry an
ambiguous write or fall back between AI providers.

One account scope owns one store, vault key, cache, and work registry. Preserve
the sign-out order documented by `PatchlightScopeTests`.

Tests: `PatchlightCoreTests` (`./test PatchlightCoreTests`).
