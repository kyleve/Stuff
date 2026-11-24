import AppIntents
import RegionKit
import WhereCore

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
/// of a region's spelling. The system builds the "pick a region" menu from
/// `RegionEntityQuery.suggestedEntities()`, which surfaces the user's *tracked*
/// regions.
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

    /// The user's tracked regions as entities, in the catalog's canonical order
    /// — the "pick a region" menu and the Spotlight index. Takes `services` so
    /// it's testable; the query resolves the app-registered handoff via
    /// `@Dependency`, and the Spotlight indexer receives it from the app.
    static func tracked(from services: WhereServices) async throws -> [RegionEntity] {
        let regions = try await services.trackedRegions()
        return Region.inCanonicalOrder(regions).map(RegionEntity.init)
    }
}

/// Resolves available regions by stored ID or localized name. Opening the
/// picker without a search offers the user's tracked regions.
public struct RegionEntityQuery: EntityStringQuery {
    /// The app-registered services handoff (see `IntentServices`); resolved by
    /// the App Intents dependency container, never a singleton of ours.
    @Dependency private var intentServices: IntentServices

    public init() {}

    public func entities(for identifiers: [RegionEntity.ID]) async throws -> [RegionEntity] {
        identifiers.compactMap { identifier in
            Region(rawValue: identifier).map(RegionEntity.init)
        }
    }

    /// A typed name can find an untracked destination. An empty search uses
    /// the same tracked suggestions as opening the picker.
    public func entities(matching string: String) async throws -> [RegionEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try await suggestedEntities() }
        return Region.allCases.filter { $0.localizedName.localizedStandardContains(query) }
            .map(RegionEntity.init)
    }

    public func suggestedEntities() async throws -> [RegionEntity] {
        try await RegionEntity.tracked(from: intentServices.current())
    }
}
