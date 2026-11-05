import Foundation
import Testing
@testable import WhereCore

struct VersionedLocationSampleTests {
    @Test func canonicalEnvelopeRetainsObservationIdentityAndEveryField() throws {
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let record = try VersionedLocationSample.encode(sample, generationID: .initial)
        #expect(record.id.rawValue == sample.id)
        #expect(record.semantics.major == 1)
        #expect(try VersionedLocationSample.decode(record) == sample)
        #expect(try VersionedLocationSample.encode(
            VersionedLocationSample.decode(record),
            generationID: .initial,
        ) == record)
        let mismatched = VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: record.semantics,
            scope: record.scope,
            kind: record.kind,
            payload: record.payload,
        )
        #expect(throws: DataCompatibilityError.conflictingRecord) {
            try VersionedLocationSample.decode(mismatched)
        }
    }
}
