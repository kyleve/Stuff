import Foundation
import RegionKit
import WhereCore
@testable import WhereUI

enum HistoryNavigationTestSupport {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func stint(
        from start: CalendarDay,
        through end: CalendarDay,
        region: Region = .california,
    ) -> RegionStint {
        RegionStint(
            region: region,
            start: start.startOfDay(in: calendar),
            end: end.startOfDay(in: calendar),
            dayCount: start.days(through: end).count,
        )
    }

    static func flight(from start: CalendarDay, through end: CalendarDay) -> FlightAssessment {
        let departure = start.startOfDay(in: calendar).addingTimeInterval(12 * 60 * 60)
        let arrival = end.startOfDay(in: calendar).addingTimeInterval(14 * 60 * 60)
        return FlightAssessment(
            id: .init(recordingSource: .legacy, departureSampleID: UUID()),
            startedAt: departure,
            lastObservationAt: arrival,
            lastFlightAt: arrival.addingTimeInterval(-60 * 60),
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 900,
            progress: .completed(arrivedAt: arrival),
            inferredEndpoints: [],
        )
    }
}
