# RegionViewer

A thin standalone app that hosts the **WhereUI** `RegionMapView` developer tool.
You can inspect the bundled region geometry on a real map outside the full **Where** app.
Built primarily for **Mac Catalyst** (it also runs on iPhone/iPad).
It is a precursor surface for expanding the number and quality of regions the app supports.

## What it shows

The same screen as the in-app **developer overlay → Region map** entry:

- A segmented control chooses which regions to display.
  - **Attribution** draws the polygons loaded by the supplied `RegionAttributor`. The standalone viewer uses `.all` so it can inspect every loggable region.
  - **Source** draws all 67 loggable regions in the bundled catalog. RegionKit also provides a separate on-demand lookup for the US country outline.
- `MapPolygon` overlays tinted by `RegionStyle` for known regions and a stable per-title color for unmapped source features.
- A camera framed to the shown geometry, and a filterable legend that narrows the map to a single feature (keeping the dense source geometry responsive).

## Running it

The app is a Tuist target (`com.stuff.regionviewer`).
Build and run from the generated Xcode project, or from the CLI:

```bash
./ide --no-open
mise exec -- tuist xcodebuild build -workspace Stuff.xcworkspace -scheme RegionViewer \
  -destination 'generic/platform=macOS,variant=Mac Catalyst'
```

(Builds, like the rest of the project, are **macOS-only** — see the root [`AGENTS.md`](../../AGENTS.md).)

### Build it with an SDK that matches your macOS

As the only Mac Catalyst target, RegionViewer is sensitive to a build-SDK-vs-running-OS skew that the iOS-only targets never hit.
**Build it with an Xcode whose SDK matches the macOS you will run it on** (e.g. Xcode 26.x → macOS SDK 26.x on macOS 26).
If you build with a *newer* Xcode (say a beta one OS ahead), launch fails with a `dyld` error like:

```
dyld: Symbol not found: _UIFontTextStyleCallout
  Referenced from: …/RegionViewer.app/Contents/MacOS/RegionViewer.debug.dylib
  Expected in:     …/AppKit.framework/Versions/C/AppKit
```

It is not a code or project-config problem.
The newer Catalyst SDK records some UIKit font symbols (`_UIFontTextStyleCallout`, `_NSFontAttributeName`, `UIFont`, `_UIFontWeightRegular`) as re-exported through AppKit, but the older OS's AppKit does not vend them yet.
Fixes:

- Running from the **Xcode GUI**: open the project in the matching stable Xcode (the GUI uses its *own* bundled SDK, regardless of `xcode-select`).
- Running CLI builds (`tuist` / `./ide`): point the command-line tools at it — `sudo xcode-select -s /Applications/Xcode.app`.

CI is unaffected.
It runs the iOS-simulator `Stuff-iOS-FullTests` scheme on the `xcode-27` image and never launches the Catalyst app, so the build-SDK / running-OS skew above does not apply there.

## How it works

`RegionViewerApp` is a `@main App` with a `WindowGroup { NavigationStack { RegionMapView() } }`.
It has **no** `WhereSession`, SwiftData store, or App Group.
`RegionMapView` reads bundled outlines through `RegionGeometryCatalog`. North American geometry uses Tiny Well-Known Binary and the EU uses GeoJSON. The map draws interior holes and adjusts coastline detail to the current zoom. Zoom in to inspect small islands or choose a region in the legend. [RegionKit data and sources](../RegionKit/README.md#bundled-data)
