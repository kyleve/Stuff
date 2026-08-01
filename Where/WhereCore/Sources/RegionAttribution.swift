import Foundation
import os
import PeriscopeCore
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

    /// Serializes every explicit and observed reconciliation. The widget's
    /// remote-change path also reconciles before it publishes, so keeping the
    /// read/rebuild/install sequence on one actor prevents an older rebuild
    /// from landing after a newer tracked-region change.
    private actor Reconciler {
        private let store: any WhereStore
        private let state: OSAllocatedUnfairLock<State>
        private var isReconciling = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(store: any WhereStore, state: OSAllocatedUnfairLock<State>) {
            self.store = store
            self.state = state
        }

        func reconcile() async {
            await beginExclusive()
            defer { endExclusive() }

            let tracked: Set<Region>
            do {
                tracked = try await store.trackedRegions()
            } catch {
                // Degraded-but-handled: keep the last-good attributor rather
                // than replacing it with an empty or partially read set.
                RegionAttribution.logger {
                    .trackedRegionsReadFailed(description: String(describing: error))
                }
                return
            }
            let ids = Set(tracked.map(\.rawValue))
            let changed = state.withLock { $0.trackedIDs != ids }
            guard changed else { return }
            // Canonical order so the rebuilt attributor's first-match priority
            // is deterministic (see WhereServices.make).
            let rebuilt = RegionAttribution.logger.measure(.rebuild, budget: .seconds(1)) {
                RegionAttributor(for: Region.inCanonicalOrder(tracked))
            }
            state.withLock { $0 = State(attributor: rebuilt, trackedIDs: ids) }
        }

        /// Hold the reconciliation slot across the async store read and the
        /// synchronous rebuild/install. Actor isolation alone is insufficient:
        /// another call can otherwise enter while `trackedRegions()` suspends
        /// and let an older read install after a newer one.
        private func beginExclusive() async {
            if isReconciling {
                await withCheckedContinuation { waiters.append($0) }
            } else {
                isReconciling = true
            }
        }

        private func endExclusive() {
            if waiters.isEmpty {
                isReconciling = false
            } else {
                waiters.removeFirst().resume()
            }
        }
    }

    private static let logger = WhereLog.root(RegionAttributionLog.self)

    private let state: OSAllocatedUnfairLock<State>
    private let reconciler: Reconciler
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
        let state = OSAllocatedUnfairLock(initialState: State(
            attributor: initial,
            trackedIDs: trackedIDs,
        ))
        self.state = state
        reconciler = Reconciler(store: store, state: state)
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
    /// parse runs only on an actual change. The reconciler actor serializes the
    /// ordinary observer with explicit callers such as external publishing.
    func reconcile() async {
        await reconciler.reconcile()
    }
}
