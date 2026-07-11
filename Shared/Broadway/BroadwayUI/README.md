# BroadwayUI

UIKit + SwiftUI components that carry a `BContext` (from BroadwayCore) through
the view hierarchy.

## Public API

- **`BRootViewController`** — a container view controller that owns the root
  `BContext`, observes system trait changes via `BTraitsObserver`, and
  republishes the context to descendants through `traitOverrides`. The
  designated initializer wraps any `UIViewController`; a convenience initializer
  hosts SwiftUI content directly.
- **`BRootView` / `.broadwayRoot(themes:)`** — the SwiftUI-native root. Seeds a
  root `BContext` from the live system traits (`@Environment(\.colorScheme)`,
  `\.dynamicTypeSize`, and `BAccessibility.changes()`) plus the given `themes`,
  and injects it so descendants read `@Environment(\.bContext)`. Unlike the UIKit
  root it takes `themes`, letting an app seed palette/typography at the root.
- **`BTraitOverridesViewController`** — scopes trait overrides to a subtree
  while preserving inherited base traits and themes.
- **SwiftUI bridges** — `BContext+SwiftUI`, `BTraitOverrides+SwiftUI`, and
  `BMode` / `BContentSizeCategory` initializers from `ColorScheme` /
  `DynamicTypeSize` (`BTraitValues+SwiftUI`).

## Usage

```swift
let root = BRootViewController {
    ContentView() // SwiftUI content
}
window.rootViewController = root
```

`context` is `nil` until the controller enters a valid hierarchy; setup (child
creation, trait observation, and the initial context) runs on `viewIsAppearing`.

In a pure-SwiftUI app, wrap the root view instead — no UIKit host required:

```swift
WindowGroup {
    ContentView() // reads @Environment(\.bContext)
        .broadwayRoot(themes: appThemes)
}
```

## Install

Local SPM library declared in the root [`Package.swift`](../../../Package.swift)
(depends on BroadwayCore): `.package(product: "BroadwayUI")`. Run tests with
`tuist test BroadwayUITests`.
