@testable import Flyover
import Testing

@MainActor
struct FlyoverPreviewReadinessTests {
    @Test func waitsForANonemptyLatestExpectationAndEveryExpectedLoad() async {
        let readiness = FlyoverPreviewReadiness<TestScreen>()
        let first = key(.first)
        let second = key(.second)
        let waiter = Task { @MainActor in
            await readiness.waitUntilReady()
        }
        await waitUntil { readiness.waiterCount == 1 }

        readiness.expect([])
        #expect(readiness.isReadyForLatestExpectation == false)

        readiness.expect([first, second])
        readiness.beganLoading(first)
        readiness.finishedLoading(first)
        #expect(readiness.isReadyForLatestExpectation == false)

        readiness.beganLoading(second)
        readiness.finishedLoading(second)
        await waiter.value
        #expect(readiness.isReadyForLatestExpectation)
    }

    @Test func changedExpectationSupersedesStaleCompletions() async {
        let readiness = FlyoverPreviewReadiness<TestScreen>()
        let firstGeneration = key(.first, generation: 0)
        let secondGeneration = key(.first, generation: 1)
        readiness.expect([firstGeneration])
        readiness.beganLoading(firstGeneration)

        let waiter = Task { @MainActor in
            await readiness.waitUntilReady()
        }
        await waitUntil { readiness.waiterCount == 1 }

        readiness.expect([secondGeneration])
        readiness.unloaded(firstGeneration)
        readiness.finishedLoading(firstGeneration)
        #expect(readiness.isReadyForLatestExpectation == false)

        readiness.beganLoading(secondGeneration)
        readiness.finishedLoading(secondGeneration)
        await waiter.value
        #expect(readiness.isReadyForLatestExpectation)
        #expect(readiness.expectationGeneration == 2)
    }

    @Test func completionMayArriveBeforeItsFirstExpectationIsPublished() async {
        let readiness = FlyoverPreviewReadiness<TestScreen>()
        let first = key(.first)

        readiness.beganLoading(first)
        readiness.finishedLoading(first)
        readiness.expect([first])

        #expect(readiness.isReadyForLatestExpectation)
        await readiness.waitUntilReady()
    }

    @Test func cancellationRemovesAWaitingCapture() async {
        let readiness = FlyoverPreviewReadiness<TestScreen>()
        readiness.expect([key(.first)])
        let waiter = Task { @MainActor in
            await readiness.waitUntilReady()
        }
        await waitUntil { readiness.waiterCount == 1 }

        waiter.cancel()
        await waiter.value

        #expect(readiness.waiterCount == 0)
        #expect(readiness.isReadyForLatestExpectation == false)
    }

    private func key(
        _ screenID: TestScreen,
        generation: Int = 0,
    ) -> FlyoverPreviewReadiness<TestScreen>.LoadKey {
        FlyoverPreviewReadiness<TestScreen>.LoadKey(
            screenID: screenID,
            variantID: FlyoverVariantID("default"),
            generation: generation,
        )
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        while predicate() == false {
            await Task.yield()
        }
    }

    private enum TestScreen: Hashable {
        case first
        case second
    }
}
