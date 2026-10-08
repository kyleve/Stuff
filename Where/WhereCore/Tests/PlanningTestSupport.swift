import Foundation
import RegionKit
@testable import WhereCore

/// Shared calendar and input builders for planning tests; every clock is fixed.
enum PlanningTestSupport {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func day(_ month: Int, _ day: Int, year: Int = 2026) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    static func date(_ day: CalendarDay) -> Date {
        day.startOfDay(in: calendar)
    }

    static func stay(
        region: Region,
        arrival: CalendarDay,
        latestArrival: CalendarDay? = nil,
        departure: CalendarDay,
        latestDeparture: CalendarDay? = nil,
        stayID: PlannedStay.ID = .init(rawValue: UUID()),
    ) throws -> PlannedStay {
        try PlannedStay(
            id: stayID,
            region: region,
            arrival: .init(earliest: arrival, latest: latestArrival ?? arrival),
            departure: .init(earliest: departure, latest: latestDeparture ?? departure),
        )
    }

    static func report(asOf today: CalendarDay, counts: [Region: Int]) -> YearReport {
        let first = CalendarDay.yearRange(today.year).lowerBound
        var byDay: [CalendarDay: Set<Region>] = [:]
        for (region, count) in counts {
            for offset in 0 ..< count {
                byDay[first.adding(days: offset), default: []].insert(region)
            }
        }
        return YearReport(
            year: today.year,
            days: byDay.map { DayPresence(day: $0.key, regions: $0.value) },
            totals: counts,
        )
    }
}
