# BroadwayUI – Module Shape

BroadwayUI provides UIKit and SwiftUI components that own and propagate a `BContext` down the view hierarchy. Key types: `BRootViewController` (UIKit root container and trait observation), `BRootView` / `.broadwayRoot(themes:)` (SwiftUI-native root), and `BTraitOverridesViewController` (scoped overrides). It depends on **BroadwayCore**, **ViewDocumentCore**, and **ViewDocumentUI**. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../../AGENTS.md) and the group [`../AGENTS.md`](../AGENTS.md) first.

## Scope & invariants

- **Keep shared components here only.** Put app-specific views in BroadwayCatalog.
- **Defer `BRootViewController` setup** until the controller enters a valid hierarchy (`viewIsAppearing`). Before then, `context` is `nil`.
- **The controller publishes context to descendants through `traitOverrides.bContext`.**
- **Do not add `BTraitsObserver` to `BRootView`.** SwiftUI re-evaluates `body` on color-scheme and Dynamic Type changes.
- **A `.task` mirrors `BAccessibility.changes()` into state.** Both rebuild the injected `BContext`.
- **Context-building lives in `BRootContext.make(...)`.** That makes the trait mapping testable without a host.
- **Make `\.bContext` prefer a synchronous SwiftUI value, and mirror to UIKit.**
- **`BContext+SwiftUI` stores a SwiftUI-set context in a pure-SwiftUI `EnvironmentKey`.** That covers `BRootView`, `broadwayRoot`, and `bTraitOverrides`.
- **Read it synchronously.** Do not round-trip through `UITraitCollection`. Do not accept first-frame lag.
- **Mirror the value into the UIKit trait system** so nested UIKit views receive it.
- **If none is set, fall back to the UIKit trait-bridged value.** Then a `BRootViewController`-set context still reaches SwiftUI.

## Testing

Run `BroadwayUITests` in `StuffTestHost`, linking `TestHostSupport` (`./test BroadwayUITests`).

- Document decorations use validated, prepared content. Resolve scales and accessibility from the Broadway slice; inject host activity and snapshot motion policy. Keep networking and product attachment names in consumers.
- Compose native content with `BSurface`. Its finish owns the inner material or transition source; exterior artwork stays outside that finish.
- Host artwork through validated `BArtworkPlacement` and `BArtworkLayer`. Keep paint bounds separate from layout and interaction. The parent reserves gaps and retains viewport clipping.
- Essential layers remain visible under accessibility simplification. Exterior artwork may paint only in its bounded edge band and exterior zone; native content remains protected.
