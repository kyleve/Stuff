# RegionKit – Module Shape

RegionKit is the geometry and region-lookup engine for the Where feature. It
maps coordinates to `Region` attribution over bundled WGS84 polygons. It also
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
- **Keep geographic nodes and tracking eligibility explicit.** Use each
  subdivision’s `parentID` for ancestry and its parent’s child index to enumerate
  subdivisions. Country nodes have no geometry and cannot be tracked.
  `Region.allCases` appends the separate `.other` sentinel to the loggable
  catalog. Preserve the relative order of existing tracking choices.
- **A GPS observation credits one region.** Preserve caller order when
  publishers' boundaries overlap. Resolve confidence against the same
  tracked set, including an earlier region whose edge can change the match.
- **Geometry access is per-region, on demand.** `RegionAttributor(for:)` loads
  only the selected geometries. Core's injected `ElsewhereResolver` may lazily
  parse the full loggable catalog on its actor for read-only historical
  enrichment. Hierarchy traversal reads metadata alone. Rendering fidelity,
  MapKit conversion and render-artifact caches belong to consumers.
- **Credit bundled geometry in code, not only in prose.** `RegionDataSource`
  states each boundary set's origin, license, and fidelity. It derives its
  coverage from the publisher of each bundled geometry file.
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
- Pass original errors through `.restricted(.errorDetails, error)`. Keep structured `LogError` payloads restricted and do not duplicate them in attachments.
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
