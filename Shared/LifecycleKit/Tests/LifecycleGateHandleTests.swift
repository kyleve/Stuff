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

    @Test(arguments: [false, true])
    func cancellingWaitCancelsAndDrainsItsOperation(resolveBeforeCancellation: Bool) async throws {
        let handle = makeHandle()
        let dependency = LifecycleOperationGate()
        var finished = false
        var waiterReturned = false
        let waiter = Task {
            await #expect(throws: CancellationError.self) {
                try await handle.waitForResolution()
            }
            waiterReturned = true
        }
        handle.perform {
            if resolveBeforeCancellation { handle.complete() }
            await dependency.wait()
            #expect(Task.isCancelled)
            finished = true
            handle.complete() // A late completion cannot revive a cancelled gate.
        }
        try await waitUntil { dependency.entered }
        waiter.cancel()
        try await waitUntil { dependency.cancelled }
        #expect(!waiterReturned)
        #expect(!finished)
        dependency.release()
        await waiter.value
        #expect(finished)
        var staleOperationRan = false
        handle.perform { staleOperationRan = true }
        await Task.yield()
        #expect(!staleOperationRan)
    }

    @Test func resolutionDrainsWorkAndIgnoresDuplicateStarts() async throws {
        let handle = makeHandle()
        let dependency = LifecycleOperationGate()
        var finished = false
        var waiterReturned = false
        var starts = 0
        let waiter = Task {
            try await handle.waitForResolution()
            waiterReturned = true
        }
        handle.perform {
            starts += 1
            handle.complete()
            await dependency.wait()
            #expect(!Task.isCancelled)
            finished = true
        }
        handle.perform { starts += 1 }
        try await waitUntil { dependency.entered }
        #expect(!waiterReturned)
        dependency.release()
        try await waiter.value
        #expect(finished)
        #expect(starts == 1)
    }

    @Test func alreadyCancelledWaitNeverStartsGateWork() async {
        let handle = makeHandle()
        var ran = false
        let waiter = Task {
            await #expect(throws: CancellationError.self) {
                try await handle.waitForResolution()
            }
        }
        waiter.cancel()
        await waiter.value
        handle.perform { ran = true }
        await Task.yield()
        #expect(!ran)
    }
}
