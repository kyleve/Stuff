# RegionKit

The geometry and region-lookup engine behind the Where app. Given a WGS84
`Coordinate`, RegionKit answers *which `Region` is it in?* — backed by bundled
GeoJSON polygons loaded **on demand, per region**. It is pure Swift + Foundation
(no SwiftUI, UIKit, SwiftData, or CoreLocation), so it can be reused and
unit-tested in isolation.

RegionKit is the lowest layer of the Where feature: `WhereCore` (and, through
it, `WhereUI`, the widgets, and the RegionViewer) depend on RegionKit and call
into it for lookup. RegionKit depends only on [`LogKit`](../../Shared/LogKit).

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
- **`RegionGeometryCatalog`** — read-only drawable `RegionOutline`s for the
  developer region-map viewer (`.attribution` for a given attributor vs `.source`
  for the whole catalog).
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

The catalog manifest (`Sources/Resources/regions.json`) and one GeoJSON file per
region (`Sources/Resources/regions/<id>.geojson`) are **generated** from the
source data under `Tools/source/` by `Tools/generate-regions.rb`; see
[`Sources/Resources/README.md`](Sources/Resources/README.md) for the id scheme,
provenance, and how to regenerate. Region names come from the manifest, with an
optional `localizationKey` overriding from RegionKit's own `Localizable.xcstrings`
(`Region.localizedName`, `bundle: .module`) — a deliberate trade-off: dynamic
ids mean names are data, so region names lose static string-catalog extraction.

## Adding a region

Adding a region is now **pure data** — no new `Region` case, no code:

1. Add its geometry to `Tools/source/` (a new feature, or a new source file).
2. Run `ruby Where/RegionKit/Tools/generate-regions.rb` to regenerate
   `regions/` + `regions.json` (add the `NAME → id` mapping in the script if it's
   a new US feature; blocs/countries get an entry in the script's `NON_US` list).
3. Optionally add a `region.<key>` entry to `Localizable.xcstrings` and point the
   manifest entry's `localizationKey` at it (otherwise the English `name` shows).
4. Add a `RegionAttributorTests` spot-check.

Everything downstream (`RegionStyle`, region pickers, the App Intents
`RegionEntity`) derives from the catalog automatically.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` (so
`Bundle.module` resolves the GeoJSON at runtime). Attribution, geometry
(point-in-polygon, bounding box, longitude span), GeoJSON decoding, and the
geometry catalog are covered here; internal types (`GeoJSON`, `GeoPolygon`,
`RegionPolygons`) are reached via `@testable import RegionKit`.
