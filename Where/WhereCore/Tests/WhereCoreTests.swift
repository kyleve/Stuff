import Foundation
import Testing
import WhereCore

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
        let json = Data(#"{"kind":"madeUp"}"#.utf8)
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
        let original = SampleSource.manual
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SampleSource.self, from: data)
        #expect(decoded == .manual)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("evidenceId"))
        #expect(!json.contains("evidenceKindRaw"))
    }

    @Test func evidenceImpliedDecoding_missingFields_throws() {
        let json = Data(#"{"source":"evidenceImplied"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SampleSource.self, from: json)
        }
    }
}
