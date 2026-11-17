import Testing
@testable import WhereUI

@MainActor
struct CalendarSnapshotReadinessTests {
    @Test(.timeLimit(.minutes(1)))
    func waitsForTheCurrentPresentationAfterAnEarlierCaptureCompleted() async {
        let readiness = CalendarSnapshotReadiness(mode: .detail)
        let previous = readiness.makePresentation()
        previous.reconcile(year: 2025, availableMonths: [], estimateMonth: nil)
        await readiness.waitForLayout()

        let current = readiness.makePresentation()
        let waiter = Task.immediate {
            await readiness.waitForLayout()
            #expect(current.year == 2026)
        }
        // Give the observation its first transaction before completing this view.
        await Task.yield()
        previous.reconcile(year: 2024, availableMonths: [], estimateMonth: nil)
        await Task.yield()
        current.reconcile(year: 2026, availableMonths: [], estimateMonth: nil)
        await waiter.value
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsContentThatMountedBeforeTheHook() async {
        let readiness = CalendarSnapshotReadiness(mode: .overview)
        let presentation = readiness.makePresentation()
        presentation.reconcile(year: 2026, availableMonths: [], estimateMonth: nil)
        await readiness.waitForLayout()
        #expect(!Task.isCancelled)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func cancellationAllowsTheNextMount(beforeMount: Bool) async {
        let readiness = CalendarSnapshotReadiness(mode: .detail)
        let presentation = beforeMount ? nil : readiness.makePresentation()
        let waiter = Task.immediate { await readiness.waitForLayout() }
        await Task.yield()
        waiter.cancel()
        await waiter.value
        #expect(presentation?.year == nil)

        let next = readiness.makePresentation()
        next.reconcile(year: 2026, availableMonths: [], estimateMonth: nil)
        await readiness.waitForLayout()
    }

    @Test(.timeLimit(.minutes(1)))
    func mountingCanFollowTheMeasurementHook() async {
        let readiness = CalendarSnapshotReadiness(mode: .detail)
        var completed = false
        let waiter = Task.immediate {
            await readiness.waitForLayout()
            completed = true
        }
        #expect(!completed)
        let presentation = readiness.makePresentation()
        presentation.reconcile(year: 2026, availableMonths: [], estimateMonth: nil)
        await waiter.value
        #expect(completed)
    }
}
