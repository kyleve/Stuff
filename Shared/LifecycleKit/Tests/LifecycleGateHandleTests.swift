@testable import LifecycleKit
import Testing

private struct Boom: Error {}

@MainActor
struct LifecycleGateHandleTests {
    private func makeHandle() -> LifecycleGateHandle {
        LifecycleGateHandle(id: "gate", reason: .userForeground)
    }

    @Test func completeResumesWaiter() async throws {
        let handle = makeHandle()
        let waiter = Task { @MainActor in
            try await handle.waitForResolution()
            return true
        }
        await Task.yield()
        handle.complete()
        #expect(try await waiter.value)
    }

    @Test func failThrowsFromWaiter() async {
        let handle = makeHandle()
        let waiter = Task { @MainActor in
            do {
                try await handle.waitForResolution()
                return false
            } catch is Boom {
                return true
            } catch {
                return false
            }
        }
        await Task.yield()
        handle.fail(Boom())
        #expect(await waiter.value)
    }

    @Test func resolvingBeforeWaitingStillDelivers() async throws {
        let handle = makeHandle()
        handle.complete()
        try await handle.waitForResolution()
    }

    @Test func failingBeforeWaitingStillThrows() async {
        let handle = makeHandle()
        handle.fail(Boom())
        await #expect(throws: Boom.self) {
            try await handle.waitForResolution()
        }
    }

    @Test func secondResolutionIsIgnored() async throws {
        let handle = makeHandle()
        handle.complete()
        handle.fail(Boom())
        try await handle.waitForResolution()
    }

    @Test func cancellingTheWaiterThrowsCancellationError() async {
        let handle = makeHandle()
        let waiter = Task { @MainActor in
            do {
                try await handle.waitForResolution()
                return "resolved"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other"
            }
        }
        await Task.yield()
        waiter.cancel()
        #expect(await waiter.value == "cancelled")
    }

    @Test func previewHandleCarriesNoGateType() {
        let handle = makeHandle()
        #expect(handle.gateType == nil)
        #expect(handle.value == nil)
    }
}
