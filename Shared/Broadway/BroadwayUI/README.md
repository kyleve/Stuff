# BroadwayUI

## Composed surfaces

`BSurface` orders the base, interior artwork, native content, highlights, and exterior artwork.
Only native content determines layout. Supply a `finish` modifier for material treatment or the inner zoom-transition source.
The exterior layer follows that modifier and does not become part of its clipping or transition source.

Validate a `ViewArtworkPlacement` with `BArtworkPlacement` before constructing `BArtworkLayer`.
The layer hosts either a prepared document or native artwork. It clips all transforms to the declared paint bounds.
Exterior artwork also excludes the content center. Its edge band is at most 16 points and shrinks for small hosts.
The containing layout must reserve gaps and gutters. The layer does not disable scroll viewport clipping.

`BSurfaceLayerRole.essential` preserves required surface content when accessibility settings simplify ornament.
`BViewDocumentLayer` accepts that role and always retains the Reduce Motion policy.
Both artwork paths remain hidden from accessibility and ignore hit testing.

UIKit + SwiftUI components that carry a `BContext` (from BroadwayCore) through the view hierarchy.

## Public API

- **`BRootViewController`** — a container view controller that owns the root `BContext`, observes system trait changes via `BTraitsObserver`, and republishes the context to descendants through `traitOverrides`. The designated initializer wraps any `UIViewController`. A convenience initializer hosts SwiftUI content directly.
- **`BRootView` / `.broadwayRoot(themes:)`** — the SwiftUI-native root. Seeds a root `BContext` from the live system traits (`@Environment(\.colorScheme)`, `\.dynamicTypeSize`, and `BAccessibility.changes()`) plus the given `themes`, and injects it so descendants read `@Environment(\.bContext)`. Unlike the UIKit root it takes `themes`, letting an app seed palette/typography at the root.
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

## Install

Local SPM library declared in the root [`Package.swift`](../../../Package.swift) (depends on BroadwayCore): `.package(product: "BroadwayUI")`.
Run tests with `./test BroadwayUITests`.

## Portable documents

BroadwayUI consumes the independent ViewDocument libraries. Prepare and validate a document before rendering it. Attach it with `bViewDocumentBackground` or `bViewDocumentOverlay`, passing host activity and static-motion policy. These decorations stay within the host bounds and do not receive input or accessibility focus.

`BViewDocumentStylesheet` resolves semantic dimension scales from the current content-size category. Reduce Motion selects the document's static pose. Reduce Transparency and Increased Contrast hide decorations. The renderer does not load assets or fetch documents.
