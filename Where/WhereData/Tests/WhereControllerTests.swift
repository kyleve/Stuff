import Foundation
import Testing
import WhereCore
import WhereData

struct WhereControllerTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private static func makeAggregator() -> DayAggregator {
        DayAggregator(calendar: Calendar(identifier: .gregorian), timeZone: pacific)
    }

    private static func makeController() -> (WhereController, InMemoryStore, ScriptedLocationSource) {
        let store = InMemoryStore()
        let source = ScriptedLocationSource()
        let controller = WhereController(
            store: store,
            locationSource: source,
            aggregator: makeAggregator(),
        )
        return (controller, store, source)
    }

    @Test func ingestStoresSamplesAndReportsThem() async throws {
        let (controller, _, _) = Self.makeController()
        let sf = LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            source: .manual,
        )
        try await controller.ingest(sf)

        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.count == 1)
        #expect(report.days.first?.regions == [.california])
        #expect(report.totals == [.california: 1])
    }

    @Test func manualDayUnionsWithSamples() async throws {
        let (controller, _, _) = Self.makeController()
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-07-04T10:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            source: .manual,
        ))
        try await controller.addManualDay(
            date: iso("2026-07-04T15:00:00-07:00"),
            regions: [.newYork],
        )

        let report = try await controller.yearReport(for: 2026)
        let july4 = report.days.first { day in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
            let components = cal.dateComponents([.month, .day], from: day.date)
            return components.month == 7 && components.day == 4
        }
        #expect(july4?.regions == [.california, .newYork])
    }

    @Test func clearYearWipesAndReportsEmpty() async throws {
        let (controller, _, _) = Self.makeController()
        try await controller.ingest(LocationSample(
            timestamp: iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            source: .manual,
        ))
        try await controller.clearYear(2026)
        let report = try await controller.yearReport(for: 2026)
        #expect(report.days.isEmpty)
        #expect(report.totals.isEmpty)
    }

    @Test func evidenceRoundTripsViaController() async throws {
        let (controller, _, _) = Self.makeController()
        let evidence = Evidence(
            kind: .planeTicket,
            capturedAt: iso("2026-04-10T08:00:00-07:00"),
            region: .california,
            note: "SFO → JFK",
        )
        let blob = Data("ticket pdf".utf8)
        try await controller.addEvidence(evidence, blob: blob)

        let fetched = try await controller.evidence(for: 2026)
        #expect(fetched == [evidence])

        let fetchedBlob = try await controller.evidenceBlob(for: evidence.id)
        #expect(fetchedBlob == blob)
    }
}

private func iso(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: string) ?? Date(timeIntervalSince1970: 0)
}
