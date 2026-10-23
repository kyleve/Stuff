import Foundation
import Testing
import WhereCore

/// Shared assertions for complete recorded windows. Ground boundaries are reviewed
/// fixture identities, independent of the detector's selected travel intervals.
enum RecordedFlightAssertions {
    static func completedFlight(
        samples: [LocationSample],
        now: Date,
        travelDay: CalendarDay,
        lastDepartureGroundID: LocationSample.ID,
        firstArrivalGroundID: LocationSample.ID,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws -> FlightAssessment {
        let analyzer = FlightTrajectoryAnalyzer()
        let flights = analyzer.analyze(samples: samples, now: now)
        try #require(flights.count == 1, sourceLocation: sourceLocation)
        let flight = try #require(flights.first, sourceLocation: sourceLocation)
        let departure = try #require(
            samples.first { $0.id == lastDepartureGroundID },
            sourceLocation: sourceLocation,
        )
        let arrival = try #require(
            samples.first { $0.id == firstArrivalGroundID },
            sourceLocation: sourceLocation,
        )
        let protectedIDs = Set(samples.filter {
            $0.timestamp <= departure.timestamp || $0.timestamp >= arrival.timestamp
        }.map(\.id))
        let evidence = try #require(flight.progress.arrival, sourceLocation: sourceLocation)
        #expect(evidence.firstGroundAt >= arrival.timestamp, sourceLocation: sourceLocation)
        #expect(evidence.confirmedAt > evidence.firstGroundAt, sourceLocation: sourceLocation)
        #expect(
            samples.contains { $0.timestamp == evidence.firstGroundAt },
            sourceLocation: sourceLocation,
        )
        #expect(
            samples.contains { $0.timestamp == evidence.confirmedAt },
            sourceLocation: sourceLocation,
        )
        #expect(flight.groundSampleIDs.isEmpty == false, sourceLocation: sourceLocation)
        #expect(flight.groundSampleIDs.isSubset(of: protectedIDs), sourceLocation: sourceLocation)
        #expect(
            flight.airborneSampleIDs.isDisjoint(with: protectedIDs),
            sourceLocation: sourceLocation,
        )
        #expect(
            Set(flight.inferredEndpoints.map(\.sampleID)).isDisjoint(with: protectedIDs),
            sourceLocation: sourceLocation,
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(secondsFromGMT: 0),
            sourceLocation: sourceLocation,
        )
        #expect(flight.completedDays(in: calendar) == [travelDay], sourceLocation: sourceLocation)

        // Original callbacks can already share timestamps and positions. Reordering
        // and redelivering them must not change ownership or correction authority.
        #expect(
            analyzer.analyze(samples: Array(samples.reversed()) + samples, now: now) == flights,
            sourceLocation: sourceLocation,
        )
        let withoutArrival = samples.filter { $0.timestamp < arrival.timestamp }
        for withoutArrivalFlight in analyzer.analyze(samples: withoutArrival, now: now) {
            #expect(withoutArrivalFlight.isPending, sourceLocation: sourceLocation)
        }
        return flight
    }
}
