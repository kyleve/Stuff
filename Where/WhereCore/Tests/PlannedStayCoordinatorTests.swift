import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct PlannedStayCoordinatorTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let now = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 1, hour: 12),
    )!

    private static func makeCoordinator(
        store: SwiftDataStore,
        now: Date = Self.now,
    ) -> PlannedStayCoordinator {
        PlannedStayCoordinator(store: store, calendar: calendar, now: { now })
    }

    @Test func setAndClearRoundTripThroughTheStore() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.makeCoordinator(store: store)
        let through = CalendarDay(year: 2026, month: 7, day: 10)

        try await coordinator.set(region: .newYork, through: through)
        #expect(try await coordinator.active() == PlannedStay(region: .newYork, through: through))

        try await coordinator.clear()
        #expect(try await coordinator.active() == nil)
        let records = try await store.plannedStayRecords()
        #expect(records.count == 1)
        #expect(records.first?.value == nil)
    }

    @Test func expiredStayWritesATombstoneEvenBeforeForecastEligibility() async throws {
        let store = try SwiftDataStore.inMemory()
        let march = try #require(Self.calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 1, hour: 12),
        ))
        let coordinator = Self.makeCoordinator(store: store, now: march)
        try await coordinator.set(
            region: .newYork,
            through: CalendarDay(year: 2026, month: 2, day: 28),
        )

        #expect(try await coordinator.active() == nil)
        #expect(try await store.plannedStayRecords().first?.value == nil)
    }

    @Test func newestSyncedRevisionWinsDeterministically() async throws {
        let store = try SwiftDataStore.inMemory()
        let older = try PlannedStayRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            value: PlannedStay(
                region: .california,
                through: CalendarDay(year: 2026, month: 8, day: 1),
            ),
            updatedAt: Self.now.addingTimeInterval(-1),
        )
        let newer = try PlannedStayRecord(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            value: PlannedStay(
                region: .newYork,
                through: CalendarDay(year: 2026, month: 9, day: 1),
            ),
            updatedAt: Self.now,
        )
        try await store.perform {
            try await store.restorePlannedStayRecord(newer)
            try await store.restorePlannedStayRecord(older)
        }

        let coordinator = Self.makeCoordinator(store: store)
        #expect(try await coordinator.active() == newer.value)
    }
}
