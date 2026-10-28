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
public actor RegionSpotlightIndexer {
    public init() {}

    private static let logger = WhereIntentsLog.logger

    /// Not system-instantiated (the app calls this), so the services handoff
    /// arrives by plain injection rather than `@Dependency`.
    public func indexRegions(resolving intentServices: IntentServices) async {
        do {
            let services = try await intentServices.current()
            let entities = try await RegionEntity.tracked(from: services)

            try await CSSearchableIndex.default().indexAppEntities(entities)

            Self.logger.spotlightIndexed(regionCount: .restricted(.count, entities.count))
        } catch {
            // Degraded-but-handled: search integration is a nicety, so a failure
            // is logged and swallowed rather than surfaced to the user.
            await clearIndex()
            Self.logger.spotlightIndexFailed(error: .restricted(.errorDetails, error))
        }
    }

    public func withdraw() async {
        await clearIndex()
    }

    private func clearIndex() async {
        do { try await CSSearchableIndex.default().deleteAllSearchableItems() }
        catch {
            Self.logger.spotlightIndexFailed(error: .restricted(.errorDetails, error))
        }
    }
}
