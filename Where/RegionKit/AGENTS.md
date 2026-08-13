# RegionKit – Module Shape

RegionKit is the geometry and region-lookup engine for the Where feature. It
maps coordinates to `Region` attribution over bundled GeoJSON polygons. It also
provides geometry primitives and the developer-viewer geometry catalog. See
[`README.md`](README.md) for the public API and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Pure Swift + Foundation**, plus
  [`PeriscopeCore`](../../Shared/Periscope/PeriscopeCore) for logging. It must
  **not** import SwiftUI, UIKit, SwiftData, CoreLocation, or `WhereCore`. It is
  the lowest layer of the feature. `WhereCore` depends on *it*, never the
  reverse.
- Library target in [`Package.swift`](../../Package.swift)
  (`Where/RegionKit/Sources`). The generated catalog manifest + per-region
  polygons and the region-name string catalog ship in `Sources/Resources/`. The
  (non-bundled) source geometry lives in `Tools/source/`.

## Invariants

- **`Region` is a data-driven value type, not a hardcoded enum.** It wraps a
  stable `rawValue` id. The set of available regions and their metadata live in
  the bundled `regions.json` manifest, read by `RegionCatalog`. Adding a region
  is a data change (regenerate via `Tools/generate-regions.rb`), never a new
  case — see [README](README.md#adding-a-region). `regions/` + `regions.json`
  are generated. Never hand-edit them.
- **The catalog's canonical order (`RegionCatalog.all`, hence `Region.allCases`
  = catalog order then `.other`) fixes attribution priority.** An attributor
  checks its regions in order. The first polygon match wins (regions are
  mutually exclusive at our resolution). (Day-count ranking lives in
  `WhereCore`'s `Region+Ordering`, not here.)
- **Geometry access is per-region, on demand.** `RegionAttributor(for:)` loads
  only the passed regions' `regions/<id>.geojson` files. The app parses only the
  tracked set. `RegionGeometryCatalog.outlines(for: Region)` caches only the
  drawable region requested by UI artwork. Never load the whole US for one
  card. `RegionGeometrySimplifier` vends stateless, projection-aware geometry
  reduction. Rendering fidelity and render-artifact caches belong to consumers.
  `.all` loads the whole catalog (dev viewer/tests). `.shared` loads the default
  four. It is UI-free. `BoundingBox` / `LongitudeSpan` expose the min/max math.
  Drawing and MapKit conversion live in the UI layer. `RegionAttributing` lets
  `WhereCore` supply a live, swappable attributor.
- **Credit bundled geometry in code, not only in prose.** `RegionDataSource`
  states each boundary set's origin, license, and fidelity. It derives its
  coverage from the catalog. The US sources use the `us-` id prefix the generator
  mints. Everything else uses an explicit id list. Deliberately *not* an
  "everything else" fallback that would silently mis-credit a new region.
  `RegionDataSourceTests` fails when a region is covered zero times or twice.
  Regenerating the catalog must not ship uncredited data. Keep it in step with the
  [README](README.md#source-data-not-bundled) provenance notes.
- **Region names are manifest data (a documented trade-off).** `localizedName`
  resolves a manifest entry's optional `localizationKey` from the string catalog,
  else the manifest's English `name`. Dynamic ids cost static string-catalog
  extraction for region names.
- **Missing or corrupt bundled geometry (or manifest) is a programmer error.**
  The loader logs a `fault` via `RegionLog` *and* `assertionFailure`s (debug).
  In release it degrades to `.other`/an empty catalog rather than crashing.
- **Logging goes through `RegionLog`.** That is RegionKit's own `"RegionKit"`
  root scope. Never use `WhereLog`, which it cannot see. Emit into the shared
  `Periscope.shared` so the app's sink still captures it. Span the bundled-data
  loads against a budget (the manifest decode, the whole polygon load, and
  each region's geometry separately as `loadRegion(us-CA)`). One region
  with heavy geometry is otherwise invisible inside a slow attributor build.
- **Object identities are `region://` URLs.** `RegionURL` (RegionKit's local
  analog of WhereCore's `StoreURL`) builds/parses `region://<collection>/<type>`
  URLs. `Region.regionURL` vends `region://regions/<id>`. Used to key a
  `LogEvent.externalID` (see `RegionAttributorLog`) so inspect-by-object works
  without RegionKit reaching up into the app's `store://` scheme. That is a
  separate, intentionally parallel namespace. Distinct from `Region`'s
  bare-`rawValue` `Codable`, which stays the persisted form.

## Testing

Swift Testing in [`Tests/`](Tests) (`RegionKitTests`), hosted in
`StuffTestHost`. Internal types are reached via `@testable import RegionKit`.
`Tools/Tests/generate_regions_test.rb` separately exercises the data generator
against a temporary source/output tree, including cleanup and idempotence.
