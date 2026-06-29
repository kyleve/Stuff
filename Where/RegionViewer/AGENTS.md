# RegionViewer – Module Shape

A thin standalone **Mac Catalyst** (and iOS) app that hosts the WhereUI
`RegionMapView` developer tool for inspecting bundled region geometry on a real
map. See [`README.md`](README.md) for what it shows and how to run it.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app target** ([`Project.swift`](../../Project.swift),
  `Where/RegionViewer/Sources`, bundle ID `com.stuff.regionviewer`). The only
  target with `destinations: [.iPhone, .iPad, .macCatalyst]`; everything else
  uses the iPhone/iPad-only `destinations` constant.
- Depends on **WhereUI** (the `RegionMapView` screen), **WhereCore**
  (`RegionGeometryCatalog` + bundled GeoJSON, embedded transitively), and
  **LogKit**.
- Must stay a **shell only**: no domain logic, no SwiftData, no App Group, no
  `WhereSession`. All behavior belongs in `WhereUI` / `WhereCore`; if a feature
  needs more than `RegionMapView()`, add it there, not here.
- No test bundle — `RegionMapView` is covered by **WhereUI**
  (`ScreenHostingTests.regionMapViewHosts`) and the catalog by **WhereCore**
  (`RegionGeometryCatalogTests`).

## Key types

- [`RegionViewerApp`](Sources/RegionViewerApp.swift) – `@main App` whose body is
  `WindowGroup { NavigationStack { RegionMapView() } }`. That's the whole target.

## Behaviors to preserve

- **Session-less.** `RegionMapView` is `public` and self-contained precisely so
  this app needs no dependency injection. Don't introduce a session/store here.
- **Catalyst-first.** This is the project's only Catalyst target; keep it
  buildable for `ios-macabi`. Adding iOS-only API in shared modules can break
  this build — verify with `tuist build RegionViewer` on macOS.
- **No bundled GeoJSON of its own.** Region data lives in WhereCore's resource
  bundle and is embedded via the dependency; this target ships only a minimal
  `Resources/Assets.xcassets`.

## Conventions

- Follow root rules (exhaustive enum switches, small named structs, no closure
  `Binding(get:set:)`).
- Keep the `@main` shell trivial; reach for `WhereUI` for any UI and `WhereCore`
  for any data.
