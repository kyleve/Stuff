import Foundation

/// Tracks the latest nonempty set of canvas previews whose real content must
/// finish loading before an intrinsic snapshot may measure Flyover.
@MainActor
final class FlyoverPreviewReadiness<ScreenID: Hashable> {
    struct LoadKey: Hashable {
        let screenID: ScreenID
        let variantID: FlyoverVariantID
        let generation: Int
    }

    private(set) var expectedKeys: Set<LoadKey>?
    private(set) var expectationGeneration = 0
    private(set) var waiterCount = 0
    private var activeKeys: Set<LoadKey> = []
    private var completedKeys: Set<LoadKey> = []
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var isReadyForLatestExpectation: Bool {
        guard let expectedKeys else {
            return false
        }
        return expectedKeys.isSubset(of: completedKeys)
    }

    /// Supersedes the previous viewport expectation. Empty sets are ignored so
    /// an intrinsic capture cannot declare readiness before scroll geometry has
    /// published its first visible region.
    func expect(_ keys: Set<LoadKey>) {
        guard keys.isEmpty == false, keys != expectedKeys else {
            return
        }
        expectedKeys = keys
        expectationGeneration += 1
        completedKeys.formIntersection(keys)
        resumeWaitersIfReady()
    }

    func beganLoading(_ key: LoadKey) {
        activeKeys.insert(key)
        completedKeys.remove(key)
    }

    func finishedLoading(_ key: LoadKey) {
        guard activeKeys.contains(key) else {
            return
        }
        completedKeys.insert(key)
        resumeWaitersIfReady()
    }

    func unloaded(_ key: LoadKey) {
        activeKeys.remove(key)
        completedKeys.remove(key)
    }

    /// Waits for whichever nonempty expectation is current when readiness is
    /// reached. If viewport or variant state changes while suspended, the new
    /// expectation replaces the old one instead of allowing stale completions
    /// to release the waiter.
    func waitUntilReady() async {
        guard isReadyForLatestExpectation == false else {
            return
        }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard Task.isCancelled == false else {
                    continuation.resume()
                    return
                }
                waiters[waiterID] = continuation
                waiterCount = waiters.count
                resumeWaitersIfReady()
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelWaiter(waiterID)
            }
        }
    }

    private func resumeWaitersIfReady() {
        guard isReadyForLatestExpectation else {
            return
        }
        let readyWaiters = Array(waiters.values)
        waiters.removeAll()
        waiterCount = 0
        for waiter in readyWaiters {
            waiter.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
        waiterCount = waiters.count
    }
}
