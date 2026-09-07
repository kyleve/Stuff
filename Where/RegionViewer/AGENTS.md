# RegionViewer – Module Shape

RegionViewer is a thin standalone **Mac Catalyst** (and iOS) app. It hosts the
WhereUI `RegionMapView` developer tool for inspecting bundled region geometry.
See [`README.md`](README.md) for what it shows and how to run it.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & rules

- **Tuist app target** (bundle ID `com.stuff.regionviewer`), depending on
  **WhereUI**, **WhereCore**, and **RegionKit** (geometry + GeoJSON, whose
  resource bundle is embedded for `RegionGeometryCatalog`). The `@main`
  body is `WindowGroup { NavigationStack { RegionMapView() } }`. That is the
  whole target.
- **Shell only, session-less.** No domain logic, SwiftData, App Group, or
  `WhereSession` here. `RegionMapView` is self-contained on purpose. If a
  feature needs more, add it in `WhereUI`/`WhereCore`.
- **This is the repo's only Catalyst target.** Keep it buildable for
  `ios-macabi` (`tuist build RegionViewer` on macOS verifies).
- No test bundle. The geometry catalog is covered by `RegionKitTests`
  (`RegionGeometryCatalogTests`). `RegionMapView` is covered by WhereUI's
  snapshot bundle (`WhereUISnapshotTests`).
