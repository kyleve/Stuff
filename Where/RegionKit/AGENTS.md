# RegionKit – Module Shape

RegionKit is the geometry and region-lookup engine for the Where feature:
coordinate-to-`Region` attribution over bundled GeoJSON polygons, plus the
geometry primitives and the developer-viewer geometry catalog. See
[`README.md`](README.md) for the public API and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Pure Swift + Foundation**, plus [`LogKit`](../../Shared/LogKit). It must
  **not** import SwiftUI, UIKit, SwiftData, CoreLocation, or `WhereCore` — it is
  the lowest layer of the feature, and `WhereCore` depends on *it*, never the
  reverse.
- Library target in [`Package.swift`](../../Package.swift)
  (`Where/RegionKit/Sources`). Bundled region polygons and the region-name
  string catalog ship in `Sources/Resources/`.

## Invariants

- **`Region.geometrySource` is the single source of truth** for where a region's
  polygons come from; `Region.localizedName` and `geometrySource` are exhaustive
  switches, so adding a `Region` case is a compile error until its name and
  geometry are declared (see [README](README.md#adding-a-region)).
- **`Region.allCases` order fixes attribution priority** — `RegionAttributor`
  checks regions in declaration order and the first polygon match wins (regions
  are mutually exclusive at our resolution). (Day-count ranking of regions lives
  in `WhereCore`'s `Region+Ordering`, not here.)
- **Attribution loads once, lazily** (`RegionAttributor.shared`) and is UI-free:
  `BoundingBox` / `LongitudeSpan` expose the min/max math, but MapKit conversion
  lives in the UI layer.
- **Missing/corrupt bundled geometry is a programmer error** — the loader logs a
  `fault` via `RegionLog` *and* `assertionFailure`s (debug), degrading to
  `.other` in release rather than crashing.
- **Logging goes through `RegionLog.channel(_:)`** (subsystem
  `com.stuff.regionkit`), never `WhereLog` — RegionKit owns its own channel and
  in-memory store.

## Testing

Swift Testing in [`Tests/`](Tests) (`RegionKitTests`), hosted in
`StuffTestHost`. Internal types are reached via `@testable import RegionKit`.
