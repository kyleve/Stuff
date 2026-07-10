# BroadwayUI

UIKit + SwiftUI components that carry a `BContext` (from BroadwayCore) through
the view hierarchy.

## Public API

- **`BRootViewController`** — a container view controller that owns the root
  `BContext`, observes system trait changes via `BTraitsObserver`, and
  republishes the context to descendants through `traitOverrides`. The
  designated initializer wraps any `UIViewController`; a convenience initializer
  hosts SwiftUI content directly.
- **`BTraitOverridesViewController`** — scopes trait overrides to a subtree
  while preserving inherited base traits and themes.
- **SwiftUI bridges** — `BContext+SwiftUI`, `BTraitOverrides+SwiftUI`.

## Usage

```swift
let root = BRootViewController {
    ContentView() // SwiftUI content
}
window.rootViewController = root
```

`context` is `nil` until the controller enters a valid hierarchy; setup (child
creation, trait observation, and the initial context) runs on `viewIsAppearing`.

## Install

Local SPM library declared in the root [`Package.swift`](../../../Package.swift)
(depends on BroadwayCore): `.package(product: "BroadwayUI")`. Run tests with
`tuist test BroadwayUITests`.
