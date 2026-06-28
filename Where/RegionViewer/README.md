# RegionViewer

A thin standalone app that hosts the **WhereUI** `RegionMapView` developer
tool, so you can inspect the bundled region geometry on a real map outside the
full **Where** app. Built primarily for **Mac Catalyst** (it also runs on
iPhone/iPad), it's a precursor surface for expanding the number and quality of
regions the app supports.

## What it shows

The same screen as the in-app **Settings → Developer → Region map** entry:

- A segmented toggle between two geometries:
  - **Attribution** — the simplified polygons `RegionAttributor` actually loads
    and uses to attribute coordinates today (California, New York, and the
    simplified Canada / EU outlines; exterior rings only).
  - **Source** — every feature decoded straight from the bundled GeoJSON files
    (all US-state features in `us-states.geojson`, plus Canada and the EU) at
    full authored fidelity.
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

## How it works

`RegionViewerApp` is just a `@main App` with a
`WindowGroup { NavigationStack { RegionMapView() } }`. It has **no**
`WhereSession`, SwiftData store, or App Group — `RegionMapView` reads geometry
from `WhereCore`'s public `RegionGeometryCatalog`, which only needs the bundled
GeoJSON (embedded via the WhereCore dependency). The catalog decodes off the
main thread, so the heavy source parse never blocks the UI.

## Limitations

- Holes (interior rings) aren't drawn — `MapPolygon` fills exterior rings only,
  consistent with what attribution uses.
- Rendering all source features at once is dense; use the legend to filter to a
  single feature for the detailed geometry.
