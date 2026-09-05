# Flyover

Flyover is a DEBUG-oriented SwiftUI browser for seeing an app's screens as one zoomable navigation map or a linear list.
Every card renders a real screen against state supplied by the host app.
It shows its push/modal relationships, and can carry local controls for switching variants or changing the state it displays.
Selecting a card opens a full-screen live inspector.

Flyover owns presentation, not app discovery or data.
The host supplies a typed catalog and must build its screen content from an isolated in-memory world.
Flyover never opens a store, persists preferences, or resolves app globals.
Its chrome resolves through Broadway's trait-aware `FlyoverStylesheet`.

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
- `FlyoverScreen` owns a viewport, optional grid override, navigation containment, variants, controls, and reset action. Screens receive an isolated `NavigationStack` by default so titles, toolbars, and destinations render with the frame. Use `.none` only for content that owns its navigation root or is not a screen, such as a widget.
- `FlyoverVariant` stores lazy overview and focused content builders. The common initializer supplies the same builder to both. A second initializer allows an optimized overview and fully interactive focused view. Existing `SnapshotCase` content can be adapted directly.
- `FlyoverTransition` records a `.push` or `.modal` edge. Incoming edges produce inferred Back or Dismiss cues.
- `FlyoverControl` supplies standard toggle, picker, slider, stepper, and action factories. The custom-controls view builder on `FlyoverScreen` handles richer typed controls without widening Flyover's model.

Catalog validation reports duplicate group and screen IDs, duplicate variant and control IDs within a screen, missing group roots, dangling route endpoints, duplicate routes, and conflicting explicit positions.
An invalid catalog renders a diagnostic instead of a partial map.

## Presentation

The bottom bar switches between canvas/list modes and controls zoom, device, orientation, color scheme, Dynamic Type, contrast, layout direction, and bold text.
These settings are kept only for the current Flyover session and are applied to screen content through SnapshotKit's trait renderer.
On compact widths, the bar scrolls horizontally so every control remains reachable.
Flyover seeds its own Broadway root for chrome.
Registered screen content keeps the isolated styling environment supplied by its host app.

Overview content deliberately ignores hit testing so dozens of embedded navigation stacks cannot compete with the canvas.
Its controls stay live.
Open a card's inspector for native scrolling, navigation, buttons, and forms.
The canvas live-loads the six visible frames nearest its viewport center and unloads them as they leave that set.
Other cards remain lightweight placeholders.
Requesting one manually replaces automatic loading with that single pinned preview until it is paused.
Opening the focused inspector unloads the underlying canvas previews.
Variant builders are deferred and serialized, with a render opportunity between builds, so expensive preview-model construction cannot accumulate in one SwiftUI update.
The canvas also tracks the latest nonempty set of visible variant/generation loads.
Snapshot capture awaits that production loading signal before intrinsic measurement, so a slow runner cannot size or capture a partially loaded canvas.
Viewport or variant changes supersede stale completions.

Groups form a top-aligned horizontal shelf while each group's navigation graph continues from left to right.
Automatic screens at the same graph depth stack up to four rows before continuing in a new column, keeping broad catalogs from producing an excessively tall canvas.
Each automatic route depth is marked by one labeled band spanning all of its overflow columns, so horizontal packing does not hide navigation depth.
Screens with no route from their group's root are collected in a separate **Unlinked** band rather than presented as a false navigation depth.
Explicit `FlyoverPosition` values remain exact and may intentionally exceed that automatic limit.
The initial canvas zoom fits the first group to the available width so its cards are immediately legible.
Reach later groups by horizontal scrolling.
Pinching or moving the zoom slider preserves the canvas point at the center of the visible viewport.
**Fit All** remains available for a whole-graph overview.

## App integration

Keep the catalog in the app UI module behind `#if DEBUG`.
Build and retain one catalog for the Flyover session so reevaluating the host view does not recreate its fixtures.
Build one isolated, in-memory world and inject that same world into every registered screen.
Do not activate it as the app's real scope or route it through global persistence.
Synthetic variants are appropriate for states the demo fixture cannot produce cleanly, such as empty, unavailable, or error content.

Present Flyover outside the app's ambient `NavigationStack`, such as from a `fullScreenCover`.
SwiftUI can promote navigation titles and toolbar items from several nested screen stacks into an ancestor stack.
A separate presentation domain keeps that chrome local to each frame.

Registration is explicit in version one.
Apps must colocate each screen's typed registration and outgoing routes beside the represented view.
Then keep their central catalog limited to grouping and assembly.
Swift macros cannot discover all conformers or navigation destinations across a module.
A generated source scan would add build ordering and cache invalidation complexity.

## Static web export

`FlyoverWebExporter` converts a DEBUG catalog into a static QA atlas. It writes
native PNG captures, `manifest.json`, and `manifest.js`. The web shell reads
`manifest.js`, so the atlas works from `file://` and any static host. The
browser changes images and navigation state. It does not run SwiftUI or
serialize `FlyoverControl` actions.

The exporter validates the complete plan before its first capture. The host
provides one stable string for each typed screen ID and one capture closure.
Stable IDs must be nonempty and unique. Variant IDs must also be nonempty and
unique within a screen. Image paths use generated ordinals, never these IDs.

Hosted variants have a `FlyoverExportPolicy` with a fixed viewport by default.
Snapshot-backed variants inherit their settle, readiness, and hook behavior.
Their frame matrix must resolve to one capture extent: fixed, intrinsic,
full-content, or two-axis full-content. A mixed matrix has no resolved policy.
The app must supply an explicit policy before export.

Profiles are additive and keep request order. No profile matrix is generated.
The built-in IDs are:

- `phone-light`, `phone-dark`, `tablet-light`, and `phone-landscape`
- `phone-small`, `phone-xxxl`, and `phone-ax3`
- `phone-contrast`, `phone-rtl`, `phone-bold`, and `phone-voiceover`

The first profile is the initial web selection. An empty profile list becomes
`phone-light`. Fixed Flyover viewports keep their size while profile traits
still apply.

Run Where's exporter from the repository root:

```sh
./flyover export
./flyover export --profile phone-light --profile phone-dark
./flyover export --output /tmp/where-flyover --profile tablet-light
```

The default output is `.build/flyover/where`, resolved from the caller's
directory. The command stages the complete site and replaces only an existing
directory marked with `.flyover-generated`. A failed capture leaves the last
successful atlas unchanged.

### Preview the export

Serve the default export on this computer:

```sh
./flyover preview
```

The command selects a free port and prints the local URL. Press Control-C to
stop the server.

Use `--lan` to open the preview to other devices on the local network:

```sh
./flyover preview --lan
./flyover preview --output /tmp/where-flyover --lan --port 8080
```

The command prints one URL for each network address that it finds. The other
device must be able to reach this computer. A macOS firewall prompt can appear.

WARNING: LAN preview has no authentication or TLS. Any device that can reach
the computer can view the native screenshots. Stop and restart the preview
after each export.

For a static host, upload the contents of the generated directory. Put
`index.html` at the selected host root or subpath. The site needs no build step.
All site URLs are relative.

The manifest compatibility boundary is `schemaVersion: 1`. It contains the
application and build identity, profiles, precomputed canvas geometry, groups,
screens, routes, and image metadata. It contains no local source or account
paths. Full-content sizing uses SnapshotKitTesting limits and convergence
rules. A sizing failure stops the export; it never substitutes a viewport
image.

The website opens the first catalog group in canvas mode. A floating control
dock keeps the canvas visible. The group panel and overview map move between
groups without recalculating the graph. The canvas keeps its position when a
state, profile, or panel changes.

Canvas and list views give active image sources to at most six nearby screenshots.
They target 24 million pixels and always show the nearest screenshot.
The inspector removes these sources while it shows one full-resolution capture.

Point to or focus a card to emphasize its connected routes. The site dims
unrelated cards and routes until the focus moves. Filters for groups, capture
extents, and route states stay in a separate panel.

Search opens a command palette. It matches group, screen, state, and connected
route names. A result opens its screen or fits its group. List mode shows the
same selection in grouped rows. State and profile changes update the native
image without changing the selected screen.

The inspector uses the full browser window. The image stays central while a
drawer supplies capture data and route links. Full-content images use a
device-width scroll area. The Fit and 100% controls change the image scale
without changing the capture.

The browser hash stores the view, screen, state, and profile. Browser Back and
Forward restore these values. The site also supplies these keyboard controls:

- Press `/` or `Command-K` to open search.
- Press `F` to fit the complete canvas.
- Press `0` to fit the current group.
- Press `+` or `-` to change the canvas zoom.
- Press an arrow key, `[` or `]`, to move between inspector screens.
- Press `I` to show or hide the inspector details.
- Press Escape to close the inspector.

## Testing

Run unit coverage with:

```sh
./test FlyoverTests
```

The visual canvas/list contract is owned by `FlyoverSnapshotTests` in the shared snapshot scheme.
Its full-canvas reference uses SnapshotKit's explicit two-axis full-content frame.
This keeps every horizontally shelved group visible at the same readable initial zoom:

```sh
./test --snapshots
```
