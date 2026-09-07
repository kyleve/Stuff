# FlaggerUI – Module Shape

FlaggerUI turns a Flagger into a type-injected observable model, environment-
style group accessors, and a hierarchical editor. See [`README.md`](README.md).

This complements the root [`AGENTS.md`](../../AGENTS.md).

## Scope & dependencies

- SwiftUI and Flagger only; persistence, policies, sources, and group definitions remain in Flagger or consumers.
- Inject one `FlaggerModel` with `.environment(model)` at the scope root.

## Invariants

- `FlagGroupAccessor` only accepts key paths into its concrete group, and typed live mutation only accepts `LiveUpdating` flags.
- The editor reports effective, stored, default, invalid, frozen, and pending-next-lifetime state separately.

## Testing

Swift Testing in [`Tests/`](Tests) covers model/accessor behavior; image references live in [`SnapshotTests/`](SnapshotTests).
