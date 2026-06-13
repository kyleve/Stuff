@testable import LifecycleKit
import Testing

private struct Boom: Error {}

@MainActor
struct LifecycleStepUIBridgeTests {
    @Test func completeResumesWaiter() async throws {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        let waiter = Task { @MainActor in
            try await bridge.waitForResolution()
            return true
        }
        await Task.yield()
        bridge.complete()
        #expect(try await waiter.value)
    }

    @Test func failThrowsFromWaiter() async {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        let waiter = Task { @MainActor in
            do {
                try await bridge.waitForResolution()
                return false
            } catch is Boom {
                return true
            } catch {
                return false
            }
        }
        await Task.yield()
        bridge.fail(Boom())
        #expect(await waiter.value)
    }

    @Test func resolvingBeforeWaitingStillDelivers() async throws {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        bridge.complete()
        try await bridge.waitForResolution()
    }

    @Test func failingBeforeWaitingStillThrows() async {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        bridge.fail(Boom())
        await #expect(throws: Boom.self) {
            try await bridge.waitForResolution()
        }
    }

    @Test func secondResolutionIsIgnored() async throws {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        bridge.complete()
        bridge.fail(Boom())
        try await bridge.waitForResolution()
    }
}
