import AppIntents
import CoreSpotlight
import RegionKit
import WhereCore

/// Makes `RegionEntity` part of the system's on-device index so a Spotlight
/// search for a region name surfaces Where — and Siri can reason over the
/// tracked regions. The five regions are a tiny, fixed set, so they're indexed
/// wholesale at launch rather than incrementally.
extension RegionEntity: IndexedEntity {}

/// Indexes the tracked regions into Spotlight. Runs once at app launch (see the
/// app's `AppDelegate`); indexing five items is cheap and idempotent.
public enum RegionSpotlightIndexer {
    private static let logger = WhereLog.channel(.whereIntents)

    public static func indexRegions() async {
        do {
            try await CSSearchableIndex.default().indexAppEntities(RegionEntity.all)
            logger.info("Indexed \(RegionEntity.all.count) region(s) for Spotlight")
        } catch {
            // Degraded-but-handled: search integration is a nicety, so a failure
            // is logged and swallowed rather than surfaced to the user.
            logger.warning("Failed to index regions for Spotlight: \(error)")
        }
    }
}
