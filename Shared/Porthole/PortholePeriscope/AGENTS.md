# PortholePeriscope – Module Shape

PortholePeriscope is the `periscope` Porthole connector: `events` (queryable
history), `live-events` (subscribable tail), and `scopes` over a
`PeriscopeStore` + `Periscope`. See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- Depends on **PortholeKit** + **PeriscopeCore** only. It reads Periscope's
  public store/live APIs (`events(matching:)`, `scopes()`, `liveRecords()`) — it
  never records events of its own.

## Invariants

- **`events` pages newest-first via limit + offset cursor** (the cursor is the
  next offset); `afterSequence` is also exposed as a filter for incremental
  live-forward reads. Payloads are decoded to JSON when possible.
- **`live-events` pumps `system.liveRecords()`** into the subscription and
  cancels the pump when the subscription ends.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholePeriscopeTests`, `extraPackageProducts: [PortholeKit, PortholeCore,
PeriscopeCore]`). Seed an in-memory store; drive a live `Periscope` for the tail
and poll for the emitted record rather than sleeping.
