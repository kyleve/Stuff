@testable import Flyover
import Testing

@MainActor
struct FlyoverContentLoadCoordinatorTests {
    @Test func cancelledWaiterFinishesBeforeActiveOperationAndPreservesTheQueue() async throws {
        let coordinator = FlyoverContentLoadCoordinator()
        var finishFirst: CheckedContinuation<Void, Never>?
        var events: [String] = []
        let first = Task { @MainActor in
            await coordinator.perform {
                await withCheckedContinuation { finishFirst = $0 }
            }
        }
        try await waitForFlyover { finishFirst != nil }
        defer { finishFirst?.resume() }

        var cancelledFinished = false
        let cancelled = Task { @MainActor in
            events.append("cancelled queued")
            await coordinator.perform { events.append("cancelled ran") }
            cancelledFinished = true
        }
        try await waitForFlyover { events.contains("cancelled queued") }

        let next = Task { @MainActor in
            events.append("next queued")
            await coordinator.perform { events.append("next ran") }
        }
        try await waitForFlyover { events.contains("next queued") }
        cancelled.cancel()
        try await waitForFlyover { cancelledFinished }
        #expect(events == ["cancelled queued", "next queued"])

        finishFirst?.resume()
        finishFirst = nil
        await first.value
        await cancelled.value
        await next.value
        #expect(events == ["cancelled queued", "next queued", "next ran"])

        await coordinator.perform { events.append("last ran") }
        #expect(events.last == "last ran")
    }

    @Test func cancellationRacingHandoffDoesNotReleaseAnotherOperationsSlot() async throws {
        let coordinator = FlyoverContentLoadCoordinator()
        for _ in 0 ..< 100 {
            var finishFirst: CheckedContinuation<Void, Never>?
            var requested = false
            var activeCount = 0
            let first = Task { @MainActor in
                await coordinator.perform {
                    activeCount += 1
                    await withCheckedContinuation { finishFirst = $0 }
                    activeCount -= 1
                }
            }
            try await waitForFlyover { finishFirst != nil }
            let cancelled = Task { @MainActor in
                requested = true
                await coordinator.perform {
                    activeCount += 1
                    #expect(activeCount == 1)
                    await Task.yield()
                    activeCount -= 1
                }
            }
            try await waitForFlyover { requested }
            finishFirst?.resume()
            cancelled.cancel()
            let next = Task { @MainActor in
                await coordinator.perform {
                    activeCount += 1
                    #expect(activeCount == 1)
                    await Task.yield()
                    activeCount -= 1
                }
            }
            await first.value
            await cancelled.value
            await next.value
            #expect(activeCount == 0)
        }
    }

    @Test func operationsRunOneAtATimeInRequestOrder() async {
        let coordinator = FlyoverContentLoadCoordinator()
        var events: [String] = []
        var finishFirst: CheckedContinuation<Void, Never>?

        let first = Task { @MainActor in
            await coordinator.perform {
                events.append("first started")
                await withCheckedContinuation { finishFirst = $0 }
                events.append("first finished")
            }
        }
        while finishFirst == nil {
            await Task.yield()
        }

        let second = Task { @MainActor in
            events.append("second requested")
            await coordinator.perform {
                events.append("second started")
            }
        }
        while events.contains("second requested") == false {
            await Task.yield()
        }

        #expect(events == ["first started", "second requested"])

        finishFirst?.resume()
        await first.value
        await second.value

        #expect(events == [
            "first started",
            "second requested",
            "first finished",
            "second started",
        ])
    }

    @Test func cancelledWaiterDoesNotRunItsOperation() async {
        let coordinator = FlyoverContentLoadCoordinator()
        var events: [String] = []
        var finishFirst: CheckedContinuation<Void, Never>?

        let first = Task { @MainActor in
            await coordinator.perform {
                events.append("first started")
                await withCheckedContinuation { finishFirst = $0 }
            }
        }
        while finishFirst == nil {
            await Task.yield()
        }

        let cancelled = Task { @MainActor in
            events.append("second requested")
            await coordinator.perform {
                events.append("second started")
            }
        }
        while events.contains("second requested") == false {
            await Task.yield()
        }
        cancelled.cancel()
        finishFirst?.resume()

        await first.value
        await cancelled.value

        #expect(events == ["first started", "second requested"])
    }
}
