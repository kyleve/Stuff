import Foundation
import Testing
@testable import WhereCore

struct RemoteDataChangeReconcilerTests {
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

private actor ReconcileRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
