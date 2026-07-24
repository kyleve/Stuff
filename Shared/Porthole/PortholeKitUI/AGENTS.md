# PortholeKitUI – Module Shape

PortholeKitUI is Porthole's on-device pairing/status UI: `PortholePairingView`
plus the Broadway `PortholeStylesheet` and `portholeBroadwayRoot()`. See
[`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- **SwiftUI + PortholeKit + BroadwayCore/BroadwayUI.** No app code, no client
  side — it binds to a `Porthole`'s observable `state` and calls its
  `start()`/`stop()`/`revoke(_:)`.
- Broadway is linked statically here (like PeriscopeTools), so the view can seed
  its own root. If this ever becomes/embeds a dynamic framework, follow WhereUI's
  rule: consumers must not re-link Broadway or the type-keyed environment splits.

## Invariants

- **Each public view seeds its own Broadway root** (`portholeBroadwayRoot()`) and
  its content reads `@Environment(\.stylesheet)`; appearance tokens live in
  `PortholeStylesheet`, not inline. The trait-reactive slice (pairing-code
  tracking) applies only in `init(context:)` so a system context reproduces
  `default`.
- **Bind to observable state, don't fake it.** The advertising control is a
  start/stop action (start can throw → surfaced via an alert), not a two-way
  `Bool` binding, since `state.isAdvertising` is `internal(set)`. No
  `Binding(get:set:)`.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeKitUITests`, `extraPackageProducts: [PortholeKit, PortholeCore]` — not
Broadway, which comes transitively). Pin default tokens; use a hosted probe for
the trait-aware boundary crossing and a render smoke test.
