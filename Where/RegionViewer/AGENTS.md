# RegionViewer – Module Shape

A thin standalone **Mac Catalyst** (and iOS) app hosting the WhereUI
`RegionMapView` developer tool for inspecting bundled region geometry. See
[`README.md`](README.md) for what it shows and how to run it.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & rules

- **Tuist app target** (bundle ID `com.stuff.regionviewer`), depending on
  **WhereUI**, **WhereCore**, **RegionKit** (geometry + GeoJSON, whose resource
  bundle is embedded for `RegionGeometryCatalog`), and **LogKit**. The `@main`
  body is `WindowGroup { NavigationStack { RegionMapView() } }` — that's the
  whole target.
- **Shell only, session-less.** No domain logic, SwiftData, App Group, or
  `WhereSession` here; `RegionMapView` is self-contained on purpose. If a
  feature needs more, add it in `WhereUI`/`WhereCore`.
- **The repo's only Catalyst target** — keep it buildable for `ios-macabi`
  (`tuist build RegionViewer` on macOS verifies).
- No test bundle; `RegionMapView` and the geometry catalog are covered from
  WhereUI/WhereCore.
