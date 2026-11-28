import Foundation
import PeriscopeCore

/// A tracked match and its distance in meters to a change in attribution.
public struct RegionBoundaryMatch: Sendable {
    public let region: Region
    public let boundaryDistance: Double

    public init(region: Region, boundaryDistance: Double) {
        self.region = region
        self.boundaryDistance = boundaryDistance
    }
}

/// A coordinate-to-`Region` lookup engine. Abstracted as a protocol so callers
/// can hold either an immutable ``RegionAttributor`` snapshot or a live,
/// swappable attributor (e.g. one WhereCore rebuilds when the user's tracked
/// regions change) behind the same synchronous API.
public protocol RegionAttributing: Sendable {
    /// The region `coordinate` falls inside, or `.other` if none.
    func region(at coordinate: Coordinate) -> Region
    /// Resolves the winner and its confidence boundary against the same tracked set.
    func matchWithBoundaryDistance(at coordinate: Coordinate) -> RegionBoundaryMatch?
    /// Distance in meters to a named region, including zero anywhere inside it.
    /// Returns nil when its geometry is unavailable. Other matches only outside all tracked
    /// regions.
    func distance(to region: Region, from coordinate: Coordinate) -> Double?
    /// Smallest distance in meters from `coordinate` to `region`'s boundary, or
    /// `nil` for a region this attributor didn't load.
    func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double?
    /// The regions this attributor loaded and attributes to (excludes `.other`).
    var loadedRegions: [Region] { get }
}

extension RegionAttributing {
    /// Defaults for immutable attributors with disjoint regions.
    public func matchWithBoundaryDistance(at coordinate: Coordinate) -> RegionBoundaryMatch? {
        let region = region(at: coordinate)
        guard region != .other,
              let distance = distanceToBoundary(of: region, from: coordinate) else { return nil }
        return RegionBoundaryMatch(region: region, boundaryDistance: distance)
    }

    public func distance(to region: Region, from coordinate: Coordinate) -> Double? {
        if self.region(at: coordinate) == region {
            return 0
        }
        guard region != .other else { return nil }
        return distanceToBoundary(of: region, from: coordinate)
    }
}

/// Maps a coordinate to the first tracked region that contains it. Loads only
/// the requested regions' polygons. A coordinate outside them resolves to `.other`.
public struct RegionAttributor: RegionAttributing {
    let loadedRegionPolygons: [RegionPolygons]

    /// Attributor for the default set of tracked regions (California, New York,
    /// the European Union). Production derives its attributor from the
    /// store's tracked regions via `WhereServices.make(...)`; this snapshot backs
    /// the synchronous defaults for tests and previews (whose in-memory stores
    /// resolve to this same default) and the "no tracked rows yet" fallback. The
    /// developer viewer and tests use ``all`` for the whole catalog.
    public static let shared = RegionAttributor(for: [
        .california,
        .newYork,
        .europeanUnion,
    ])

    /// Attributor covering **every** available region in the catalog. Loads all
    /// per-region files, so reserve it for the developer region-map viewer and
    /// tests — production attributes against the user's tracked subset.
    public static let all = RegionAttributor(for: RegionCatalog.shared.all)

    /// Builds an attributor that loads and attributes only `regions` (in the
    /// given order, which fixes first-match priority). `.other` is ignored — it
    /// has no geometry and is the fallback when nothing matches.
    public init(for regions: [Region]) {
        self.init(
            for: regions,
            catalog: .shared,
            geometryURL: RegionCatalog.geometryURL(for:purpose:),
        )
    }

    init(
        for regions: [Region],
        catalog: RegionCatalog,
        geometryURL: (RegionCatalog.Node, RegionGeometryPurpose) -> URL?,
    ) {
        loadedRegionPolygons = Self.loadPolygons(
            for: regions,
            catalog: catalog,
            geometryURL: geometryURL,
        )
    }

    /// The regions this attributor loaded, in load order (excludes `.other`).
    public var loadedRegions: [Region] {
        loadedRegionPolygons.map(\.region)
    }

    public func region(at coordinate: Coordinate) -> Region {
        loadedRegionPolygons.first { $0.contains(coordinate) }?.region ?? .other
    }

    public func matchWithBoundaryDistance(at coordinate: Coordinate) -> RegionBoundaryMatch? {
        guard let index = loadedRegionPolygons.firstIndex(where: { $0.contains(coordinate) })
        else { return nil }
        let match = loadedRegionPolygons[index]
        var distance = match.distanceToBoundary(from: coordinate)
        // Where publishers' boundaries overlap, entering an earlier region can
        // change the winner before the fix leaves the current region.
        for earlier in loadedRegionPolygons[..<index]
            where earlier.boundingBox.overlaps(match.boundingBox)
        {
            distance = earlier.distanceToBoundary(from: coordinate, nearerThan: distance)
        }
        return RegionBoundaryMatch(region: match.region, boundaryDistance: distance)
    }

    public func distance(to region: Region, from coordinate: Coordinate) -> Double? {
        if region == .other {
            return self.region(at: coordinate) == .other ? 0 : nil
        }
        guard let entry = loadedRegionPolygons.first(where: { $0.region == region })
        else { return nil }
        return entry.contains(coordinate) ? 0 : entry.distanceToBoundary(from: coordinate)
    }

    /// Smallest distance in meters from `coordinate` to the boundary of
    /// `region`'s loaded polygons. Returns `nil` for regions this attributor
    /// didn't load (including `.other`).
    public func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double? {
        guard let entry = loadedRegionPolygons.first(where: { $0.region == region })
        else { return nil }
        return entry.distanceToBoundary(from: coordinate)
    }

    /// `RegionLog` logger — surfaces missing/unparseable bundled resources as
    /// Console.app faults alongside the debug-build `assertionFailure`.
    private static let logger = RegionLog.attributor

    /// Loads the polygons for each region from its bundled
    /// per-region geometry file. Missing/corrupt geometry is a programmer error: it's
    /// logged as a `fault` and `assertionFailure`s in debug, degrading to
    /// "region simply never matches" in release rather than crashing.
    private static func loadPolygons(
        for regions: [Region],
        catalog: RegionCatalog,
        geometryURL: (RegionCatalog.Node, RegionGeometryPurpose) -> URL?,
    ) -> [RegionPolygons] {
        var entries: [RegionPolygons] = []
        var requested: Set<Region> = []
        logger.measure(.loadPolygons, budget: .seconds(1)) {
            for region in regions where region != .other && requested.insert(region).inserted {
                guard let node = catalog.node(id: .init(rawValue: region.rawValue)) else {
                    logger.missingGeometry(region: .restricted(.location, region))
                    assertionFailure("Missing bundled region \(region.rawValue)")
                    continue
                }
                guard node.isLoggable else { continue }
                if let polygons = loadRegion(region, url: geometryURL(node, .tracking)) {
                    entries.append(polygons)
                }
            }
        }
        logger.loaded(regionCount: .shared(.count, entries.count))
        return entries
    }

    private static func loadRegion(_ region: Region, url: URL?) -> RegionPolygons? {
        guard let url else {
            logger.missingGeometry(region: .restricted(.location, region))
            assertionFailure("Missing bundled geometry for region \(region.rawValue)")
            return nil
        }
        do {
            let polygons = try logger.measure(.loadRegion(region)) {
                try RegionGeometryReader.polygons(at: url)
            }
            guard !polygons.isEmpty else {
                logger.emptyPolygons(region: .restricted(.location, region))
                assertionFailure("Region \(region.rawValue) decoded no polygons")
                return nil
            }
            return RegionPolygons(region: region, polygons: polygons)
        } catch {
            logger.decodeFailed(
                region: .restricted(.location, region),
                error: .restricted(.errorDetails, error),
            )
            assertionFailure(
                "Failed to decode bundled geometry for region \(region.rawValue): \(error)",
            )
            return nil
        }
    }
}

extension BoundingBox {
    fileprivate func overlaps(_ other: Self) -> Bool {
        minLatitude < other.maxLatitude && maxLatitude > other.minLatitude
            && minLongitude < other.maxLongitude && maxLongitude > other.minLongitude
    }
}

/// One `Region` plus every polygon that defines it, with a precomputed
/// `boundingBox` for fast pre-screening in `RegionAttributor.region(at:)`.
struct RegionPolygons {
    let region: Region
    let polygons: [GeoPolygon]
    let boundingBox: BoundingBox
    /// Dense coastal datasets contain hundreds of thousands of small islands.
    /// Each latitude band holds just the components a ray at that latitude can meet.
    private let latitudeBands: [[Int]]

    private static func band(_ latitude: Double) -> Int {
        Int(min(180, max(0, (latitude + 90).rounded(.down))))
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        guard boundingBox.contains(coordinate) else { return false }
        guard !latitudeBands.isEmpty else { return polygons.contains { $0.contains(coordinate) } }
        return latitudeBands[Self.band(coordinate.latitude)]
            .contains { polygons[$0].contains(coordinate) }
    }

    func distanceToBoundary(
        from coordinate: Coordinate,
        nearerThan distance: Double = .infinity,
    ) -> Double {
        polygons.reduce(distance) { $1.distanceToBoundary(from: coordinate, nearerThan: $0) }
    }

    init(region: Region, polygons: [GeoPolygon]) {
        self.region = region
        self.polygons = polygons
        if polygons.count >= 1024 {
            var bands = [[Int]](repeating: [], count: 181)
            for (index, polygon) in polygons.enumerated() where !polygon.vertices.isEmpty {
                let box = polygon.geographicBounds
                for row in Self.band(box.minLatitude) ... Self.band(box.maxLatitude) {
                    bands[row].append(index)
                }
            }
            latitudeBands = bands
        } else {
            latitudeBands = []
        }
        if let box = BoundingBox.enclosing(polygons) {
            boundingBox = box
        } else {
            // Empty polygon set is a programmer error — the loader guards
            // against it before constructing a `RegionPolygons`. The
            // release-build fallback is `.empty`, a degenerate bbox that
            // contains nothing, so the region simply never matches (failing to
            // `.other` beats crashing on a missing-data condition).
            assertionFailure(
                "Cannot construct RegionPolygons with no polygons for \(region.rawValue)",
            )
            boundingBox = .empty
        }
    }
}
