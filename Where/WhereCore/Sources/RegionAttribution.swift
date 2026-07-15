import Foundation
import os
import RegionKit

/// A live, swappable `RegionAttributing` derived from the store's tracked
/// regions. A reference type so every `WhereServices` collaborator that holds it
/// sees a rebuild the moment the tracked set changes — a local edit or a remote
/// CloudKit import, both of which arrive on `store.changes()`.
///
/// `region(at:)` / `distanceToBoundary(_:from:)` forward to the current
/// snapshot. Rebuilding (re-parsing the per-region GeoJSON) happens only when
/// the tracked *set* actually changes, so reacting to every `changes()` ping
/// stays cheap on the GPS hot path (a fetch + a set compare).
final class RegionAttribution: RegionAttributing {
    private struct State {
        var attributor: RegionAttributor
        var trackedIDs: Set<String>
    }

    private static let logger = WhereLog.channel(.regionAttribution)

    private let store: any WhereStore
    private let state: OSAllocatedUnfairLock<State>
    /// Set once in `init` and only cancelled in `deinit`, so there's no
    /// concurrent access to guard.
    private nonisolated(unsafe) var observer: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the source of tracked regions and the `changes()` signal.
    ///   - initial: the attributor for the tracked set as of construction (built
    ///     by ``WhereServices/make(store:locationSource:)`` after reading the
    ///     store, so there's no flash of the wrong set at launch).
    ///   - trackedIDs: the region ids `initial` was built from.
    init(store: any WhereStore, initial: RegionAttributor, trackedIDs: Set<String>) {
        self.store = store
        state = OSAllocatedUnfairLock(initialState: State(
            attributor: initial,
            trackedIDs: trackedIDs,
        ))
        observer = Task { [weak self] in
            for await _ in store.changes() {
                await self?.reconcile()
            }
        }
    }

    deinit {
        observer?.cancel()
    }

    private var current: RegionAttributor {
        state.withLock { $0.attributor }
    }

    func region(at coordinate: Coordinate) -> Region {
        current.region(at: coordinate)
    }

    func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double? {
        current.distanceToBoundary(of: region, from: coordinate)
    }

    var loadedRegions: [Region] {
        current.loadedRegions
    }

    /// Re-read the tracked regions and rebuild the attributor when the set
    /// changed. Cheap when nothing changed (a fetch + a set compare); the file
    /// parse runs only on an actual change. Serialized by the single observer
    /// task; also exposed so callers/tests can reconcile deterministically.
    func reconcile() async {
        let tracked: Set<Region>
        do {
            tracked = try await store.trackedRegions()
        } catch {
            // Degraded-but-handled: keep the last-good attributor rather than
            // silently freezing on an empty/stale set, and surface the failure so
            // a persistent read error is observable instead of invisible.
            Self.logger.warning("Failed to read tracked regions for attributor rebuild: \(error)")
            return
        }
        let ids = Set(tracked.map(\.rawValue))
        let changed = state.withLock { $0.trackedIDs != ids }
        guard changed else { return }
        // Canonical order so the rebuilt attributor's first-match priority is
        // deterministic (see WhereServices.make).
        let rebuilt = RegionAttributor(for: Region.inCanonicalOrder(tracked))
        state.withLock { $0 = State(attributor: rebuilt, trackedIDs: ids) }
    }
}
