@testable import LifecycleKit
import Testing

private struct Boom: Error {}

@MainActor
struct StepHandleTests {
    @Test func completeResumesWaiter() async throws {
        let handle = StepHandle(reason: .userForeground)
        let waiter = Task { @MainActor in
            try await handle.waitForResolution()
            return true
        }
        await Task.yield()
        handle.complete()
        #expect(try await waiter.value)
    }

    @Test func failThrowsFromWaiter() async {
        let handle = StepHandle(reason: .userForeground)
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
        let handle = StepHandle(reason: .userForeground)
        handle.complete()
        try await handle.waitForResolution()
    }

    @Test func failingBeforeWaitingStillThrows() async {
        let handle = StepHandle(reason: .userForeground)
        handle.fail(Boom())
        await #expect(throws: Boom.self) {
            try await handle.waitForResolution()
        }
    }

    @Test func secondResolutionIsIgnored() async throws {
        let handle = StepHandle(reason: .userForeground)
        handle.complete()
        handle.fail(Boom())
        try await handle.waitForResolution()
    }
}
