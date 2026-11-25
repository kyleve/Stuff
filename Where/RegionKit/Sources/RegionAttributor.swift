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
        if self.region(at: coordinate) == region { return 0 }
        guard region != .other else { return nil }
        return distanceToBoundary(of: region, from: coordinate)
    }
}

/// Maps coordinates to their most specific tracked region. Caller order breaks
/// ties between matching regions that have no ancestor relationship.
///
/// An attributor is built for a **specific set of regions** and loads only
/// their physical geometry. A tracked parent references the same child polygons
/// as its tracked subdivisions. Anything outside the tracked coverage is `.other`.
public struct RegionAttributor: RegionAttributing {
    private let trackedGeometry: [TrackedGeometry]
    /// Only ancestors and descendants whose polygons were requested participate.
    private let loadedDescendants: [Region: Set<Region>]

    /// Attributor for the default set of tracked regions (California, New York,
    /// Canada, the European Union). Production derives its attributor from the
    /// store's tracked regions via `WhereServices.make(...)`; this snapshot backs
    /// the synchronous defaults for tests and previews (whose in-memory stores
    /// resolve to this same default) and the "no tracked rows yet" fallback. The
    /// developer viewer and tests use ``all`` for the whole catalog.
    public static let shared = RegionAttributor(for: [
        .california,
        .newYork,
        .canada,
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
        self.init(for: regions, catalog: .shared, geometryURL: RegionCatalog.geometryURL(for:))
    }

    init(for regions: [Region], catalog: RegionCatalog, geometryURL: (RegionCatalog.Node) -> URL?) {
        self.init(
            trackedGeometry: Self
                .loadPolygons(for: regions, catalog: catalog, geometryURL: geometryURL),
            catalog: catalog,
        )
    }

    init(regionPolygons: [RegionPolygons], catalog: RegionCatalog = .shared) {
        self.init(trackedGeometry: regionPolygons.map {
            TrackedGeometry(region: $0.region, members: [$0])
        }, catalog: catalog)
    }

    private init(trackedGeometry: [TrackedGeometry], catalog: RegionCatalog) {
        self.trackedGeometry = trackedGeometry
        let loaded = Set(trackedGeometry.map(\.region))
        var descendants: [Region: Set<Region>] = [:]
        for region in loaded {
            var ancestor = catalog.node(for: region).flatMap(catalog.parent(of:))
            while let node = ancestor {
                if let parent = node.region, loaded.contains(parent) {
                    descendants[parent, default: []].insert(region)
                }
                ancestor = catalog.parent(of: node)
            }
        }
        loadedDescendants = descendants
    }

    /// Resolve a drawable member to its most specific tracked owner, just as
    /// attribution does. A picker that offers every subdivision draws each file once.
    func forEachDrawableMember(_ visit: (Region, RegionPolygons) -> Void) {
        var owners: [Region: Set<Region>] = [:]
        for entry in trackedGeometry {
            for member in entry.members {
                owners[member.region, default: []].insert(entry.region)
            }
        }
        let preferred = owners.compactMapValues { winner(in: $0)?.region }
        for entry in trackedGeometry {
            for member in entry.members where preferred[member.region] == entry.region {
                visit(entry.region, member)
            }
        }
    }

    /// The regions this attributor loaded, in load order (excludes `.other`).
    public var loadedRegions: [Region] {
        trackedGeometry.map(\.region)
    }

    public func region(at coordinate: Coordinate) -> Region {
        winningEntry(at: coordinate)?.region ?? .other
    }

    private func winningEntry(at coordinate: Coordinate) -> TrackedGeometry? {
        guard !loadedDescendants.isEmpty else {
            return trackedGeometry.first { $0.contains(coordinate) }
        }
        return winner(in: matches(at: coordinate))
    }

    private func matches(at coordinate: Coordinate) -> Set<Region> {
        Set(trackedGeometry.lazy.filter { $0.contains(coordinate) }.map(\.region))
    }

    private func winner(in matches: Set<Region>) -> TrackedGeometry? {
        trackedGeometry.first {
            matches.contains($0.region) && loadedDescendants[$0.region]?
                .isDisjoint(with: matches) != false
        }
    }

    public func matchWithBoundaryDistance(at coordinate: Coordinate) -> RegionBoundaryMatch? {
        let matches = matches(at: coordinate)
        guard let match = winner(in: matches) else { return nil }
        var distance = match.distanceToBoundary(from: coordinate)
        // A competing boundary can change the winner inside this outline only
        // where their bounds overlap. Use the same ancestor and priority rules
        // on both sides, e.g. crossing into Ontario can displace Canada.
        for entry in trackedGeometry
            where entry.region != match.region && entry.boundingBox.overlaps(match.boundingBox)
        {
            let acrossEdge = matches.symmetricDifference([entry.region])
            if winner(in: acrossEdge)?.region != match.region {
                distance = min(distance, entry.distanceToBoundary(from: coordinate))
            }
        }
        return RegionBoundaryMatch(region: match.region, boundaryDistance: distance)
    }

    public func distance(to region: Region, from coordinate: Coordinate) -> Double? {
        if region == .other { return self.region(at: coordinate) == .other ? 0 : nil }
        guard let entry = trackedGeometry.first(where: { $0.region == region }) else { return nil }
        return entry.contains(coordinate) ? 0 : entry.distanceToBoundary(from: coordinate)
    }

    /// Smallest distance in meters from `coordinate` to the boundary of
    /// `region`'s loaded polygons. Returns `nil` for regions this attributor
    /// didn't load (including `.other`).
    public func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double? {
        guard let entry = trackedGeometry.first(where: { $0.region == region }) else { return nil }
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
        geometryURL: (RegionCatalog.Node) -> URL?,
    ) -> [TrackedGeometry] {
        var entries: [TrackedGeometry] = []
        var members: [RegionCatalog.Node.ID: RegionPolygons] = [:]
        var requested: Set<Region> = []
        logger.measure(.loadPolygons, budget: .seconds(1)) {
            for region in regions where region != .other && requested.insert(region).inserted {
                guard let node = catalog.node(id: .init(rawValue: region.rawValue)) else {
                    logger.missingGeometry(region: .restricted(.location, region))
                    assertionFailure("Missing bundled region \(region.rawValue)")
                    continue
                }
                guard node.isLoggable else { continue }
                let sources = catalog.geometryNodes(for: node)
                let polygons = sources.compactMap { source -> RegionPolygons? in
                    if let cached = members[source.id] { return cached }
                    let member = loadMember(source, url: geometryURL(source))
                    members[source.id] = member
                    return member
                }
                if !polygons.isEmpty, polygons.count == sources.count {
                    entries.append(TrackedGeometry(region: region, members: polygons))
                }
            }
        }
        logger.loaded(regionCount: .shared(.count, entries.count))
        return entries
    }

    private static func loadMember(_ node: RegionCatalog.Node, url: URL?) -> RegionPolygons? {
        let region = Region(unchecked: node.id.rawValue)
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

/// The geometry referenced by one tracking choice. Members share their decoded
/// coordinates and spatial indexes with individually tracked subdivisions.
struct TrackedGeometry {
    let region: Region
    let members: [RegionPolygons]
    let boundingBox: BoundingBox

    init(region: Region, members: [RegionPolygons]) {
        self.region = region
        self.members = members
        boundingBox = members.reduce(.empty) { $0.enclosing($1.boundingBox) }
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        boundingBox.contains(coordinate) && members.contains { $0.contains(coordinate) }
    }

    func distanceToBoundary(from coordinate: Coordinate) -> Double {
        if members.count == 1 { return members[0].distanceToBoundary(from: coordinate) }
        func shared(_ a: Coordinate, _ b: Coordinate, with member: RegionPolygons) -> Bool {
            members.contains { $0.region != member.region && $0.hasEdge(a, b) }
        }

        // The nearest edge of a member usually lies on the coast or an international
        // border. Only revisit members whose nearest edge is an internal subdivision edge.
        var best = Double.infinity
        var sharedMembers: [RegionPolygons] = []
        for member in members {
            var edge: (start: Coordinate, end: Coordinate)?
            let nearest = member.distanceToBoundary(from: coordinate, nearerThan: best) { a, b in
                edge = (a, b)
                return true
            }
            guard let edge else { continue }
            if shared(edge.start, edge.end, with: member) {
                sharedMembers.append(member)
            } else {
                best = nearest
            }
        }
        for member in sharedMembers {
            best = member.distanceToBoundary(from: coordinate, nearerThan: best) { a, b in
                !shared(a, b, with: member)
            }
        }
        return best
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

    func hasEdge(_ a: Coordinate, _ b: Coordinate) -> Bool {
        guard boundingBox.contains(a), boundingBox.contains(b) else { return false }
        if latitudeBands.isEmpty { return polygons.contains { $0.hasEdge(a, b) } }
        return latitudeBands[Self.band(a.latitude)].contains { polygons[$0].hasEdge(a, b) }
    }

    func distanceToBoundary(
        from coordinate: Coordinate,
        nearerThan distance: Double = .infinity,
        includingEdge: (Coordinate, Coordinate) -> Bool = { _, _ in true },
    ) -> Double {
        polygons.reduce(distance) { $1.distanceToBoundary(
            from: coordinate,
            nearerThan: $0,
            includingEdge: includingEdge,
        ) }
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
