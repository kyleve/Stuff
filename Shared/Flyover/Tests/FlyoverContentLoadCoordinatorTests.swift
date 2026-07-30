@testable import Flyover
import Testing

@MainActor
struct FlyoverContentLoadCoordinatorTests {
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
