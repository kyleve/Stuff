import Foundation
import Testing
@testable import WhereCore

struct YearReportTests {
    @Test func yearReport_sortsDaysAscending() {
        let later = DayPresence(
            date: Date(timeIntervalSince1970: 2_000_000_000),
            regions: [.newYork],
        )
        let earlier = DayPresence(
            date: Date(timeIntervalSince1970: 1_000_000_000),
            regions: [.california],
        )
        let report = YearReport(year: 2026, days: [later, earlier], totals: [:])
        #expect(report.days.first?.date == earlier.date)
        #expect(report.days.last?.date == later.date)
    }
}

struct StorageDefaultTests {
    @Test func storageDefault_isInMemoryUnderTestRunner() {
        // We're running under either XCTest or Swift Testing via
        // `tuist test` / `xcodebuild test` / `swift test`, all of
        // which set `XCTestConfigurationFilePath`. If this assertion
        // ever fails, `Storage.default` would let a real test build
        // write to the user's local SwiftData store — bad.
        #expect(SwiftDataStore.Storage.default == .inMemory)
    }

    @Test func make_inMemory_roundTripsASample() async throws {
        let store = try SwiftDataStore.make(storage: .inMemory)
        let sample = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 10,
            source: .manual,
        )
        try await store.perform { try await store.add(sample: sample) }

        let stored = try await store.allSamples()
        #expect(stored.map(\.id) == [sample.id])
    }
}

struct SDLocationSampleTests {
    @Test func missingSourceRawReturnsNil() {
        let record = SDLocationSample(value: LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        record.sourceRaw = nil
        #expect(record.toValue() == nil)
    }

    @Test func corruptSourceRawReturnsNil() {
        let record = SDLocationSample(value: LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .manual,
        ))
        record.sourceRaw = "not-a-real-source"
        #expect(record.toValue() == nil)
    }
}

struct RegionTests {
    @Test func localizedName_returnsEnglishStringForEachCase() {
        #expect(Region.california.localizedName == "California")
        #expect(Region.newYork.localizedName == "New York")
        #expect(Region.canada.localizedName == "Canada")
        #expect(Region.europeanUnion.localizedName == "European Union")
        #expect(Region.other.localizedName == "Other")
    }
}

struct EvidenceKindTests {
    @Test func otherWithLabel_roundTripsThroughCodable() throws {
        let original = EvidenceKind.other("ferry ticket")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvidenceKind.self, from: data)
        #expect(decoded == original)
    }

    @Test func otherWithNilLabel_roundTripsThroughCodable() throws {
        let original = EvidenceKind.other(nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvidenceKind.self, from: data)
        #expect(decoded == original)
    }

    @Test func planeTicket_roundTripsThroughCodable() throws {
        let original = EvidenceKind.planeTicket
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvidenceKind.self, from: data)
        #expect(decoded == original)
    }

    @Test func unknownDiscriminator_throws() {
        // Synthesized `Codable` for enums-with-associated-values uses
        // the case name as the outer key; an unknown key fails to
        // match any case and decodes as a `DecodingError`.
        let json = Data(#"{"madeUp":{}}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(EvidenceKind.self, from: json)
        }
    }

    @Test func knownCases_listsEveryFamilyOnce() {
        let discriminators = EvidenceKind.knownCases.map(\.discriminator)
        let expected = [
            "planeTicket",
            "boardingPass",
            "hotelReceipt",
            "carRental",
            "rideshare",
            "photo",
            "document",
            "other",
        ]
        #expect(discriminators == expected)
    }
}

struct SampleSourceTests {
    @Test func evidenceImplied_roundTripsThroughCodable() throws {
        let evidenceId = UUID()
        let original = SampleSource.evidenceImplied(id: evidenceId, kind: .boardingPass)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SampleSource.self, from: data)
        #expect(decoded == original)
    }

    @Test func evidenceImplied_carriesIdAndKindAccessors() {
        let evidenceId = UUID()
        let source = SampleSource.evidenceImplied(id: evidenceId, kind: .photo)
        #expect(source.evidenceId == evidenceId)
        #expect(source.evidenceKind == .photo)
    }

    @Test func manualSource_dropsEvidenceFieldsInEncoding() throws {
        // Synthesized `Codable` only emits associated values for the
        // matching case, so a plain `.manual` encodes without an
        // `id`/`kind` payload anywhere in the JSON.
        let original = SampleSource.manual
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SampleSource.self, from: data)
        #expect(decoded == .manual)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"id\""))
        #expect(!json.contains("\"kind\""))
    }

    @Test func evidenceImpliedDecoding_missingFields_throws() {
        // Empty `evidenceImplied` payload omits required `id` and
        // `kind` keys, which the synthesized decoder rejects with a
        // `DecodingError.keyNotFound`.
        let json = Data(#"{"evidenceImplied":{}}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SampleSource.self, from: json)
        }
    }
}
