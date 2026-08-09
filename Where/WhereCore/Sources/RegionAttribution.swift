import Foundation
import os
import PeriscopeCore
import RegionKit

/// A live attributor that can deterministically catch up with its backing
/// store before a dependent operation continues.
protocol RegionAttributionReconciling: RegionAttributing {
    func reconcile() async
}

/// A live, swappable `RegionAttributing` derived from the store's tracked
/// regions. A reference type so every `WhereServices` collaborator that holds it
/// sees a rebuild the moment the tracked set changes — a local edit or a remote
/// CloudKit import, both of which arrive on `store.changes()`.
///
/// `region(at:)` / `distanceToBoundary(_:from:)` forward to the current
/// snapshot. Rebuilding (re-parsing the per-region GeoJSON) happens only when
/// the tracked *set* actually changes, so reacting to every `changes()` ping
/// stays cheap on the GPS hot path (a fetch + a set compare).
final class RegionAttribution: RegionAttributionReconciling {
    /// Serializes the background observer with explicit full-fan-out reconciliations. Actor
    /// isolation alone would still be reentrant across the store read, so ownership is handed
    /// directly to one waiter at a time.
    private actor ReconciliationGate {
        private var isOccupied = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            if isOccupied {
                await withCheckedContinuation { waiters.append($0) }
            } else {
                isOccupied = true
            }
        }

        func release() {
            if waiters.isEmpty {
                isOccupied = false
            } else {
                waiters.removeFirst().resume()
            }
        }
    }

    private struct State {
        var attributor: RegionAttributor
        var trackedIDs: Set<String>
    }

    private static let logger = WhereLog.root(RegionAttributionLog.self)

    private let store: any WhereStore
    private let state: OSAllocatedUnfairLock<State>
    private let reconciliationGate = ReconciliationGate()
    /// Set once in `init` and only cancelled in `deinit`, so there's no
    /// concurrent access to guard.
    private nonisolated(unsafe) var observer: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the source of tracked regions.
    ///   - changes: the committed-data signal this live attribution observes.
    ///   - initial: the attributor for the tracked set as of construction (built
    ///     by ``WhereServices/make(store:locationSource:)`` after reading the
    ///     store, so there's no flash of the wrong set at launch).
    ///   - trackedIDs: the region ids `initial` was built from.
    init(
        store: any WhereStore,
        changes: AsyncStream<Void>,
        initial: RegionAttributor,
        trackedIDs: Set<String>,
    ) {
        self.store = store
        state = OSAllocatedUnfairLock(initialState: State(
            attributor: initial,
            trackedIDs: trackedIDs,
        ))
        observer = Task { [weak self] in
            for await _ in changes {
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
    /// parse runs only on an actual change. Serialized across the background
    /// observer and explicit full-fan-out callers.
    func reconcile() async {
        await reconciliationGate.acquire()
        await reconcileExclusively()
        await reconciliationGate.release()
    }

    private func reconcileExclusively() async {
        let tracked: Set<Region>
        do {
            tracked = try await store.trackedRegions()
        } catch {
            // Degraded-but-handled: keep the last-good attributor rather than
            // silently freezing on an empty/stale set, and surface the failure so
            // a persistent read error is observable instead of invisible.
            Self.logger { .trackedRegionsReadFailed(description: String(describing: error)) }
            return
        }
        let ids = Set(tracked.map(\.rawValue))
        let changed = state.withLock { $0.trackedIDs != ids }
        guard changed else { return }
        // Canonical order so the rebuilt attributor's first-match priority is
        // deterministic (see WhereServices.make). Re-parsing every tracked
        // region's GeoJSON is the expensive part, hence the span.
        let rebuilt = Self.logger.measure(.rebuild, budget: .seconds(1)) {
            RegionAttributor(for: Region.inCanonicalOrder(tracked))
        }
        state.withLock { $0 = State(attributor: rebuilt, trackedIDs: ids) }
    }
}
