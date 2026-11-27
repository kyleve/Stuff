import AppIntents
import CoreSpotlight
import PeriscopeCore
import RegionKit
import WhereCore

/// Makes `RegionEntity` part of the system's on-device index so a Spotlight
/// search for a region name surfaces Where — and Siri can reason over the
/// tracked regions. The tracked set is small (a handful), so it's indexed
/// wholesale at launch rather than incrementally.
extension RegionEntity: IndexedEntity {}

/// Indexes the user's tracked regions into Spotlight. Runs once at app launch
/// (see the app's `AppDelegate`); indexing a handful of items is cheap and
/// idempotent, and re-runs pick up any change to the tracked set.
public enum RegionSpotlightIndexer {
    private static let logger = WhereIntentsLog.logger

    /// Not system-instantiated (the app calls this), so the services handoff
    /// arrives by plain injection rather than `@Dependency`.
    public static func indexRegions(resolving intentServices: IntentServices) async {
        do {
            let entities = try await RegionEntity.tracked(from: intentServices.current())
            let index = CSSearchableIndex.default()
            // Upserting tracked entities leaves older entries, including Canada, in Spotlight.
            let retired = RegionCatalog.shared.nodes.filter { !$0.isLoggable }.map(\.id.rawValue)
            try await index.deleteAppEntities(identifiedBy: retired, ofType: RegionEntity.self)
            try await index.indexAppEntities(entities)
            logger.spotlightIndexed(regionCount: .restricted(.count, entities.count))
        } catch {
            // Degraded-but-handled: search integration is a nicety, so a failure
            // is logged and swallowed rather than surfaced to the user.
            logger.spotlightIndexFailed(
                error: .restricted(.errorDetails, error),
            )
        }
    }
}
