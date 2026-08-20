import RegionKit
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct LocationCardsPresentationModelTests {
    private func preferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    private func item(_ region: Region, _ days: Int) -> RegionDays {
        RegionDays(region: region, days: days)
    }

    private func target(
        _ counts: [RegionDays],
        year: Int = 2026,
        isVisible: Bool = true,
    ) -> LocationCardsPresentationModel.ReconciliationID {
        LocationCardsPresentationModel.ReconciliationID(
            counts: counts,
            year: year,
            isVisible: isVisible,
        )
    }

    @Test func firstRevealEstablishesBaselineSilently() {
        let preferences = preferences()
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let current = [item(.california, 148), item(.newYork, 37)]

        let reconciliation = target(current)
        model.updateReconciliationTarget(reconciliation)
        #expect(model.presented(current) == current)
        model.reconcile(reconciliation)

        #expect(model.feedbackTrigger == 0)
        #expect(model.latestOvertake == nil)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [
            .california: 148,
            .newYork: 37,
        ])
    }

    @Test func countAndOrderRemainOldUntilLiveOvertakeReconciles() throws {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([
            .california: 100,
            .newYork: 99,
        ], in: 2026)
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let baseline = [item(.california, 100), item(.newYork, 99)]
        let baselineReconciliation = target(baseline)
        model.updateReconciliationTarget(baselineReconciliation)
        model.reconcile(baselineReconciliation)

        let current = [item(.newYork, 101), item(.california, 100)]
        let reconciliation = target(current)
        model.updateReconciliationTarget(reconciliation)
        #expect(model.presented(current) == baseline)
        #expect(model.willOvertake(reconciliation))

        let event = try #require(model.reconcile(reconciliation))

        #expect(model.presented(current) == current)
        #expect(event.winner == .newYork)
        #expect(event.passedRegion == .california)
        #expect(model.feedbackTrigger == 1)
        #expect(model.overtakeTrigger(for: .newYork) == 1)
        #expect(model.overtakeTrigger(for: .california) == 0)
    }

    @Test func increasedCountWithoutReorderTriggersOnlyCountFeedback() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([
            .california: 100,
            .newYork: 50,
        ], in: 2026)
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let baseline = [item(.california, 100), item(.newYork, 50)]
        let baselineReconciliation = target(baseline)
        model.updateReconciliationTarget(baselineReconciliation)
        model.reconcile(baselineReconciliation)

        let current = [item(.california, 101), item(.newYork, 50)]
        let reconciliation = target(current)
        model.updateReconciliationTarget(reconciliation)
        let event = model.reconcile(reconciliation)

        #expect(event == nil)
        #expect(model.feedbackTrigger == 1)
        #expect(model.latestOvertake == nil)
    }

    @Test func multipleChangedCardsProduceOneFeedbackEvent() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([
            .california: 148,
            .newYork: 37,
        ], in: 2026)
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let baseline = [item(.california, 148), item(.newYork, 37)]
        let baselineReconciliation = target(baseline)
        model.updateReconciliationTarget(baselineReconciliation)
        model.reconcile(baselineReconciliation)

        let current = [
            item(.california, 149),
            item(.newYork, 38),
        ]
        let reconciliation = target(current)
        model.updateReconciliationTarget(reconciliation)
        model.reconcile(reconciliation)

        #expect(model.feedbackTrigger == 1)
    }

    @Test func primaryMembershipChangeUpdatesQuietly() {
        let preferences = preferences()
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let baseline = [item(.california, 100), item(.newYork, 50)]
        let baselineReconciliation = target(baseline)
        model.updateReconciliationTarget(baselineReconciliation)
        model.reconcile(baselineReconciliation)

        let current = [item(.canada, 110), item(.california, 100)]
        let reconciliation = target(current)
        model.updateReconciliationTarget(reconciliation)

        #expect(model.presented(current) == baseline)
        #expect(!model.willOvertake(reconciliation))
        #expect(model.reconcile(reconciliation) == nil)
        #expect(model.presented(current) == current)
        #expect(model.latestOvertake == nil)
    }

    @Test func updateReceivedWhileHiddenSynchronizesOrderQuietlyOnReturn() {
        let preferences = preferences()
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let baseline = [item(.california, 100), item(.newYork, 99)]
        let baselineReconciliation = target(baseline)
        model.updateReconciliationTarget(baselineReconciliation)
        model.reconcile(baselineReconciliation)
        model.updateReconciliationTarget(target(baseline, isVisible: false))

        let current = [item(.newYork, 101), item(.california, 100)]
        let hiddenReconciliation = target(current, isVisible: false)
        model.updateReconciliationTarget(hiddenReconciliation)
        #expect(model.reconcile(hiddenReconciliation) == nil)
        let visibleReconciliation = target(current)
        model.updateReconciliationTarget(visibleReconciliation)

        #expect(model.presented(current).map(\.region) == [.newYork, .california])
        #expect(!model.willOvertake(visibleReconciliation))
        #expect(model.reconcile(visibleReconciliation) == nil)
        #expect(model.latestOvertake == nil)
    }

    @Test func preparingAnotherYearUsesOnlyThatYearsBaselineAndSuppressesOvertake() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([
            .california: 25,
            .newYork: 20,
        ], in: 2025)
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let current = [item(.newYork, 30), item(.california, 25)]

        model.prepare(for: 2025)
        let reconciliation = target(current, year: 2025)
        model.updateReconciliationTarget(reconciliation)

        #expect(model.year == 2025)
        #expect(model.presented(current) == [item(.newYork, 20), item(.california, 25)])
        #expect(!model.willOvertake(reconciliation))
        #expect(model.feedbackTrigger == 0)
    }

    @Test func latestPendingReportCanSupersedeAnEarlierOneBeforeReconciliation() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([
            .california: 100,
            .newYork: 99,
        ], in: 2026)
        let model = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let baseline = [item(.california, 100), item(.newYork, 99)]
        model.updateReconciliationTarget(target(baseline))

        let firstPending = [item(.newYork, 101), item(.california, 100)]
        let latestPending = [item(.newYork, 102), item(.california, 100)]
        let firstReconciliation = target(firstPending)
        let latestReconciliation = target(latestPending)

        model.updateReconciliationTarget(firstReconciliation)
        #expect(model.presented(firstPending) == baseline)
        model.updateReconciliationTarget(latestReconciliation)
        #expect(model.presented(latestPending) == baseline)
        #expect(model.reconcile(firstReconciliation) == nil)
        model.reconcile(latestReconciliation)

        #expect(model.presented(latestPending) == latestPending)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026)?[.newYork] == 102)
    }
}
