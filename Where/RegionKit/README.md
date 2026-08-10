# RegionKit

The geometry and region-lookup engine behind the Where app. Given a WGS84
`Coordinate`, RegionKit answers *which `Region` is it in?* — backed by bundled
GeoJSON polygons loaded **on demand, per region**. It is pure Swift + Foundation
(no SwiftUI, UIKit, SwiftData, or CoreLocation), so it can be reused and
unit-tested in isolation.

RegionKit is the lowest layer of the Where feature: `WhereCore` (and, through
it, `WhereUI`, the widgets, and the RegionViewer) depend on RegionKit and call
into it for lookup. RegionKit depends only on
[`PeriscopeCore`](../../Shared/Periscope/PeriscopeCore) for logging.

## What you get

- **`Region`** — a `Hashable`/`Codable` value type wrapping a stable string id
  (`rawValue`, e.g. `"us-CA"`, `"canada"`), with a `localizedName`. It is **not**
  a hardcoded enum: the set of *available* regions is data (see `RegionCatalog`).
  Conveniences (`.california`, `.newYork`, `.canada`, `.europeanUnion`, `.other`)
  read naturally at call sites; `.other` is the catch-all sentinel (no geometry).
  (Day-count *ranking* lives in `WhereCore`, not here.)
- **`RegionCatalog`** — the catalog of available regions, loaded from the bundled
  `regions.json` manifest: `all`, `localizedName(for:)`, canonical order, and the
  per-region geometry files. Adding a region is a data change, not a code change.
- **`Coordinate`** — a plain WGS84 latitude/longitude value type (no
  CoreLocation), plus geometry primitives `GeoPolygon`, `BoundingBox`, and the
  antimeridian-aware `LongitudeSpan`.
- **`RegionAttributor`** / **`RegionAttributing`** — `region(at:)` maps a
  coordinate to its `Region` (bounding-box pre-pass, then an even-odd ray-cast),
  and `distanceToBoundary` measures nearness to a region's edge. An attributor is
  built for a **specific set of regions** (`RegionAttributor(for:)`) and loads
  only those regions' files; `.all` covers the whole catalog and `.shared` the
  default four. `RegionAttributing` is the protocol the app's live, swappable
  attributor also conforms to.
- **`RegionGeometryCatalog`** — read-only drawable `RegionOutline`s: a cached,
  per-region path for UI artwork, plus the developer region-map viewer's
  `.attribution` view of a given attributor and `.source` view of the whole
  catalog. `RegionGeometrySimplifier` can derive reduced geometry at a
  consumer-chosen normalized tolerance without imposing UI sizes on RegionKit.
- **`RegionDataSource`** — where the bundled geometry came from: the boundary
  set's name, its links, its `License`, its `Fidelity` (`.authoritative` vs the
  `.approximate` hand-drawn outlines), and the regions it covers.
  `RegionDataSource.all` derives coverage from the catalog, and the Where app's
  Settings > About screen renders it. Untranslated by design — these are proper
  nouns and legal terms, and the UI supplies the localized framing.
- **`RegionLog`** — RegionKit's Periscope logging facade: one `"RegionKit"`
  root scope with a typed `LogEvent` per collaborator (`RegionAttributor`,
  `RegionCatalog`, `RegionGeometryCatalog`), emitted into the process-wide
  `Periscope.shared` system. The bundled-data loads are also timed as budgeted
  spans — the manifest decode, the full polygon load, and each region's geometry
  on its own — so a slow attributor build can be traced to the region
  responsible.

## Installation

`RegionKit` is a local SPM library in this repo (`Where/RegionKit`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "RegionKit")])
```

## Quick start

```swift
import RegionKit

let region = RegionAttributor.shared.region(at: Coordinate(latitude: 37.77, longitude: -122.42))
// -> .california
print(region.localizedName) // "California"
```

## Bundled data

The catalog manifest and one GeoJSON file per region ship in
`Sources/Resources/`. Both are **generated** — never hand-edit them.

### `regions.json` — the catalog manifest

An ordered array of entries, one per available region:

```json
{ "id": "us-CA", "name": "California", "localizationKey": "region.california",
  "geometry": { "file": "us-CA.geojson" } }
```

- `id` — a stable data identifier, never shown to the user. US states are
  `us-<USPS>` (`us-CA`, `us-NY`, …); countries/blocs use a slug (`canada`,
  `european-union`). The `other` catch-all isn't in the manifest — it's a
  sentinel with no geometry.
- `name` — the English display name (the `localizedName` fallback).
- `localizationKey` — optional; when present, `localizedName` resolves it from
  `Localizable.xcstrings` (`bundle: .module`), else falls back to `name`. Only
  the handful with existing translations carry one. (Dynamic ids mean names are
  data, so region names lose static string-catalog extraction — a deliberate
  trade-off.)
- `geometry.file` — the per-region file under `regions/`.
- **Array order is the catalog's canonical order** (US states alphabetically,
  then countries/blocs, blocs last): it fixes attribution first-match priority
  (regions are mutually exclusive at our resolution) and the day-count ranking
  tiebreak.

### `regions/<id>.geojson` — per-region geometry

One FeatureCollection per region (a single `Polygon`/`MultiPolygon` feature,
exterior rings only). `RegionAttributor` loads only the files for the regions
it's asked to attribute, so we never parse the whole US at launch.

### Regenerating

`regions/` and `regions.json` are generated from the (non-bundled) source data
under [`Tools/source/`](Tools/source) by
[`Tools/generate-regions.rb`](Tools/generate-regions.rb) — re-run it from the
repo root after changing the source (the `NAME → us-<USPS>` map lives in the
script):

```sh
ruby Where/RegionKit/Tools/generate-regions.rb
```

The retained-tool Minitest suite runs the generator against temporary geometry
and output roots, checking ordering, metadata, stale-output cleanup, and
byte-for-byte idempotence; use the Ruby test-loader command in `Tools/README.md`.

### Source data (not bundled)

Each entry below is also expressed in code as a `RegionDataSource`, which is
what the app credits on its About screen; keep the two in step.

- **`us-states.geojson`** — US state boundaries (50 states + DC + PR),
  `MultiPolygon` per feature keyed by `properties.NAME`; the generator splits it
  into one `regions/us-<USPS>.geojson` per feature. Originally
  `gz_2010_us_040_00_5m.json` (5m, 2010 census) from
  [eric.clst.org/tech/usgeojson](https://eric.clst.org/tech/usgeojson/),
  converted from US Census Cartographic Boundary Files. License: US Government
  works are public domain (17 U.S.C. § 105); attribution requested (see the repo
  `README.md`).
- **`canada.geojson` / `europeanUnion.geojson`** — hand-simplified outlines,
  deliberately coarse (fine for `RegionAttributorTests` spot-checks; should be
  replaced with higher-fidelity public-domain sources before any production
  residency-audit use).

## Adding a region

Adding a region is now **pure data** — no new `Region` case, no code:

1. Add its geometry to `Tools/source/` (a new feature, or a new source file).
2. Run `ruby Where/RegionKit/Tools/generate-regions.rb` to regenerate
   `regions/` + `regions.json` (add the `NAME → id` mapping in the script if it's
   a new US feature; blocs/countries get an entry in the script's `NON_US` list).
3. Optionally add a `region.<key>` entry to `Localizable.xcstrings` and point the
   manifest entry's `localizationKey` at it (otherwise the English `name` shows).
4. Attribute the geometry in `RegionDataSource` — a US state is already covered
   by the `us-` rule, anything else needs its source named.
   `RegionDataSourceTests` fails until it is.
5. Add a `RegionAttributorTests` spot-check.

Everything downstream (`RegionStyle`, region pickers, the App Intents
`RegionEntity`) derives from the catalog automatically.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` (so
`Bundle.module` resolves the GeoJSON at runtime). Attribution, geometry
(point-in-polygon, bounding box, longitude span), and the geometry catalog are
covered here; internal types (`GeoJSON`, `GeoPolygon`, `RegionPolygons`) are
reached via `@testable import RegionKit`.

**GeoJSON *decoding* is not covered** — there is no `GeoJSONTests.swift`, so the
unsupported-geometry throw and the malformed-coordinate drop are unexercised, and
`RegionCatalog`'s degrade-to-empty-catalog path is asserted only at the log-event
level. Filed in [`Where/TODOs.md`](../TODOs.md); this paragraph goes away when it
closes.
