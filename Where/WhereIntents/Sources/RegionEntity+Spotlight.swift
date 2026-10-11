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
    private var isPublishing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init() {}

    private static let logger = WhereIntentsLog.logger

    /// Not system-instantiated (the app calls this), so the services handoff
    /// arrives by plain injection rather than `@Dependency`.
    public func indexRegions(resolving intentServices: IntentServices) async {
        await beginExclusive()
        defer { endExclusive() }
        do {
            let services = try await intentServices.current()
            let entities = try await RegionEntity.tracked(from: services)
            try await services.validateDataAccess()
            try await CSSearchableIndex.default().indexAppEntities(entities)
            try await services.validateDataAccess()
            Self.logger { .spotlightIndexed(regionCount: entities.count) }
        } catch {
            // Degraded-but-handled: search integration is a nicety, so a failure
            // is logged and swallowed rather than surfaced to the user.
            await clearIndex()
            Self.logger(attachments: [.error(error, name: "index-error")]) {
                .spotlightIndexFailed(description: String(describing: error))
            }
        }
    }

    public func withdraw() async {
        await beginExclusive()
        defer { endExclusive() }
        await clearIndex()
    }

    private func clearIndex() async {
        do { try await CSSearchableIndex.default().deleteAllSearchableItems() }
        catch {
            Self.logger(attachments: [.error(error, name: "index-withdrawal-error")]) {
                .spotlightIndexFailed(description: error.localizedDescription)
            }
        }
    }

    private func beginExclusive() async {
        if isPublishing { await withCheckedContinuation { waiters.append($0) } }
        else { isPublishing = true }
    }

    private func endExclusive() {
        if waiters.isEmpty { isPublishing = false }
        else { waiters.removeFirst().resume() }
    }
}
