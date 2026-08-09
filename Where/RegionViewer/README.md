# RegionViewer

A thin standalone app that hosts the **WhereUI** `RegionMapView` developer
tool, so you can inspect the bundled region geometry on a real map outside the
full **Where** app. Built primarily for **Mac Catalyst** (it also runs on
iPhone/iPad), it's a precursor surface for expanding the number and quality of
regions the app supports.

## What it shows

The same screen as the in-app **developer overlay → Region map** entry:

- A segmented toggle between two geometries:
  - **Attribution** — the simplified polygons `RegionAttributor` actually loads
    and uses to attribute coordinates today (California, New York, and the
    simplified Canada / EU outlines; exterior rings only).
  - **Source** — every feature decoded straight from the bundled per-region
    GeoJSON files at full authored fidelity. `RegionGeometryCatalog`'s
    `buildSourceOutlines()` walks `RegionCatalog.shared.entries` and decodes each
    region's own file under `RegionKit/Sources/Resources/regions/`, so this mode
    shows exactly what ships. (The monolithic `us-states.geojson` under
    `RegionKit/Tools/source/` is a build-time input to the extraction tooling —
    never bundled, never read at runtime.)
- `MapPolygon` overlays tinted by `RegionStyle` for known regions and a stable
  per-title color for unmapped source features.
- A camera framed to the shown geometry, and a filterable legend that narrows
  the map to a single feature (keeping the dense source geometry responsive).

## Running it

The app is a Tuist target (`com.stuff.regionviewer`). Build and run from the
generated Xcode project, or from the CLI:

```bash
./ide --no-open                 # regenerate the Xcode project
mise exec -- tuist build RegionViewer
```

(Builds, like the rest of the project, are **macOS-only** — see the root
[`AGENTS.md`](../../AGENTS.md).)

### Build it with an SDK that matches your macOS

As the only Mac Catalyst target, RegionViewer is sensitive to a
build-SDK-vs-running-OS skew that the iOS-only targets never hit. **Build
it with an Xcode whose SDK matches the macOS you'll run it on** (e.g.
Xcode 26.x → macOS SDK 26.x on macOS 26). If you build with a *newer*
Xcode (say a beta one OS ahead), launch fails with a `dyld` error like:

```
dyld: Symbol not found: _UIFontTextStyleCallout
  Referenced from: …/RegionViewer.app/Contents/MacOS/RegionViewer.debug.dylib
  Expected in:     …/AppKit.framework/Versions/C/AppKit
```

It's not a code or project-config problem: the newer Catalyst SDK records
some UIKit font symbols (`_UIFontTextStyleCallout`, `_NSFontAttributeName`,
`UIFont`, `_UIFontWeightRegular`) as re-exported through AppKit, but the
older OS's AppKit doesn't vend them yet. Fixes:

- Running from the **Xcode GUI**: open the project in the matching stable
  Xcode (the GUI uses its *own* bundled SDK, regardless of `xcode-select`).
- Running CLI builds (`tuist` / `./ide`): point the command-line tools at
  it — `sudo xcode-select -s /Applications/Xcode.app`.

CI is unaffected — it runs the iOS-simulator `Stuff-iOS-Tests` scheme on the
`xcode-27` image and never launches the Catalyst app, so the build-SDK / running-OS
skew above doesn't apply there.

## How it works

`RegionViewerApp` is just a `@main App` with a
`WindowGroup { NavigationStack { RegionMapView() } }`. It has **no**
`WhereSession`, SwiftData store, or App Group — `RegionMapView` reads geometry
from `RegionKit`'s public `RegionGeometryCatalog`, which only needs the bundled
GeoJSON (embedded via the RegionKit dependency). The catalog decodes off the
main thread, so the heavy source parse never blocks the UI.

## Limitations

- Holes (interior rings) aren't drawn — `MapPolygon` fills exterior rings only,
  consistent with what attribution uses.
- Rendering all source features at once is dense; use the legend to filter to a
  single feature for the detailed geometry.
