import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Synthetic geography for the invented trajectory fixture. Real region polygons
/// play no part in these persistence and projection integration tests.
enum SampleCorrectionTestSupport {
    struct SparseLayoverRegions: RegionAttributing {
        let loadedRegions: [Region] = [.california, .newYork, .canada]

        func region(at coordinate: Coordinate) -> Region {
            let east = coordinate.longitude * 111.195
            if east < 0.5 { return .california }
            if abs(east - 150) < 0.5 { return .canada }
            if east >= 299.5 { return .newYork }
            return .other
        }

        func distanceToBoundary(of _: Region, from _: Coordinate) -> Double? {
            nil
        }
    }

    struct FlightRegions: RegionAttributing {
        let loadedRegions: [Region] = [.california, .newYork, .canada]

        func region(at coordinate: Coordinate) -> Region {
            let east = coordinate.longitude * 111.195
            let north = coordinate.latitude * 111.195
            if east < 0.5 { return .california }
            if (1440 ... 1455).contains(east), north > 0 { return .newYork }
            if east >= 1500 { return .canada }
            return .other
        }

        func distanceToBoundary(of _: Region, from _: Coordinate) -> Double? {
            nil
        }
    }

    static let attribution = FlightRegions()
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static var aggregator: DayAggregator {
        DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
    }

    struct Harness {
        let store: SwiftDataStore
        let services: WhereServices
        let widgets: WidgetDataReader

        var reader: ReportReader {
            services.reports
        }

        var coordinator: SampleCorrectionCoordinator {
            services.corrections
        }

        var day: CalendarDay {
            CalendarDay(from: FlightTrajectoryFixtures.start, in: calendar)
        }

        var interval: DateInterval {
            calendar.dateInterval(of: .day, for: FlightTrajectoryFixtures.start)!
        }

        func proposal() async throws -> SampleCorrectionProposal {
            let review = try await coordinator.review(
                id: .flightDay(day: day),
                year: day.year,
                primaryRegions: attribution.loadedRegions,
                driftThresholdMeters: 1000,
            )
            return try #require(review?.proposal)
        }
    }

    static func makeHarness(
        now: Date = FlightTrajectoryFixtures.date(minutes: 150),
    ) throws -> Harness {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: attribution,
            aggregator: aggregator,
            now: { now },
        )
        return Harness(
            store: store,
            services: services,
            widgets: WidgetDataReader(
                store: store,
                aggregator: aggregator,
                attributor: attribution,
            ),
        )
    }

    static func completedFlight() async throws -> Harness {
        let harness = try makeHarness()
        try await harness.store.perform {
            for sample in FlightTrajectoryFixtures.turningFlight().samples {
                try await harness.store.add(sample: sample)
            }
        }
        return harness
    }
}
