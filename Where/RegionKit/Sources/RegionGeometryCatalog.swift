import Foundation
import PeriscopeCore

/// The purpose a publisher's boundary product serves in Where.
public enum RegionGeometryPurpose: String, CaseIterable, Sendable, Hashable {
    case display
    case tracking
}

/// One drawable region boundary: a single exterior ring tagged with a
/// display title and, when known, the `Region` it belongs to. A
/// MultiPolygon feature expands into several `RegionOutline`s (one per
/// sub-polygon). Interior rings accompany their exterior so a map can cut out holes when filling a
/// polygon.
public struct RegionOutline: Identifiable, Sendable, Hashable {
    /// Typed identity (never a raw `String`): the title plus a running
    /// index, unique within a set of outlines so SwiftUI
    /// `ForEach` stays stable even when one feature yields many rings or
    /// several features share a title.
    public struct ID: Hashable, Sendable {
        public let title: String
        public let index: Int
    }

    public let id: ID
    /// Human-readable label: a `Region.localizedName` (e.g. "California").
    public let title: String
    /// The catalog region that owns this outline, when known.
    public let region: Region?
    /// The exterior ring, in order.
    public let coordinates: [Coordinate]
    public let holes: [[Coordinate]]

    init(
        id: ID,
        title: String,
        region: Region?,
        coordinates: [Coordinate],
        holes: [[Coordinate]] = [],
    ) {
        self.id = id
        self.title = title
        self.region = region
        self.coordinates = coordinates
        self.holes = holes
    }

    /// Hash on identity alone. Each result assigns unique IDs, so this
    /// avoids walking the (often thousands-of-points)
    /// coordinate ring on every `Set`/dictionary insertion. The
    /// synthesized `==` still compares every field, so value equality is
    /// unchanged and the `a == b ⇒ hash(a) == hash(b)` contract holds.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Failure decoding bundled region geometry. Surfaced (never swallowed) so
/// developer tools can show a real error state and production artwork can log
/// a broken bundled-resource invariant instead of silently drawing nothing.
public enum RegionGeometryError: Error {
    case missingResource(String)
    case emptyResource(String)
}

extension RegionGeometryError: LocalizedError {
    /// A developer-facing message that names the missing file, rather than
    /// the generic "operation couldn't be completed" the viewer's error
    /// state would otherwise show. The diagnostic includes the failing bundle resource.
    public var errorDescription: String? {
        switch self {
            case let .missingResource(resource):
                "Missing bundled region geometry resource “\(resource)”."
            case let .emptyResource(resource):
                "Bundled region geometry resource “\(resource)” contains no drawable outlines."
        }
    }
}

/// Read-only catalog of region boundary geometry for region artwork and the
/// developer region-map viewer. UI never touches `RegionAttributor`'s internal
/// polygons or the geometry decoder directly.
public enum RegionGeometryCatalog {
    /// Drawable outlines for one region, cached after the first request.
    ///
    /// This is the lightweight path for region-specific UI artwork: it decodes
    /// only `region` rather than the full source catalog. `.other` returns an
    /// empty array because it intentionally has no geometry. Missing, corrupt,
    /// or empty bundled geometry logs a fault and asserts in debug; release
    /// builds safely omit the decorative outline.
    public static func displayOutlines(for region: Region) async -> [RegionOutline] {
        guard region != .other else { return [] }
        do {
            return try await RegionCache.shared.outlines(for: region)
        } catch {
            RegionLog.geometryCatalog.regionLoadFailed(
                region: .restricted(.location, region),
                error: .restricted(.errorDetails, error),
            )
            assertionFailure(
                "Failed to load drawable outlines for \(region.rawValue): \(error.localizedDescription)",
            )
            return []
        }
    }

    /// Prepares both the overlays and tap lookup from the offered regions' display boundaries.
    @concurrent public static func displayGeometry(for regions: [Region]) async throws
        -> RegionDisplayGeometry
    {
        try displayGeometry(
            for: regions,
            catalog: .shared,
            resourceURL: RegionCatalog.geometryURL(for:purpose:),
        )
    }

    static func displayGeometry(
        for regions: [Region],
        catalog: RegionCatalog,
        resourceURL: (RegionCatalog.Node, RegionGeometryPurpose) -> URL?,
    ) throws -> RegionDisplayGeometry {
        try RegionLog.geometryCatalog.measure(.buildDisplayGeometry, budget: .seconds(2)) {
            var entries: [RegionPolygons] = []
            var seen: Set<Region> = []
            for region in regions where region != .other && seen.insert(region).inserted {
                try Task.checkCancellation()
                let polygons = try displayPolygons(
                    for: region,
                    catalog: catalog,
                    resourceURL: resourceURL,
                )
                if !polygons.isEmpty { entries.append(RegionPolygons(
                    region: region,
                    polygons: polygons,
                )) }
            }
            let result = RegionDisplayGeometry(entries: entries)
            try Task.checkCancellation()
            return result
        }
    }

    private static func displayPolygons(
        for region: Region,
        catalog: RegionCatalog,
        resourceURL: (RegionCatalog.Node, RegionGeometryPurpose) -> URL?,
    ) throws -> [GeoPolygon] {
        guard region != .other else { return [] }
        guard let node = catalog.node(id: .init(rawValue: region.rawValue)) else {
            throw RegionGeometryError.missingResource(region.rawValue)
        }
        guard node.isLoggable else { return [] }
        guard let url = resourceURL(node, .display) else {
            throw RegionGeometryError
                .missingResource(node.geometry?.display.file ?? region.rawValue)
        }
        let polygons = try RegionGeometryReader.polygons(at: url)
        guard !polygons.isEmpty
        else { throw RegionGeometryError.emptyResource(url.lastPathComponent) }
        return polygons
    }

    /// Reuses the exact polygons already loaded into a tracking snapshot for the diagnostic map.
    public static func trackingOutlines(for attributor: RegionAttributor) -> [RegionOutline] {
        outlines(for: attributor.loadedRegionPolygons)
    }

    fileprivate static func outlines(for entries: [RegionPolygons]) -> [RegionOutline] {
        var outlines: [RegionOutline] = []
        for entry in entries {
            append(entry.polygons, for: entry.region, to: &outlines)
        }
        return outlines
    }

    private static func append(
        _ polygons: [GeoPolygon],
        for region: Region,
        to outlines: inout [RegionOutline],
    ) {
        let title = region.localizedName
        for polygon in polygons {
            outlines.append(RegionOutline(
                id: .init(title: title, index: outlines.count),
                title: title,
                region: region,
                coordinates: polygon.vertices,
                holes: polygon.holes,
            ))
        }
    }

    /// Cards request individual regions repeatedly. Keep their outlines off the main actor.
    actor RegionCache {
        static let shared = RegionCache(
            catalog: .shared,
            resourceURL: RegionCatalog.geometryURL(for:purpose:),
        )

        private let catalog: RegionCatalog
        private let resourceURL: @Sendable (RegionCatalog.Node, RegionGeometryPurpose) -> URL?
        private var cached: [Region: [RegionOutline]] = [:]

        init(
            catalog: RegionCatalog,
            resourceURL: @escaping @Sendable (RegionCatalog.Node, RegionGeometryPurpose) -> URL?,
        ) {
            self.catalog = catalog
            self.resourceURL = resourceURL
        }

        func outlines(for region: Region) throws -> [RegionOutline] {
            if let outlines = cached[region] { return outlines }
            let outlines = try RegionLog.geometryCatalog.measure(
                .loadRegionOutlines(region),
                budget: .seconds(1),
            ) {
                let polygons = try RegionGeometryCatalog.displayPolygons(
                    for: region,
                    catalog: catalog,
                    resourceURL: resourceURL,
                )
                var outlines: [RegionOutline] = []
                RegionGeometryCatalog.append(polygons, for: region, to: &outlines)
                return outlines
            }
            cached[region] = outlines
            return outlines
        }
    }
}

/// Display geometry for the offered regions, in input order. The outlines and hit testing
/// share coordinate buffers, including islands, holes and antimeridian handling.
public struct RegionDisplayGeometry: Sendable {
    public let outlines: [RegionOutline]
    private let entries: [RegionPolygons]

    init(entries: [RegionPolygons]) {
        self.entries = entries
        outlines = RegionGeometryCatalog.outlines(for: entries)
    }

    /// Returns the first offered region whose displayed polygon contains the coordinate.
    public func region(containing coordinate: Coordinate) -> Region? {
        entries.first { $0.contains(coordinate) }?.region
    }
}

extension BoundingBox {
    /// The smallest box enclosing every coordinate of every outline, or
    /// `nil` when `outlines` is empty. Reuses the shared
    /// `enclosing(_:)` coordinate core so the region-map viewer frames
    /// its camera from the same math the attributor pre-pass uses.
    public static func enclosing(_ outlines: [RegionOutline]) -> BoundingBox? {
        enclosing(outlines.lazy.flatMap(\.coordinates))
    }
}
