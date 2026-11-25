# RegionKit

The geometry and region-lookup engine behind the Where app. Given a WGS84
`Coordinate`, RegionKit answers *which `Region` is it in?* — backed by bundled
WGS84 polygons loaded **on demand, per region**. It uses Swift and Foundation
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
  read naturally at call sites. `.other` is the catch-all sentinel (no geometry).
  (Day-count *ranking* lives in `WhereCore`, not here.)
- **`RegionCatalog`** reads all geographic nodes from the bundled `regions.json`.
  Use `node(for:)` for a loggable region or `node(id:)` for any node. A node has a
  jurisdiction `kind`, localized name and optional loggable `region`. Each US or
  Canadian subdivision carries its parent ID and its own geometry file.
  `parent(of:)` and `children(of:)` look up its immediate relatives entirely in
  memory. `all` and `entries` preserve the manifest order of loggable regions.
- **`Coordinate`** — a plain WGS84 latitude/longitude value type (no
  CoreLocation), plus geometry primitives `GeoPolygon`, `BoundingBox`, and the
  antimeridian-aware `LongitudeSpan`.
- **`RegionAttributor`** / **`RegionAttributing`** — `region(at:)` maps a
  coordinate to its `Region` (bounding-box pre-pass, then an even-odd ray-cast),
  and `distanceToBoundary` measures nearness to a named region's edge. When
  tracked regions overlap, a matching descendant takes precedence over its
  matching ancestors. Caller order breaks ties among remaining matches.
  `matchWithBoundaryDistance(at:)` measures confidence against the winning
  region and the boundaries of its tracked descendants. An attributor is
  built for a **specific set of regions** (`RegionAttributor(for:)`) and loads
  the geometry needed for that set. Canada uses its thirteen subdivisions. `.all` covers the whole catalog and `.shared` the
  default four. `RegionAttributing` is the protocol the app's live, swappable
  attributor also conforms to.
- **`RegionGeometryCatalog`** returns drawable `RegionOutline`s. Call
  `outlines(for:)` with a region for its artwork. Canada draws its provinces and
  territories together. The developer viewer’s `.attribution` view shows the
  selected regions, and `.source` shows the individual bundled geometries.
  `RegionGeometrySimplifier` can derive reduced geometry at a
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
  Load failures carry restricted `LogError` snapshots from the original error.
  These version-2 events retain their severity and external IDs. Diagnostic export applies the snapshot's field controls.

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

The generated resources in `Sources/Resources/` contain the catalog manifest and
66 geometry files. Under `regions/`, `us/` holds the 52 US jurisdictions,
`ca/` holds the 13 Canadian provinces and territories, and `eu/` holds the EU bloc outline.
The US and Canada are country entries in the manifest.

### `regions.json` — the catalog manifest

The ordered array has one entry per geographic node.

```json
{ "id": "us-CA", "name": "California", "kind": "state", "isLoggable": true,
  "parentID": "united-states", "source": "census", "sourceYear": 2026,
  "localizationKey": "region.california", "geometryFile": "us/us-CA.twkb" }
```

- `id` — a stable data identifier, never shown to the user. US states are
  `us-<USPS>` (`us-CA`, `us-NY`, …). Canadian subdivisions use `ca-<postal code>`. Countries and blocs use a slug (`canada`,
  `european-union`). The `other` catch-all isn't in the manifest — it's a
  sentinel with no geometry.
- `name` — the English display name (the `localizedName` fallback).
- `localizationKey` — optional. When present, `localizedName` resolves it from
  `Localizable.xcstrings` (`bundle: .module`), else falls back to `name`. Only
  the handful with existing translations carry one. (Dynamic ids mean names are
  data, so region names lose static string-catalog extraction — a deliberate
  trade-off.)
- `kind` classifies the jurisdiction as `state`, `federalDistrict`, `territory`,
  `province`, `country` or `bloc`.
- `parentID` optionally names the immediate parent by its stable ID. A root
  omits this field. Parents may occur anywhere in the manifest. The loader
  rejects unresolved parents, duplicate IDs and cycles.
- `isLoggable` controls whether the node appears in tracking choices and can
  construct a validated `Region`. The independent bare-string `Codable`
  representation preserves stored IDs across catalog changes.
- `geometryFile` is a path relative to `regions/`. Country entries omit this field.
  To find their children, use the catalog’s index of `parentID` values.
- Array order fixes the order of available regions and the day-count ranking
  tiebreak. WhereCore also uses it to order its tracked set for GPS attribution.

### Per-region geometry

Each North American file holds a 2D MultiPolygon in [Tiny Well-Known Binary](https://github.com/TWKB/Specification/blob/master/twkb.md). Its integer deltas preserve all seven decimal places of the normalized GeoJSON, including every island and interior ring. The EU retains its existing plain GeoJSON. Tracking Canada loads its provinces and territories. A Toronto fix therefore matches Canada when tracked on its own and Ontario when both are tracked.

### Regenerating

Run the following from the repository root. Ruby alone can regenerate or check the adopted release offline. The source lock, conversion report and compressed normalized features live in [the release directory](Tools/source/release).

```sh
tool=Where/RegionKit/Tools/generate-regions.rb
ruby "$tool" --check
ruby "$tool"
```

Refreshing and replaying raw releases also use Python 3.12 and the [pinned GIS dependencies](Tools/requirements-boundaries.txt). Use the Python patch and native library versions recorded in the release lock to reproduce an existing release. Install the pinned binary wheels into an isolated environment. Keep your content-addressed cache outside the checkout and retain it to replay publisher bytes that may later change.

```sh
python3.12 -m venv /tmp/regionkit-gis
/tmp/regionkit-gis/bin/pip install --only-binary=:all: -r Where/RegionKit/Tools/requirements-boundaries.txt
export REGIONKIT_PYTHON=/tmp/regionkit-gis/bin/python
cache="$HOME/.cache/regionkit-boundaries"
ruby "$tool" --refresh --us-year 2026 --ca-year 2026 --cache "$cache" --output /tmp/regions-candidate
ruby "$tool" --replay /tmp/regions-candidate/sources.lock.json --cache "$cache" --output /tmp/regions-replay
diff -qr /tmp/regions-candidate /tmp/regions-replay
```

Release locks use format 2. To migrate an older format-1 release, refresh with the same publisher years and reuse the raw download cache. Replay and adoption require a format-2 lock.

If a saved format-2 candidate has a flat `resources/regions/` directory, replay its lock into a new candidate before adoption. For an already adopted release, the no-argument Ruby command reorganizes the installed files offline.

The adopted release uses a 180 m simplification setting for the US and 45 m for Canada. These settings guide an area-based algorithm. The report records sampled displacement separately. Both modes create a new output directory. Refresh checks the publisher inventory and prints changed checksums for previously adopted URLs. Replay reads exclusively from the verified cache. Inspect `report.json` for component and hole counts, simplification error and border classifications. `bundle-report.json` records the installed geometry size and the files needed for the default tracking set. Compare the candidate manifest with the installed choices before adopting it.

```sh
ruby "$tool" --adopt /tmp/regions-candidate
ruby "$tool" --check
```

Adoption verifies source and output hashes before it installs the normalized inputs and generated bundle together. After interruption, rerun the no-argument command to finish the journaled release offline. If validation rejects a changed publisher source, keep the last good release, inspect the reported ID or checksum and refresh into a fresh candidate directory.

### Source data (not bundled)

- The US Census Bureau's 2026 TIGER/Line STATE file supplies the 50 states, DC and Puerto Rico. The updater validates all 56 source IDs and emits the 52 jurisdictions Where supports. These polygons include water inside their legal boundaries. US Government works are public domain under 17 U.S.C. § 105. [Census downloads](https://www2.census.gov/geo/tiger/TIGER2026/STATE/)
- Statistics Canada's 2026 detailed cartographic files supply ten provinces and three territories. The source represents land and coastal islands, so Canadian boats or shoreline observations can fall outside it. The two publishers can disagree close to their common boundary. Contains information licensed under the Open Government Licence – Canada. Where reprojects and simplifies the published boundaries. [Province and territory layer](https://geo.statcan.gc.ca/geo_wa/rest/services/2026/Cartographic_boundary_files/MapServer/0), [licence](https://open.canada.ca/en/open-government-licence-canada)
- The European Union uses the repository's approximate hand-drawn outline. Each node's `source` identifies its credit in Settings → About.

## Adding a region

Map the publisher ID to a stable app ID in the source adapter. Assign the node's immediate parent, jurisdiction kind, tracking eligibility and source. Verify a known interior location, add the applicable membership check and update the compatibility gates before shipping a new writable ID. RegionKit resolves a display name from the optional localization key or the publisher's English name.

When adding the first geometry for another country or bloc, map its catalog ID to a directory in `RegionGenerator::GEOMETRY_GROUPS`.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` (so
`Bundle.module` resolves the generated files at runtime). Attribution, geometry
(point-in-polygon, bounding box, longitude span), and the geometry catalog are
covered here. internal types (`GeoJSON`, `GeoPolygon`, `RegionPolygons`) are
reached via `@testable import RegionKit`.

The binary reader and writer are exercised with a shared, hand-checked delta stream and malformed inputs. The source-format tests verify membership, shape completeness and projection. The release CLI tests cover offline rebuild, drift and interrupted adoption.

```sh
ruby Tools/Tests/generate_regions_test.rb
ruby Tools/Tests/region_release_test.rb
"$REGIONKIT_PYTHON" -B -m unittest discover -s Where/RegionKit/Tools -p test_convert_boundaries.py
./test RegionKitTests
```
