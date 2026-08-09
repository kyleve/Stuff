# RegionViewer

A thin standalone app that hosts the **WhereUI** `RegionMapView` developer
tool.
You can inspect the bundled region geometry on a real map outside the
full **Where** app.
It is built primarily for **Mac Catalyst** (it also runs on
iPhone/iPad).
It is a precursor surface for expanding the number and quality of
regions the app supports.

## What it shows

The same screen as the in-app **developer overlay → Region map** entry:

- A segmented toggle between two geometries:
  - **Attribution** — the simplified polygons `RegionAttributor` actually loads
    and uses to attribute coordinates today (California, New York, and the
    simplified Canada / EU outlines. Exterior rings only).
  - **Source** — every feature decoded straight from the bundled GeoJSON files
    (all US-state features in `us-states.geojson`, plus Canada and the EU) at
    full authored fidelity.
- `MapPolygon` overlays tinted by `RegionStyle` for known regions and a stable
  per-title color for unmapped source features.
- A camera framed to the shown geometry, and a filterable legend that narrows
  the map to a single feature (keeping the dense source geometry responsive).

## Running it

The app is a Tuist target (`com.stuff.regionviewer`).
Regenerate the Xcode project with `./ide --no-open`.
Build from the generated project, or from the CLI:

```bash
./ide --no-open                 # regenerate the Xcode project
mise exec -- tuist build RegionViewer
```

(Builds, like the rest of the project, are **macOS-only** — see the root
[`AGENTS.md`](../../AGENTS.md).)

### Build it with an SDK that matches your macOS

As the only Mac Catalyst target, RegionViewer is sensitive to a
build-SDK-vs-running-OS skew that the iOS-only targets never hit.
**Build it with an Xcode whose SDK matches the macOS you will run it on** (e.g.
Xcode 26.x → macOS SDK 26.x on macOS 26).
If you build with a *newer*
Xcode (say a beta one OS ahead), launch fails with a `dyld` error like:

```
dyld: Symbol not found: _UIFontTextStyleCallout
  Referenced from: …/RegionViewer.app/Contents/MacOS/RegionViewer.debug.dylib
  Expected in:     …/AppKit.framework/Versions/C/AppKit
```

It is not a code or project-config problem.
The newer Catalyst SDK records
some UIKit font symbols (`_UIFontTextStyleCallout`, `_NSFontAttributeName`,
`UIFont`, `_UIFontWeightRegular`) as re-exported through AppKit.
The older OS's AppKit does not vend them yet.
Fixes:

- Running from the **Xcode GUI**: open the project in the matching stable
  Xcode (the GUI uses its *own* bundled SDK, regardless of `xcode-select`).
- Running CLI builds (`tuist` / `./ide`): point the command-line tools at
  it — `sudo xcode-select -s /Applications/Xcode.app`.

CI is unaffected.
It runs the iOS-simulator `Stuff-iOS-Tests` scheme on the
`xcode-27` image and never launches the Catalyst app.
The build-SDK / running-OS skew above does not apply there.

## How it works

`RegionViewerApp` is a `@main App` with a
`WindowGroup { NavigationStack { RegionMapView() } }`.
It has **no**
`WhereSession`, SwiftData store, or App Group.
`RegionMapView` reads geometry
from `RegionKit`'s public `RegionGeometryCatalog`.
It only needs the bundled
GeoJSON (embedded via the RegionKit dependency).
The catalog decodes off the
main thread.
The heavy source parse never blocks the UI.

## Limitations

- Holes (interior rings) are not drawn.
  `MapPolygon` fills exterior rings only.
  That is consistent with what attribution uses.
- Rendering all source features at once is dense.
  Use the legend to filter to a single feature for the detailed geometry.
