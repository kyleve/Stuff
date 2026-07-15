import AppIntents
import RegionKit

/// A `Region` as an `AppEntity`: the region parameter every intent operates on,
/// the Spotlight-indexable representation of a tracked region, and the
/// reload-safe parameter of the interactive day-count snippet. Identified by
/// `Region.rawValue`, so it round-trips losslessly with `RegionKit.Region`.
///
/// It's an entity rather than an `AppEnum` on purpose: App Intents requires an
/// `AppEnum`'s `caseDisplayRepresentations` to be *compile-time-constant*
/// literals, which would force restating RegionKit's region names here. An
/// entity's `displayRepresentation` is per-instance and evaluated at runtime, so
/// it reads `Region.localizedName` directly — RegionKit stays the single source
/// of a region's spelling. The system builds the same "pick a region" menu from
/// `RegionEntityQuery.suggestedEntities()`.
public struct RegionEntity: AppEntity, Identifiable, Sendable {
    /// `Region.rawValue` — the stable data identifier.
    public var id: String

    public init(_ region: Region) {
        id = region.rawValue
    }

    /// The backing region, falling back to `.other` for an unknown id.
    public var region: Region {
        Region(rawValue: id) ?? .other
    }

    /// App Intents extracts this static metadata at build time, so it must be a
    /// constant initializer call (not computed / not `Bundle.module`-backed); the
    /// literal is localized through the app's App Intents string extraction.
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Region")

    /// Per-instance and runtime, so it can read RegionKit's localized name
    /// rather than a duplicated literal.
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(region.localizedName)")
    }

    public static let defaultQuery = RegionEntityQuery()

    /// Every tracked region as an entity, in `Region.allCases` order.
    public static var all: [RegionEntity] {
        Region.allCases.map(RegionEntity.init)
    }
}

/// Resolves `RegionEntity` values for the fixed, five-case region set — no
/// store access needed, so it also serves as the entities' `suggestedEntities`
/// (the full menu) and the source for Spotlight indexing.
public struct RegionEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [RegionEntity.ID]) async throws -> [RegionEntity] {
        identifiers.compactMap { identifier in
            Region(rawValue: identifier).map(RegionEntity.init)
        }
    }

    public func suggestedEntities() async throws -> [RegionEntity] {
        RegionEntity.all
    }
}
