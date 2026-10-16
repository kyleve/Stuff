import Foundation
import RegionKit
import WhereCore

/// Recorded stays split at flight departure days, interleaved with historical flights.
/// Splitting changes presentation only: each region-day remains in exactly one segment.
enum PresenceJourneyItem: Identifiable, Hashable {
    enum ID: Hashable {
        case stay(region: Region, start: Date)
        case flight(FlightAssessment.ID)
    }

    case stay(RegionStint)
    case flight(FlightAssessment)

    var id: ID {
        switch self {
            case let .stay(stint): .stay(region: stint.region, start: stint.start)
            case let .flight(flight): .flight(flight.id)
        }
    }

    static func items(
        stints: [RegionStint],
        flights: [FlightAssessment],
        year: Int,
        calendar: Calendar,
    ) -> [Self] {
        var seen: Set<FlightAssessment.ID> = []
        let flights = flights.filter {
            !$0.isPending && $0.completedDays(in: calendar).contains { $0.year == year }
                && seen.insert($0.id).inserted
        }.sorted(by: flightOrder)
        let yearStart = CalendarDay(year: year, month: 1, day: 1).startOfDay(in: calendar)
        let boundaries = Set(flights.map { max(yearStart, calendar.startOfDay(for: $0.startedAt)) })
            .sorted()
        var result: [Self] = []
        for stint in stints {
            var start = stint.start
            for boundary in boundaries where boundary > stint.start && boundary <= stint.end {
                guard let end = calendar.date(byAdding: .day, value: -1, to: boundary) else {
                    preconditionFailure("Calendar cannot find the day before a flight")
                }
                result.append(.stay(segment(stint, start: start, end: end, calendar: calendar)))
                start = boundary
            }
            result.append(.stay(segment(stint, start: start, end: stint.end, calendar: calendar)))
        }
        result += flights.map(Self.flight)
        return result.sorted { lhs, rhs in
            let left = lhs.sortDay(calendar: calendar, yearStart: yearStart)
            let right = rhs.sortDay(calendar: calendar, yearStart: yearStart)
            if left != right { return left < right }
            switch (lhs, rhs) {
                case let (.flight(a), .flight(b)): return flightOrder(a, b)
                case (.flight, .stay): return true
                case (.stay, .flight): return false
                case let (.stay(a), .stay(b)):
                    if a.end != b.end { return a.end < b.end }
                    return Region.declarationOrder[a.region, default: 0]
                        < Region.declarationOrder[b.region, default: 0]
            }
        }
    }

    private static func flightOrder(_ lhs: FlightAssessment, _ rhs: FlightAssessment) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        if lhs.id.departureSampleID != rhs.id.departureSampleID {
            return lhs.id.departureSampleID.uuidString < rhs.id.departureSampleID.uuidString
        }
        switch (lhs.id.recordingSource, rhs.id.recordingSource) {
            case (.legacy, .legacy): return false
            case (.legacy, .device): return true
            case (.device, .legacy): return false
            case let (.device(a), .device(b)): return a.rawValue.uuidString < b.rawValue.uuidString
        }
    }

    private func sortDay(calendar: Calendar, yearStart: Date) -> Date {
        switch self {
            case let .stay(stint): stint.start
            case let .flight(flight): max(yearStart, calendar.startOfDay(for: flight.startedAt))
        }
    }

    private static func segment(
        _ stint: RegionStint,
        start: Date,
        end: Date,
        calendar: Calendar,
    ) -> RegionStint {
        RegionStint(
            region: stint.region,
            start: start,
            end: end,
            dayCount: CalendarDay(from: start, in: calendar)
                .days(through: CalendarDay(from: end, in: calendar)).count,
        )
    }
}
