# Flyover – Module Shape

Flyover is an app-agnostic SwiftUI developer browser for registered screen
states and their push/modal relationships. See [`README.md`](README.md) for the
public API and integration guide. This file complements the root
[`AGENTS.md`](../../AGENTS.md), which owns build, formatting, and global
conventions.

## Scope & dependencies

- Flyover may import SwiftUI and SnapshotKit; it must not import WhereCore,
  WhereUI, persistence frameworks, or any app module.
- Apps own their typed screen IDs, demo/synthetic state, catalog construction,
  and the DEBUG-only entry point that hosts ``FlyoverView``.
- Strings in this developer-only shared tool are English literals. An app
  localizes the entry point it adds to its own UI.

## Invariants

- Catalog registration is explicit and typed; do not add source scanning,
  build scripts, or macros without revisiting the API and build-cost tradeoff.
- Overview screen content is inert. Native interaction is enabled only in the
  focused inspector; per-frame controls remain interactive in both modes.
- Variant content builders stay lazy; catalog construction must not instantiate
  off-screen views or their models.
- Canvas loading follows the viewport and keeps at most six automatic screen
  trees live; a manually requested preview replaces that set with one tree,
  and presenting the focused inspector suspends the canvas set.
- Open the canvas fitted to its width; reserve whole-graph framing for the
  explicit Fit All action.
- Invoke variant builders through the serial deferred load coordinator, never
  synchronously from a SwiftUI `body`; preview fixtures may open expensive
  in-memory stores.
- Global traits are session-only and apply to registered content, not Flyover
  chrome.
- Register forward push/modal routes only. Flyover derives Back/Dismiss cues
  from incoming routes.
- Type erase only at the heterogeneous content/control registry boundary.

## Testing

Swift Testing in [`Tests/`](Tests) covers catalog validation, graph layout, and
session state. Rendering is pinned in [`SnapshotTests/`](SnapshotTests) through
the module's `FlyoverSnapshotTests` target in the shared `StuffSnapshotTests`
scheme.
