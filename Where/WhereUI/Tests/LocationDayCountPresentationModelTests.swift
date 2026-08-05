import RegionKit
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct LocationDayCountPresentationModelTests {
    private func preferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    private func item(_ region: Region, _ days: Int) -> RegionDays {
        RegionDays(region: region, days: days)
    }

    @Test func firstRevealEstablishesBaselineSilently() {
        let preferences = preferences()
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)
        let current = [item(.california, 148), item(.newYork, 37)]

        #expect(model.presented(current[0]).days == 148)
        model.reconcile(current, in: 2026, isVisible: true)

        #expect(model.feedbackTrigger == 0)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [
            .california: 148,
            .newYork: 37,
        ])
    }

    @Test func increasedCountRevealsFromSavedValueAndTriggersOnce() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([.california: 148], in: 2026)
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)
        let current = item(.california, 149)

        #expect(model.presented(current).days == 148)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [.california: 148])

        model.reconcile([current], in: 2026, isVisible: true)

        #expect(model.presented(current).days == 149)
        #expect(model.feedbackTrigger == 1)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [.california: 149])

        model.reconcile([current], in: 2026, isVisible: true)

        #expect(model.feedbackTrigger == 1)
    }

    @Test func decreasedCountRevealsWithoutFeedback() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([.california: 148], in: 2026)
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)
        let current = item(.california, 147)

        #expect(model.presented(current).days == 148)

        model.reconcile([current], in: 2026, isVisible: true)

        #expect(model.presented(current).days == 147)
        #expect(model.feedbackTrigger == 0)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [.california: 147])
    }

    @Test func multipleChangedCardsProduceOneFeedbackEvent() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([
            .california: 148,
            .newYork: 37,
        ], in: 2026)
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)

        model.reconcile([
            item(.california, 149),
            item(.newYork, 38),
        ], in: 2026, isVisible: true)

        #expect(model.feedbackTrigger == 1)
    }

    @Test func unchangedAndNewCardsStaySilent() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([.california: 148], in: 2026)
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)
        let current = [item(.california, 148), item(.newYork, 12)]

        #expect(model.presented(current[1]).days == 12)
        model.reconcile(current, in: 2026, isVisible: true)

        #expect(model.feedbackTrigger == 0)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [
            .california: 148,
            .newYork: 12,
        ])
    }

    @Test func hiddenReconciliationLeavesCurrentCountsPending() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([.california: 148], in: 2026)
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)
        let current = item(.california, 151)

        model.reconcile([current], in: 2026, isVisible: false)

        #expect(model.presented(current).days == 148)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [.california: 148])
        #expect(model.feedbackTrigger == 0)

        model.reconcile([current], in: 2026, isVisible: true)

        #expect(model.presented(current).days == 151)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == [.california: 151])
    }

    @Test func preparingAnotherYearUsesOnlyThatYearsBaseline() {
        let preferences = preferences()
        preferences.setLastSeenLocationDayCounts([.california: 25], in: 2025)
        preferences.setLastSeenLocationDayCounts([.california: 148], in: 2026)
        let model = LocationDayCountPresentationModel(preferences: preferences, year: 2026)

        model.prepare(for: 2025)

        #expect(model.year == 2025)
        #expect(model.presented(item(.california, 30)).days == 25)
        #expect(model.feedbackTrigger == 0)
    }
}
