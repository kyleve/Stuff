# Flyover

Flyover is a DEBUG-oriented SwiftUI browser for seeing an app's screens as one
zoomable navigation map or a linear list. Every card renders a real screen
against state supplied by the host app, shows its push/modal relationships, and
can carry local controls for switching variants or changing the state it
displays. Selecting a card opens a full-screen live inspector.

Flyover owns presentation, not app discovery or data. The host supplies a typed
catalog and should build its screen content from an isolated in-memory world.
Flyover never opens a store, persists preferences, or resolves app globals.

## Installation

Add the local product to a UI target:

```swift
.target(
    name: "YourUI",
    dependencies: [.target(name: "Flyover")],
)
```

## Quick start

```swift
import Flyover
import SwiftUI

enum Screen: Hashable {
    case home
    case details
}

let catalog = FlyoverCatalog(
    groups: [
        FlyoverGroup(
            id: FlyoverGroupID("main"),
            title: "Main flow",
            root: Screen.home,
            screens: [
                FlyoverScreen(
                    id: .home,
                    title: "Home",
                    variants: [
                        FlyoverVariant(
                            id: FlyoverVariantID("default"),
                            title: "Default",
                        ) {
                            HomeView()
                        },
                    ],
                ),
                FlyoverScreen(
                    id: .details,
                    title: "Details",
                    variants: [
                        FlyoverVariant(
                            id: FlyoverVariantID("default"),
                            title: "Default",
                        ) {
                            DetailsView()
                        },
                    ],
                ),
            ],
        ),
    ],
    transitions: [
        FlyoverTransition(from: Screen.home, to: .details, kind: .push),
    ],
)

FlyoverView(catalog: catalog)
```

## Catalog API

- `FlyoverCatalog` owns groups and forward transitions.
- `FlyoverGroup` gives a cluster a title and graph root.
- `FlyoverScreen` owns a viewport, optional grid override, variants, controls,
  and reset action.
- `FlyoverVariant` stores lazy overview and focused content builders. The common
  initializer supplies the same builder to both; a second initializer allows
  an optimized overview and fully interactive focused view. Existing
  `SnapshotCase` content can be adapted directly.
- `FlyoverTransition` records a `.push` or `.modal` edge. Incoming edges produce
  inferred Back or Dismiss cues.
- `FlyoverControl` supplies standard toggle, picker, slider, stepper, and action
  factories. The custom-controls view builder on `FlyoverScreen` handles richer
  typed controls without widening Flyover's model.

Catalog validation reports duplicate group and screen IDs, duplicate variant
and control IDs within a screen, missing group roots, dangling route endpoints,
duplicate routes, and conflicting explicit positions. An invalid catalog
renders a diagnostic instead of a partial map.

## Presentation

The bottom bar switches between canvas/list modes and controls zoom, device,
orientation, color scheme, Dynamic Type, contrast, layout direction, and bold
text. These settings are kept only for the current Flyover session and are
applied to screen content through SnapshotKit's trait renderer. On compact
widths, the bar scrolls horizontally so every control remains reachable.

Overview content deliberately ignores hit testing so dozens of embedded
navigation stacks cannot compete with the canvas. Its controls stay live. Open a
card's inspector for native scrolling, navigation, buttons, and forms.
The canvas live-loads the six visible frames nearest its viewport center and
unloads them as they leave that set. Other cards remain lightweight
placeholders; requesting one manually replaces automatic loading with that
single pinned preview until it is paused. Opening the focused inspector unloads
the underlying canvas previews. Variant builders are deferred and serialized,
with a render opportunity between builds, so expensive preview-model
construction cannot accumulate in one SwiftUI update.

The initial canvas zoom fits the graph to the available width so its cards are
immediately legible and the remaining groups can be reached by vertical
scrolling. **Fit All** remains available for a whole-graph overview.

## App integration

Keep the catalog in the app UI module behind `#if DEBUG`. Build and retain one
catalog for the Flyover session so reevaluating the host view does not recreate
its fixtures. Build one isolated, in-memory world and inject that same world
into every registered screen. Do not activate it as the app's real scope or
route it through global persistence. Synthetic variants are appropriate for
states the demo fixture cannot produce cleanly, such as empty, unavailable, or
error content.

Registration is explicit in version one. Swift macros cannot discover all
conformers or navigation destinations across a module, and a generated source
scan would add build ordering and cache invalidation complexity. The typed
catalog is searchable, reviewable, and can be completeness-tested against a
`CaseIterable` app screen enum.

## Testing

Run unit coverage with:

```sh
./test FlyoverTests
```

The visual canvas/list contract is owned by `FlyoverSnapshotTests` in the shared
snapshot scheme:

```sh
./test --snapshots
```
