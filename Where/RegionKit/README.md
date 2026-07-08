# RegionKit

The geometry and region-lookup engine behind the Where app. Given a WGS84
`Coordinate`, RegionKit answers *which tracked `Region` is it in?* — backed by
bundled GeoJSON polygons loaded once at process start. It is pure Swift +
Foundation (no SwiftUI, UIKit, SwiftData, or CoreLocation), so it can be reused
and unit-tested in isolation.

RegionKit is the lowest layer of the Where feature: `WhereCore` (and, through
it, `WhereUI`, the widgets, and the RegionViewer) depend on RegionKit and call
into it for lookup. RegionKit depends only on [`LogKit`](../../Shared/LogKit).

## What you get

- **`Region`** — the tracked-region enum (`.california`, `.newYork`, `.canada`,
  `.europeanUnion`, `.other`), with a `localizedName` (from RegionKit's own
  string catalog) and a `geometrySource` describing where its polygons come
  from. (Day-count *ranking* of regions lives in `WhereCore`, not here —
  RegionKit stays about regions and geofencing.)
- **`Coordinate`** — a plain WGS84 latitude/longitude value type (no
  CoreLocation), plus geometry primitives `GeoPolygon`, `BoundingBox`, and the
  antimeridian-aware `LongitudeSpan`.
- **`RegionAttributor`** — `region(at:)` maps a coordinate to its `Region`
  (bounding-box pre-pass, then an even-odd ray-cast), and `distanceToBoundary`
  measures nearness to a region's edge. `RegionAttributor.shared` loads the
  bundled polygons lazily.
- **`RegionGeometryCatalog`** — read-only drawable `RegionOutline`s for the
  developer region-map viewer (`.attribution` vs `.source` geometry).
- **`RegionLog`** — RegionKit's LogKit facade (subsystem `com.stuff.regionkit`).

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

Region polygons ship in `Sources/Resources/*.geojson`; see
[`Sources/Resources/README.md`](Sources/Resources/README.md) for provenance and
fidelity notes. Region names resolve through RegionKit's own
`Localizable.xcstrings` (`Region.localizedName`, `bundle: .module`).

## Adding a region

Add the `Region` case, then resolve the two compile errors it forces: a
`region.<rawValue>` entry in `Sources/Resources/Localizable.xcstrings` (for
`localizedName`) and a `Region.geometrySource` case — either
`.usStateFeature(name:)` (a feature already in `us-states.geojson`, no new file)
or `.bundledFile` with a new `<rawValue>.geojson` in `Sources/Resources/`. Add a
`RegionAttributorTests` spot-check.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` (so
`Bundle.module` resolves the GeoJSON at runtime). Attribution, geometry
(point-in-polygon, bounding box, longitude span), GeoJSON decoding, and the
geometry catalog are covered here; internal types (`GeoJSON`, `GeoPolygon`,
`RegionPolygons`) are reached via `@testable import RegionKit`.
