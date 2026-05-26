import Foundation
import Testing
import WhereCore

struct InMemoryStoreTests {
    @Test func roundTripsSamples() async throws {
        let store = InMemoryStore()
        let sample = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        )
        try await store.addSample(sample)
        let all = try await store.allSamples()
        #expect(all == [sample])
    }

    @Test func samplesAreFilteredByInterval() async throws {
        let store = InMemoryStore()
        let early = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_000_000_000),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        )
        let middle = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_500_000_000),
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            horizontalAccuracy: 0,
            source: .manual,
        )
        let late = LocationSample(
            timestamp: Date(timeIntervalSince1970: 2_000_000_000),
            coordinate: Coordinate(latitude: 48.8566, longitude: 2.3522),
            horizontalAccuracy: 0,
            source: .manual,
        )
        try await store.addSample(late)
        try await store.addSample(early)
        try await store.addSample(middle)

        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_400_000_000),
            end: Date(timeIntervalSince1970: 1_900_000_000),
        )
        let result = try await store.samples(in: interval)
        #expect(result == [middle])
    }

    @Test func evidenceRoundTripsWithBlob() async throws {
        let store = InMemoryStore()
        let evidence = Evidence(
            kind: .boardingPass,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            region: .newYork,
            note: "JFK → SFO",
        )
        let blob = Data("PDF bytes".utf8)
        try await store.addEvidence(evidence, blob: blob)

        let fetched = try await store.evidence(
            in: DateInterval(
                start: Date(timeIntervalSince1970: 1_600_000_000),
                end: Date(timeIntervalSince1970: 1_800_000_000),
            ),
        )
        #expect(fetched == [evidence])

        let fetchedBlob = try await store.evidenceBlob(for: evidence.id)
        #expect(fetchedBlob == blob)
    }

    @Test func manualDayReplacesByDate() async throws {
        let store = InMemoryStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.setManualDay(DayPresence(date: date, regions: [.california]))
        try await store.setManualDay(DayPresence(date: date, regions: [.newYork]))

        let result = try await store.manualDays(
            in: DateInterval(
                start: date.addingTimeInterval(-86400),
                end: date.addingTimeInterval(86400),
            ),
        )
        #expect(result.count == 1)
        #expect(result.first?.regions == [.newYork])
    }

    @Test func clearWipesIntervalAcrossAllTables() async throws {
        let store = InMemoryStore()
        let inside = Date(timeIntervalSince1970: 1_700_000_000)
        let outside = Date(timeIntervalSince1970: 2_000_000_000)

        try await store.addSample(LocationSample(
            timestamp: inside,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await store.addSample(LocationSample(
            timestamp: outside,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        try await store.addEvidence(
            Evidence(kind: .other, capturedAt: inside),
            blob: nil,
        )
        try await store.setManualDay(DayPresence(date: inside, regions: [.california]))

        try await store.clear(
            in: DateInterval(
                start: inside.addingTimeInterval(-3600),
                end: inside.addingTimeInterval(3600),
            ),
        )

        let allSamples = try await store.allSamples()
        #expect(allSamples.count == 1)
        #expect(allSamples.first?.timestamp == outside)

        let allEvidence = try await store.evidence(
            in: DateInterval(start: .distantPast, end: .distantFuture),
        )
        #expect(allEvidence.isEmpty)

        let allManuals = try await store.manualDays(
            in: DateInterval(start: .distantPast, end: .distantFuture),
        )
        #expect(allManuals.isEmpty)
    }
}
