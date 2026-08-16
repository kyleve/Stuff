import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct LocationForecastModelTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static let now = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 15, hour: 12),
    )!

    private static func services(store: any WhereStore) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
    }

    private static func report() -> YearReport {
        YearReport(
            year: 2026,
            days: [DayPresence(date: now, in: calendar, regions: [.newYork])],
            totals: [
                .other: 150,
                .california: 100,
                .newYork: 90,
                .canada: 80,
                .europeanUnion: 70,
            ],
        )
    }

    @Test func leadingForecastsExcludeElsewhereWithoutChangingPrimaryCards() throws {
        let services = try Self.services(store: SwiftDataStore.inMemory())
        let model = LocationForecastModel(
            services: services,
            calendar: Self.calendar,
            now: { Self.now },
        )
        let report = Self.report()

        #expect(model.leadingForecasts(report: report).map(\.region) == [
            .california,
            .newYork,
            .canada,
        ])
        #expect(RegionRanking(report: report).primary.count == RegionRanking.primaryCount)
    }

    @Test func onlyARegionRecordedTodayCanEditAStay() throws {
        let model = try LocationForecastModel(
            services: Self.services(store: SwiftDataStore.inMemory()),
            calendar: Self.calendar,
            now: { Self.now },
        )

        #expect(model.isCurrent(.newYork, report: Self.report()))
        #expect(model.isCurrent(.california, report: Self.report()) == false)
    }

    @Test func saveAndClearUpdateTheObservableValueImmediately() async throws {
        let model = try LocationForecastModel(
            services: Self.services(store: SwiftDataStore.inMemory()),
            calendar: Self.calendar,
            now: { Self.now },
        )
        let through = try #require(Self.calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1),
        ))

        try await model.set(region: .newYork, through: through)
        #expect(model.activePlannedStay == PlannedStay(
            region: .newYork,
            through: CalendarDay(year: 2026, month: 8, day: 1),
        ))

        try await model.clear()
        #expect(model.activePlannedStay == nil)
    }

    @Test func plannedRegionCoversTomorrowThroughTheSelectedDay() async throws {
        let model = try LocationForecastModel(
            services: Self.services(store: SwiftDataStore.inMemory()),
            calendar: Self.calendar,
            now: { Self.now },
        )
        let through = CalendarDay(year: 2026, month: 7, day: 18)
        try await model.set(region: .newYork, through: through.startOfDay(in: Self.calendar))

        #expect(model.plannedRegion(on: CalendarDay(year: 2026, month: 7, day: 15)) == nil)
        #expect(model.plannedRegion(on: CalendarDay(year: 2026, month: 7, day: 16)) == .newYork)
        #expect(model.plannedRegion(on: through) == .newYork)
        #expect(model.plannedRegion(on: CalendarDay(year: 2026, month: 7, day: 19)) == nil)
    }

    @Test func crossYearStayIntersectsTheRestOfTheCurrentYear() async throws {
        let model = try LocationForecastModel(
            services: Self.services(store: SwiftDataStore.inMemory()),
            calendar: Self.calendar,
            now: { Self.now },
        )
        let stay = PlannedStay(
            region: .newYork,
            through: CalendarDay(year: 2027, month: 2, day: 1),
        )
        try await model.set(
            region: stay.region,
            through: stay.through.startOfDay(in: Self.calendar),
        )

        #expect(model.plannedStay(intersecting: 2026) == stay)
        #expect(model.plannedStay(intersecting: 2025) == nil)
        #expect(model.plannedInterval(intersecting: 2026) == .init(
            region: .newYork,
            start: CalendarDay(year: 2026, month: 7, day: 16),
            end: CalendarDay(year: 2026, month: 12, day: 31),
        ))
        #expect(model.plannedInterval(intersecting: 2026)?.dayCount == 169)
    }

    @Test func failedSaveKeepsTheLastGoodValue() async throws {
        let store = try TestStore()
        await store.failPlannedStays()
        let model = LocationForecastModel(
            services: Self.services(store: store),
            calendar: Self.calendar,
            now: { Self.now },
        )

        await #expect(throws: PlannedStaySaveFailure.self) {
            try await model.set(region: .newYork, through: Self.now)
        }
        #expect(model.activePlannedStay == nil)
    }
}
