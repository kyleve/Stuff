# BroadwayUI – Module Shape

BroadwayUI provides UIKit and SwiftUI components that own and propagate a `BContext` down the view hierarchy. Key types: `BRootViewController` (UIKit root container and trait observation), `BRootView` / `.broadwayRoot(themes:)` (SwiftUI-native root), and `BTraitOverridesViewController` (scoped overrides). It depends on **BroadwayCore**. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../../AGENTS.md) and the group [`../AGENTS.md`](../AGENTS.md) first.

## Scope & invariants

- **Keep shared components here only.** Put app-specific views in BroadwayCatalog.
- **Defer `BRootViewController` setup** until the controller enters a valid hierarchy (`viewIsAppearing`). Before then, `context` is `nil`.
- **The controller publishes context to descendants through `traitOverrides.bContext`.**
- **Do not add `BTraitsObserver` to `BRootView`.** SwiftUI re-evaluates `body` on color-scheme, Dynamic Type, and size-class changes.
- **A `.task` mirrors `BAccessibility.changes()` into state.** Both rebuild the injected `BContext`.
- **Context-building lives in `BRootContext.make(...)`.** That makes the trait mapping testable without a host.
- **Map unavailable SwiftUI size classes to compact on both axes.** Keep this consistent with BroadwayCore's UIKit mapping.
- **Make `\.bContext` prefer a synchronous SwiftUI value, and mirror to UIKit.**
- **`BContext+SwiftUI` stores a SwiftUI-set context in a pure-SwiftUI `EnvironmentKey`.** That covers `BRootView`, `broadwayRoot`, and `bTraitOverrides`.
- **Read it synchronously.** Do not round-trip through `UITraitCollection`. Do not accept first-frame lag.
- **Mirror the value into the UIKit trait system** so nested UIKit views receive it.
- **If none is set, fall back to the UIKit trait-bridged value.** Then a `BRootViewController`-set context still reaches SwiftUI.

## Scroll restoration

- Keep scroll restoration opt-in through an explicit stable scope. Key entries by view type and typed role; a context change replaces the entry, not its value in a historical cache.
- Resolve a mount again only when its scope, key, or context changes. Capture the resolved entry in native observable bindings. Outgoing views and obsolete contexts must not write into a replacement entry. Guard: `BScrollPositionTests`.
- Views own initial positioning and missing-target policy. The shared store must not import application types or synchronize panes.

## Testing

Run `BroadwayUITests` in `StuffTestHost`, linking `TestHostSupport` (`./test BroadwayUITests`).
