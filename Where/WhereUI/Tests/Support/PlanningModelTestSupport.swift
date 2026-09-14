import Foundation
import RegionKit
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Hermetic services and an explicit clock for planning presentation tests.
enum PlanningModelTestSupport {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static let today = CalendarDay(year: 2026, month: 7, day: 15)
    static var now: Date {
        today.startOfDay(in: calendar)
    }

    @MainActor static func model(store: any WhereStore) -> LocationForecastModel {
        LocationForecastModel(services: services(store: store), calendar: calendar, now: { now })
    }

    static func services(store: any WhereStore) -> WhereServices {
        WhereServices(store: store, locationSource: ScriptedLocationSource(), now: { now })
    }

    static func stay(region: Region) throws -> PlannedStay {
        try PlannedStay(
            id: .init(rawValue: UUID()),
            region: region,
            arrival: .init(exact: today),
            departure: .init(exact: today.adding(days: 7)),
        )
    }
}
