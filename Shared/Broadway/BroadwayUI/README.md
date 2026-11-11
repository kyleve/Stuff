# BroadwayUI

UIKit + SwiftUI components that carry a `BContext` (from BroadwayCore) through the view hierarchy.

## Public API

- **`BRootViewController`** — a container view controller that owns the root `BContext`, observes system trait changes via `BTraitsObserver`, and republishes the context to descendants through `traitOverrides`. The designated initializer wraps any `UIViewController`. A convenience initializer hosts SwiftUI content directly.
- **`BRootView` / `.broadwayRoot(themes:)`** — the SwiftUI-native root. Seeds a root `BContext` from the live system traits (`@Environment(\.colorScheme)`, `\.dynamicTypeSize`, both size classes, and `BAccessibility.changes()`) plus the given `themes`, and injects it so descendants read `@Environment(\.bContext)`. Unlike the UIKit root it takes `themes`, letting an app seed palette/typography at the root.
- **`BTraitOverridesViewController`** — scopes trait overrides to a subtree while preserving inherited base traits and themes.
- **SwiftUI bridges** — `BContext+SwiftUI` resolves `@Environment(\.bContext)`, preferring a synchronous pure-SwiftUI value (set by `BRootView` / `broadwayRoot` / `bTraitOverrides`, and mirrored into UIKit traits so it also reaches nested UIKit) and falling back to the UIKit trait-bridged value when none is set. Plus `BTraitOverrides+SwiftUI` and the `BMode` / `BContentSizeCategory` initializers from `ColorScheme` / `DynamicTypeSize` (`BTraitValues+SwiftUI`).

## Usage

```swift
let root = BRootViewController {
    ContentView() // SwiftUI content
}
window.rootViewController = root
```

`context` is `nil` until the controller enters a valid hierarchy.
Setup (child creation, trait observation, and the initial context) runs on `viewIsAppearing`.

In a pure-SwiftUI app, wrap the root view instead — no UIKit host required:

```swift
WindowGroup {
    ContentView() // reads @Environment(\.bContext)
        .broadwayRoot(themes: appThemes)
}
```

The root observes horizontal and vertical size classes through SwiftUI.
Missing or unknown size classes resolve to compact on both axes, matching the UIKit bridge.
Later explicit values update the context normally.
`bHorizontalSizeClass(_:)` and `bVerticalSizeClass(_:)` scope Broadway layout policies to a subtree.
These overrides affect stylesheets; native container traits remain under system control.

## Scroll restoration

`BScrollPosition` exposes a native `ScrollPosition` binding. Add
`.bScrollRestorationScope()` to a stable ancestor to retain positions when its
descendants are replaced. A caller-owned `BScrollRestorationStore` can also be
supplied to the modifier. Without a scope, positions remain local to the view.

Initialize the wrapper with the view type, a typed role, a context token, and the
scroll target ID type. Independent panes need independent roles or scopes.
Changing context (for example, region or year) discards the previous position;
returning to that context starts fresh. Old bindings retain their detached entry
and cannot overwrite its replacement. Stores belong to one scene/session.

Views choose initial anchors, wait for content, and handle missing targets.
Call `_position.initialize(ScrollPosition(id: target, anchor: .top))` after content
is ready. This applies the initial policy once per context, even if native layout
already reported a provisional first item. Later calls preserve the retained position.
The store neither interprets application data nor synchronizes separate panes.
Use identified content and alignment for restoration; pixel offsets are not a
cross-layout restoration contract. Guards: `BScrollPositionTests`.

## Install

Local SPM library declared in the root [`Package.swift`](../../../Package.swift) (depends on BroadwayCore): `.package(product: "BroadwayUI")`.
Run tests with `./test BroadwayUITests`.
