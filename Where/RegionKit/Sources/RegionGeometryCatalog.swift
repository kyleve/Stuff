import Foundation
import PeriscopeCore

/// Which set of region polygons to vend, for the developer region-map
/// viewer's source toggle.
public enum RegionGeometryKind: String, CaseIterable, Sendable, Hashable {
    /// What a `RegionAttributor` actually loaded and uses to attribute
    /// coordinates — the app's tracked subset.
    case attribution
    /// The bundled physical boundaries, each labeled with its source region.
    case source
}

/// One drawable region boundary: a single exterior ring tagged with a
/// display title and, when known, the `Region` it belongs to. A
/// MultiPolygon feature expands into several `RegionOutline`s (one per
/// sub-polygon). Interior rings accompany their exterior so a map can cut out holes when filling a
/// polygon.
public struct RegionOutline: Identifiable, Sendable, Hashable {
    /// Typed identity (never a raw `String`): the title plus a running
    /// index, unique across a single `outlines(for:)` result so SwiftUI
    /// `ForEach` stays stable even when one feature yields many rings or
    /// several features share a title.
    public struct ID: Hashable, Sendable {
        public let title: String
        public let index: Int
    }

    public let id: ID
    /// Human-readable label: a `Region.localizedName` (e.g. "California").
    public let title: String
    /// The tracked region this outline belongs to, or `nil` for a source
    /// feature not modeled as a `Region`.
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

    /// Hash on identity alone. `id` is unique within an `outlines(for:)`
    /// result, so this avoids walking the (often thousands-of-points)
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
    /// state would otherwise show. Not localized — this only ever appears
    /// in the DEBUG region-map tool.
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
    public static func outlines(for region: Region) async -> [RegionOutline] {
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

    /// Drawable outlines for `kind`.
    ///
    /// - `.attribution` reflects exactly what `attributor` loaded (the tracked
    ///   subset) — the caller passes the attributor rather than the catalog
    ///   reaching for a global, so the viewer shows the regions it cares about.
    /// - `.source` decodes each physical file in the catalog and ignores
    ///   `attributor`.
    ///
    /// `.source` decoding runs on its cache actor. `.attribution` maps the
    /// caller-provided attributor on the caller's actor because it is already
    /// resolved in memory. Throws `RegionGeometryError` / a `DecodingError`
    /// rather than absorbing a missing or malformed bundle into an empty list.
    public static func outlines(
        for kind: RegionGeometryKind,
        attributor: RegionAttributor,
    ) async throws -> [RegionOutline] {
        switch kind {
            case .attribution:
                attributionOutlines(for: attributor)
            case .source:
                try await SourceCache.shared.outlines()
        }
    }

    // MARK: - Attribution

    /// Outlines for exactly what `attributor` loaded — cheap, since it reads the
    /// already-resolved polygons.
    private static func attributionOutlines(for attributor: RegionAttributor) -> [RegionOutline] {
        var builder = OutlineBuilder()
        attributor.forEachDrawableMember { region, member in
            let title = region.localizedName
            for polygon in member.polygons {
                builder.add(
                    title: title,
                    region: region,
                    coordinates: polygon.vertices,
                    holes: polygon.holes,
                )
            }
        }
        return builder.outlines
    }

    // MARK: - Source

    /// Decode each bundled geometry file at full
    /// fidelity, each outline tagged with the `Region` it belongs to and titled
    /// by its `localizedName`.
    static func buildSourceOutlines() throws -> [RegionOutline] {
        try RegionLog.geometryCatalog.measure(.buildSourceOutlines, budget: .seconds(2)) {
            var builder = OutlineBuilder()
            for node in RegionCatalog.shared.nodes where node.geometryFile != nil {
                try builder.add(node: node, resourceURL: RegionCatalog.geometryURL(for: node))
            }
            return builder.outlines
        }
    }

    /// Caches the heavy `.source` decode (parsing every per-region file) so
    /// toggling back to source after the first load is instant. An `actor` both
    /// serializes the one-time build and runs it off the main thread.
    private actor SourceCache {
        static let shared = SourceCache()
        private var cached: [RegionOutline]?

        func outlines() throws -> [RegionOutline] {
            if let cached { return cached }
            let built = try RegionGeometryCatalog.buildSourceOutlines()
            cached = built
            return built
        }
    }

    /// Per-region cache for UI artwork. Actor isolation serializes simultaneous
    /// requests for the same first-use decode without introducing a global
    /// mutable registry in the UI layer.
    actor RegionCache {
        static let shared = RegionCache(
            catalog: .shared,
            resourceURL: RegionCatalog.geometryURL(for:),
        )

        private let catalog: RegionCatalog
        private let resourceURL: @Sendable (RegionCatalog.Node) -> URL?
        private var cached: [RegionCatalog.Node.ID: [RegionOutline]] = [:]

        init(
            catalog: RegionCatalog,
            resourceURL: @escaping @Sendable (RegionCatalog.Node) -> URL?,
        ) {
            self.catalog = catalog
            self.resourceURL = resourceURL
        }

        func outlines(for region: Region) throws -> [RegionOutline] {
            guard let node = catalog.node(id: .init(rawValue: region.rawValue)) else {
                throw RegionGeometryError.missingResource(region.rawValue)
            }
            guard node.isLoggable else { return [] }
            if let cached = cached[node.id] { return cached }
            let outlines = try RegionLog.geometryCatalog.measure(
                .loadRegionOutlines(region),
                budget: .seconds(1),
            ) {
                if node.geometryFile != nil { return try physicalOutlines(for: node) }
                var builder = OutlineBuilder()
                let title = node.localizedName
                for member in catalog.geometryNodes(for: node) {
                    for outline in try physicalOutlines(for: member) {
                        builder.add(
                            title: title,
                            region: region,
                            coordinates: outline.coordinates,
                            holes: outline.holes,
                        )
                    }
                }
                return builder.outlines
            }
            cached[node.id] = outlines
            return outlines
        }

        private func physicalOutlines(for node: RegionCatalog.Node) throws -> [RegionOutline] {
            if let cached = cached[node.id] { return cached }
            var builder = OutlineBuilder()
            try builder.add(node: node, resourceURL: resourceURL(node))
            cached[node.id] = builder.outlines
            return builder.outlines
        }
    }
}

/// Accumulates `RegionOutline`s while assigning each a unique, stable
/// `ID`, and drops degenerate rings (fewer than 3 vertices can't be
/// drawn).
private struct OutlineBuilder {
    private(set) var outlines: [RegionOutline] = []
    private var nextIndex = 0

    mutating func add(node: RegionCatalog.Node, resourceURL: URL?) throws {
        guard let resourceURL else {
            throw RegionGeometryError.missingResource(node.geometryFile ?? node.id.rawValue)
        }
        let title = node.localizedName
        let start = outlines.count
        for polygon in try RegionGeometryReader.polygons(at: resourceURL) {
            add(
                title: title,
                region: node.region,
                coordinates: polygon.vertices,
                holes: polygon.holes,
            )
        }
        guard outlines.count > start else {
            throw RegionGeometryError.emptyResource(resourceURL.lastPathComponent)
        }
    }

    mutating func add(
        title: String,
        region: Region?,
        coordinates: [Coordinate],
        holes: [[Coordinate]],
    ) {
        guard coordinates.isValidPolygonRing else { return }
        outlines.append(RegionOutline(
            id: RegionOutline.ID(title: title, index: nextIndex),
            title: title,
            region: region,
            coordinates: coordinates,
            holes: holes,
        ))
        nextIndex += 1
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
