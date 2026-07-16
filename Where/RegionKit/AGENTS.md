# RegionKit – Module Shape

RegionKit is the geometry and region-lookup engine for the Where feature:
coordinate-to-`Region` attribution over bundled GeoJSON polygons, plus the
geometry primitives and the developer-viewer geometry catalog. See
[`README.md`](README.md) for the public API and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Pure Swift + Foundation**, plus
  [`PeriscopeCore`](../../Shared/Periscope/PeriscopeCore) for logging. It must
  **not** import SwiftUI, UIKit, SwiftData, CoreLocation, or `WhereCore` — it is
  the lowest layer of the feature, and `WhereCore` depends on *it*, never the
  reverse.
- Library target in [`Package.swift`](../../Package.swift)
  (`Where/RegionKit/Sources`). The generated catalog manifest + per-region
  polygons and the region-name string catalog ship in `Sources/Resources/`; the
  (non-bundled) source geometry lives in `Tools/source/`.

## Invariants

- **`Region` is a data-driven value type, not a hardcoded enum.** It wraps a
  stable `rawValue` id; the set of available regions and their metadata live in
  the bundled `regions.json` manifest, read by `RegionCatalog`. Adding a region
  is a data change (regenerate via `Tools/generate-regions.rb`), never a new case
  — see [README](README.md#adding-a-region). `regions/` + `regions.json` are
  generated; never hand-edit them.
- **The catalog's canonical order (`RegionCatalog.all`, hence `Region.allCases`
  = catalog order then `.other`) fixes attribution priority** — an attributor
  checks its regions in order and the first polygon match wins (regions are
  mutually exclusive at our resolution). (Day-count ranking lives in `WhereCore`'s
  `Region+Ordering`, not here.)
- **Attribution is per-region, on demand.** `RegionAttributor(for:)` loads only
  the passed regions' `regions/<id>.geojson` files, so the app parses only the
  tracked set — never the whole US at launch. `.all` loads the whole catalog
  (dev viewer/tests); `.shared` the default four. It's UI-free: `BoundingBox` /
  `LongitudeSpan` expose the min/max math, but MapKit conversion lives in the UI
  layer. `RegionAttributing` lets `WhereCore` supply a live, swappable attributor.
- **Region names are manifest data (a documented trade-off).** `localizedName`
  resolves a manifest entry's optional `localizationKey` from the string catalog,
  else the manifest's English `name` — so dynamic ids cost static string-catalog
  extraction for region names.
- **Missing/corrupt bundled geometry (or manifest) is a programmer error** — the
  loader logs a `fault` via `RegionLog` *and* `assertionFailure`s (debug),
  degrading to `.other`/an empty catalog in release rather than crashing.
- **Logging goes through `RegionLog`** — a Periscope facade with a `"RegionKit"`
  root scope and one typed `LogEvent` per collaborator, emitted into
  `Periscope.shared`. RegionKit owns its own root scope, never `WhereLog`, but
  shares the process-wide store (the app wires the `PeriscopeStore` sink).
- **Object identities are `region://` URLs** — `RegionURL` (RegionKit's local
  analog of WhereCore's `StoreURL`) builds/parses `region://<collection>/<type>`
  URLs, and `Region.regionURL` vends `region://regions/<id>`. Used to key a
  `LogEvent.externalID` (see `RegionAttributorLog`) so inspect-by-object works
  without RegionKit reaching up into the app's `store://` scheme — a separate,
  intentionally parallel namespace. Distinct from `Region`'s bare-`rawValue`
  `Codable`, which stays the persisted form.

## Testing

Swift Testing in [`Tests/`](Tests) (`RegionKitTests`), hosted in
`StuffTestHost`. Internal types are reached via `@testable import RegionKit`.
