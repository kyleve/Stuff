import Foundation
import RegionKit
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Deterministic production-shaped fixtures shared by the planning model tests.
@MainActor
enum PlanningTestSupport {
    static let today = CalendarDay(year: 2026, month: 9, day: 13)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static var now: Date {
        today.startOfDay(in: calendar)
    }

    static func report(store: any WhereStore) -> YearReportModel {
        let referenceDate = now
        return YearReportModel(
            services: WhereServices(
                store: store,
                locationSource: ScriptedLocationSource(),
                now: { referenceDate },
            ),
            selectedYear: today.year,
            preferences: makePreferences(),
            now: { referenceDate },
        )
    }

    static func stay(
        region: Region,
        from arrival: CalendarDay,
        through departure: CalendarDay,
    ) throws -> PlannedStay {
        try PlannedStay(
            id: PlannedStay.ID(rawValue: UUID()),
            region: region,
            arrival: .init(exact: arrival),
            departure: .init(exact: departure),
        )
    }
}
