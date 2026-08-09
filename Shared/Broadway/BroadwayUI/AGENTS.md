# BroadwayUI – Module Shape

BroadwayUI provides UIKit and SwiftUI components that own and propagate a `BContext` down the view hierarchy. Key types: `BRootViewController` (UIKit root container and trait observation), `BRootView` / `.broadwayRoot(themes:)` (SwiftUI-native root), and `BTraitOverridesViewController` (scoped overrides). It depends on **BroadwayCore**. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../../AGENTS.md) and the group [`../AGENTS.md`](../AGENTS.md) first.

## Scope & invariants

- **Keep shared components here only.** Put app-specific views in BroadwayCatalog.
- **Defer `BRootViewController` setup** until the controller enters a valid hierarchy (`viewIsAppearing`). Before then, `context` is `nil`. The controller publishes context to descendants through `traitOverrides.bContext`.
- **Do not add `BTraitsObserver` to `BRootView`.** SwiftUI re-evaluates `body` on color-scheme and Dynamic Type changes. A `.task` mirrors `BAccessibility.changes()` into state. Both rebuild the injected `BContext`. Context-building lives in `BRootContext.make(...)` so the trait mapping is testable without a host.
- **Make `\.bContext` prefer a synchronous SwiftUI value, and mirror to UIKit.** `BContext+SwiftUI` stores a SwiftUI-set context (through `BRootView`, `broadwayRoot`, or `bTraitOverrides`) in a pure-SwiftUI `EnvironmentKey`. Read it synchronously. Do not round-trip through `UITraitCollection`. Do not accept first-frame lag. Mirror the value into the UIKit trait system so nested UIKit views receive it. If none is set, fall back to the UIKit trait-bridged value. Then a `BRootViewController`-set context still reaches SwiftUI.

## Testing

Run `BroadwayUITests` in `StuffTestHost`, linking `TestHostSupport` (`./test BroadwayUITests`).
