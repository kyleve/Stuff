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
  (`rawValue`, e.g. `"us-CA"`, `"ca-ON"`), with a `localizedName`. It is **not**
  a hardcoded enum: the set of *available* regions is data (see `RegionCatalog`).
  Conveniences (`.california`, `.newYork`, `.ontario`, `.europeanUnion`, `.other`)
  read naturally at call sites. `.other` is the catch-all sentinel (no geometry).
  (Day-count *ranking* lives in `WhereCore`, not here.)
- **`RegionCatalog`** reads all geographic nodes from the bundled `regions.json`.
  Use `node(for:)` for a loggable region or `node(id:)` for any node. A node has a
  jurisdiction `kind`, localized name and optional loggable `region`. Each US or
  Canadian subdivision carries its parent ID and a pair of boundaries.
  `parent(of:)` and `children(of:)` look up its immediate relatives entirely in
  memory. `all` and `entries` preserve the manifest order of loggable regions.
- **`Coordinate`** — a plain WGS84 latitude/longitude value type (no
  CoreLocation), plus geometry primitives `GeoPolygon`, `BoundingBox`, and the
  antimeridian-aware `LongitudeSpan`.
- **`RegionAttributor`** / **`RegionAttributing`** — `region(at:)` maps a
  coordinate to its `Region` (bounding-box pre-pass, then an even-odd ray-cast),
  and `distanceToBoundary` measures nearness to a named region's edge. Caller
  order determines which tracked region wins where publishers' polygons overlap.
  `matchWithBoundaryDistance(at:)` also checks an earlier region's edge when
  crossing it could change the winner. An attributor loads the files for its
  tracked set, including water assigned to each jurisdiction. `.all` covers all 66 available regions. `.shared` tracks
  California, New York and the European Union.
- **`RegionGeometryCatalog`** supplies shoreline geometry for rendering. A card
  calls `await displayOutlines(for: region)` to load one region’s artwork.
  The developer map draws the outlines from `try await displayGeometry(for:)`.
  The returned geometry also supports coordinate lookup with `region(containing:)`.
  Uncovered water returns `nil`. Input order decides overlaps.
  The developer map can call `trackingOutlines(for: attributor)` to inspect
  the polygons used by a loaded tracker. Consumers choose screen-size
  simplification through `RegionGeometrySimplifier`.
- **`RegionDataSource.all`** lists each boundary product, its publisher,
  licence, fidelity, covered regions and use. Settings → About renders these
  credits. The EU’s original artwork serves both purposes.
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
131 geometry files for 66 loggable IDs. Under `regions/`, `us/` holds the 52 US jurisdictions,
`ca/` holds the 13 Canadian provinces and territories, and `eu/` holds the EU bloc outline.
Canada and the US have catalog nodes for looking up each subdivision’s parent.
Users can track individual subdivisions and the EU bloc.

### `regions.json` — the catalog manifest

The ordered array has one entry per geographic node.

```json
{ "id": "us-CA", "name": "California", "kind": "state", "isLoggable": true,
  "parentID": "united-states", "localizationKey": "region.california",
  "geometry": {
    "tracking": { "file": "us/us-CA.tracking.twkb", "product": "censusTIGER", "year": 2026 },
    "display": { "file": "us/us-CA.display.twkb", "product": "censusCartographic", "year": 2025 }
  } }
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
- Each `geometry` descriptor identifies its file relative to `regions/`, source product and vintage. The EU uses the same undated file for each purpose. Country entries omit geometry.
  To find their children, use the catalog’s index of `parentID` values.
- Array order fixes the order of available regions and the day-count ranking
  tiebreak. WhereCore also uses it to order its tracked set for GPS attribution.

### Per-region geometry

Each North American file holds a 2D MultiPolygon in [Tiny Well-Known Binary](https://github.com/TWKB/Specification/blob/master/twkb.md). Its integer deltas preserve all seven decimal places of the normalized GeoJSON, including every island and interior ring. Tracking files serve GPS attribution, distance and confidence. Display files serve artwork, projected dots and map overlays. A fix north of Port Jefferson in Long Island Sound can count toward New York while falling outside its displayed shoreline. The EU retains its existing plain GeoJSON. A Toronto fix matches Ontario when the user tracks it. Otherwise the tracked attributor returns `.other`, and a full-catalog lookup can still identify Ontario.

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
ruby "$tool" --refresh --us-year 2026 --us-display-year 2025 --ca-year 2026 --cache "$cache" --output /tmp/regions-candidate
ruby "$tool" --replay /tmp/regions-candidate/sources.lock.json --cache "$cache" --output /tmp/regions-replay
diff -qr /tmp/regions-candidate /tmp/regions-replay
```

Release locks use format 4. The two US products have independent vintage flags.
Both Canadian products use `--ca-year`. To upgrade an older release, refresh
with all three years. The checkout that published an older lock can replay it.

Refresh checks the publisher inventory and prints changed pins for previously
adopted URLs. Replay reads exclusively from the verified download cache. Both
write to a new directory. Inspect `report.json` for component counts, source and
candidate classifications, and the displacement bounds under `trackingAccuracy`.
`bundle-report.json` lists shipped bytes by role and the default tracking files.

Every generated tracking boundary must stay within **25 m** of its original
publisher geometry, in both directions along the entire boundary. The updater
starts with a 180 m area-based simplification and restores source vertices on
edges that exceed its 24 m working threshold. Both owners of a shared edge
retain the same vertices. The verifier follows every island and hole in the
decoded TWKB back to the original coordinates, accounting for rounding and
source repairs. The report binds the publisher inputs and encoded tracking
files by SHA-256. Review the bounds and any repairs
before adoption. The cap measures error introduced by conversion. Source survey
precision and the device’s reported GPS accuracy are separate quantities.

```sh
ruby "$tool" --adopt /tmp/regions-candidate
ruby "$tool" --check
```

Adoption verifies source and output hashes before it installs the normalized inputs and generated bundle together. After interruption, rerun the no-argument command to finish the journaled release offline. If validation rejects a changed publisher source, keep the last good release, inspect the reported ID or checksum and refresh into a fresh candidate directory.

### Source data (not bundled)

- **US tracking.** The 2026 Census TIGER/Line STATE archive defines state and equivalent boundaries, including assigned water. The updater checks all 56 source IDs and ships the existing 52 jurisdictions. [TIGER/Line STATE](https://www2.census.gov/geo/tiger/TIGER2026/STATE/)
- **US display.** The independently published 2025 Census 1:500,000 cartographic file supplies a generalized shoreline. RegionKit retains the publisher’s detail. Both Census products are public domain. [Cartographic state boundaries](https://www2.census.gov/geo/tiger/GENZ2025/shp/cb_2025_us_state_500k.zip)
- **Canadian tracking.** Statistics Canada’s 2026 digital province and territory boundaries include assigned coastal water. The updater requests each WGS84 feature at full precision, checks its ring and vertex counts against the native-coordinate response and applies the common displacement cap. [Digital boundaries](https://geo.statcan.gc.ca/geo_wa/rest/services/2026/Digital_boundary_files/MapServer/0)
- **Canadian display.** Statistics Canada’s 2026 detailed cartographic boundaries represent land and coastal islands. The 45 m area-based simplification preserves narrow Maritime waterways that disappeared at 180 m. Inland water coverage varies by product and lake. Contains information adapted from Statistics Canada under the Open Government Licence – Canada. [Cartographic boundaries](https://geo.statcan.gc.ca/geo_wa/rest/services/2026/Cartographic_boundary_files/MapServer/0), [Canadian licence](https://open.canada.ca/en/open-government-licence-canada)
- **EU tracking and display.** The European Union uses the repository’s approximate hand-drawn GeoJSON for both roles.

## Adding a region

Map the publisher ID to a stable app ID in the source adapter. Assign the node's immediate parent, jurisdiction kind, tracking eligibility and both source products. Verify a known interior location, add the applicable membership check and update the compatibility gates before shipping a new writable ID. RegionKit resolves a display name from the optional localization key or the publisher's English name.

When adding a publisher source, pass its original coordinates and pinned input hashes to the shared tracking converter. Require an accuracy result for every encoded tracking region from that source. Display uses the cartographic detail appropriate to the app’s maps and artwork. For the first geometry from another country or bloc, map its catalog ID to a directory in `RegionGenerator::GEOMETRY_GROUPS`.

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
"$REGIONKIT_PYTHON" -B -m unittest discover -s Where/RegionKit/Tools -p 'test_*.py'
./test RegionKitTests
```
