import Foundation
import Testing
@testable import WhereCore

struct RemoteDataChangeReconcilerTests {
    @Test func shutdownDrainsReconciliationAndTerminatesObservation() async throws {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self)
        let hold = ReconciliationHold()
        let reconciler: any WhereShutdownable = RemoteDataChangeReconciler(changes: changes) {
            await hold.reconcile()
        }
        continuation.yield()
        try await waitUntil { await hold.isWaiting }
        let shutdown = Task {
            await reconciler.shutdown()
            await hold.didShutdown()
        }
        // AsyncStream observes cancellation before the in-flight reconciliation is released.
        try await waitUntil { await hold.isCancelled }
        #expect(await hold.shutdownFinished == false)
        await hold.release()
        await shutdown.value
        #expect(await hold.shutdownFinished)
        if case .terminated = continuation.yield() {} else {
            Issue.record("Shutdown must terminate remote observation")
        }
        await reconciler.shutdown()
    }

    @Test func remotePingRunsTheInjectedReconciliation() async throws {
        let changes = StoreChangeBroadcaster()
        let recorder = ReconcileRecorder()
        let reconciler = RemoteDataChangeReconciler(changes: changes.subscribe()) {
            await recorder.record()
        }

        changes.send()

        try await waitUntil { await recorder.count == 1 }
        _ = reconciler
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @Sendable () async -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("waitUntil timed out")
    }
}

private actor ReconciliationHold {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isCancelled = false
    private(set) var shutdownFinished = false
    var isWaiting: Bool {
        continuation != nil
    }

    func reconcile() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancelled() }
        }
    }

    func cancelled() {
        isCancelled = true
    }

    func didShutdown() {
        shutdownFinished = true
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ReconcileRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
