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

    private static func services(
        store: any WhereStore,
        locationSource: any LocationSource = ScriptedLocationSource(),
    ) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: locationSource,
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

    @Test func currentLocationCheckPublishesAcceptedStatus() async throws {
        let source = ScriptedLocationSource()
        source.setNextRequestedLocation(Self.sample(
            at: Coordinate(latitude: 40.7128, longitude: -74.0060),
        ))
        let model = try LocationForecastModel(
            services: Self.services(
                store: SwiftDataStore.inMemory(),
                locationSource: source,
            ),
            calendar: Self.calendar,
            now: { Self.now },
        )

        await model.checkCurrentLocation(for: .newYork, driftThreshold: .km1)

        #expect(model.plannedStayLocationCheck == .init(
            region: .newYork,
            driftThreshold: .km1,
            status: .accepted,
        ))
    }

    @Test func currentLocationCheckPublishesOutsideStatus() async throws {
        let source = ScriptedLocationSource()
        source.setNextRequestedLocation(Self.sample(
            at: Coordinate(latitude: 35.6762, longitude: 139.6503),
        ))
        let model = try LocationForecastModel(
            services: Self.services(
                store: SwiftDataStore.inMemory(),
                locationSource: source,
            ),
            calendar: Self.calendar,
            now: { Self.now },
        )

        await model.checkCurrentLocation(for: .newYork, driftThreshold: .km50)

        #expect(model.plannedStayLocationCheck?.status == .outside)
    }

    @Test func currentLocationCheckPublishesUnavailableStatus() async throws {
        let model = try LocationForecastModel(
            services: Self.services(store: SwiftDataStore.inMemory()),
            calendar: Self.calendar,
            now: { Self.now },
        )

        await model.checkCurrentLocation(for: .newYork, driftThreshold: .km1)

        #expect(model.plannedStayLocationCheck?.status == .unavailable)
    }

    @Test func cancelledCurrentLocationCheckDoesNotPublishLateResult() async throws {
        let source = GatedCurrentLocationSource()
        let model = try LocationForecastModel(
            services: Self.services(
                store: SwiftDataStore.inMemory(),
                locationSource: source,
            ),
            calendar: Self.calendar,
            now: { Self.now },
        )
        let task = Task {
            await model.checkCurrentLocation(for: .newYork, driftThreshold: .km1)
        }
        await source.waitUntilRequestCount(1)

        task.cancel()
        await source.resolveRequest(
            at: 0,
            with: Self.sample(at: Coordinate(latitude: 40.7128, longitude: -74.0060)),
        )
        await task.value

        #expect(model.plannedStayLocationCheck?.status == .checking)
    }

    @Test func supersededCurrentLocationCheckDoesNotOverwriteNewerResult() async throws {
        let source = GatedCurrentLocationSource()
        let model = try LocationForecastModel(
            services: Self.services(
                store: SwiftDataStore.inMemory(),
                locationSource: source,
            ),
            calendar: Self.calendar,
            now: { Self.now },
        )
        let first = Task {
            await model.checkCurrentLocation(for: .newYork, driftThreshold: .km1)
        }
        await source.waitUntilRequestCount(1)
        let second = Task {
            await model.checkCurrentLocation(for: .california, driftThreshold: .km5)
        }
        await source.waitUntilRequestCount(2)

        await source.resolveRequest(
            at: 1,
            with: Self.sample(at: Coordinate(latitude: 37.7749, longitude: -122.4194)),
        )
        await second.value
        await source.resolveRequest(
            at: 0,
            with: Self.sample(at: Coordinate(latitude: 40.7128, longitude: -74.0060)),
        )
        await first.value

        #expect(model.plannedStayLocationCheck == .init(
            region: .california,
            driftThreshold: .km5,
            status: .accepted,
        ))
    }

    private static func sample(at coordinate: Coordinate) -> LocationSample {
        LocationSample(
            timestamp: now,
            coordinate: coordinate,
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }
}
