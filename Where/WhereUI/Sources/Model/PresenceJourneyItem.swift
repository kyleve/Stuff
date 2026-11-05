import Foundation
import RegionKit
import WhereCore

/// Recorded stays split at interior visit starts and flight departures, interleaved with flights.
/// Splitting changes presentation only: each region-day remains in exactly one segment.
enum PresenceJourneyItem: Identifiable, Hashable {
    enum ID: Hashable {
        case stay(RegionStint.ID)
        case flight(FlightAssessment.ID)
    }

    case stay(RegionStint)
    case flight(FlightAssessment)

    var id: ID {
        switch self {
            case let .stay(stint): .stay(stint.id)
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
        let boundaries = Set(stints.map(\.start))
            .union(flights.map { flightDay($0, year: year, calendar: calendar) })
            .sorted()
        var result: [Self] = []
        for stint in stints {
            var start = stint.start
            // A shorter visit interrupts a longer stay at its first day. Shared
            // endpoint days stay intact so departures remain before flight rows.
            for boundary in boundaries where boundary > stint.start && boundary < stint.end {
                result.append(.stay(RegionStint(
                    region: stint.region,
                    start: start,
                    end: boundary.adding(days: -1),
                )))
                start = boundary
            }
            result.append(.stay(RegionStint(region: stint.region, start: start, end: stint.end)))
        }
        result += flights.map(Self.flight)
        return result.sorted { lhs, rhs in
            let left = lhs.sortDay(calendar: calendar, year: year)
            let right = rhs.sortDay(calendar: calendar, year: year)
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

    private func sortDay(calendar: Calendar, year: Int) -> CalendarDay {
        switch self {
            case let .stay(stint): stint.start
            case let .flight(flight): Self.flightDay(flight, year: year, calendar: calendar)
        }
    }

    private static func flightDay(
        _ flight: FlightAssessment,
        year: Int,
        calendar: Calendar,
    ) -> CalendarDay {
        // `items` admits only completed flights with supported dates in this year.
        guard let day = flight.completedDays(in: calendar).filter({ $0.year == year }).min() else {
            preconditionFailure("A timeline flight must have a completed day in the selected year")
        }
        return day
    }
}
