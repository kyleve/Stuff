import Foundation
import Testing
@testable import WhereCore

struct VersionedHistoryIndexTests {
    @Test func everyHeaderIsAdmittedBeforeAnyEnvelopeBody() throws {
        let bytes = [
            Data(#"{"semantics":{"major":1,"minor":0,"patch":0}}"#.utf8),
            Data(#"{"semantics":{"major":2,"minor":0,"patch":0},"payload":"opaque"}"#.utf8),
        ]
        for order in [bytes, bytes.reversed()] {
            let index = try VersionedHistoryIndex(envelopes: Array(order))
            #expect(index.recordMajors == [1, 2])
            #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
                try index.records(in: .initial, policy: RecordingBackupTestSupport.policy)
            }
        }
    }

    @Test func immutableDuplicatesCoalesceAndGenerationRebindingRemainsDistinct() throws {
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let record = try VersionedLocationSample.encode(sample, generationID: .initial)
        let rebound = record.inGeneration(.init(rawValue: UUID()))
        let encoder = JSONEncoder()
        let index = try VersionedHistoryIndex(envelopes: [record, record, rebound]
            .map(encoder.encode))
        let policy = RecordingBackupTestSupport.policy
        #expect(try Set(index.records(in: .initial, policy: policy)) == [record])
        #expect(try index.record(
            with: record.id,
            generationID: record.dataGenerationID,
            policy: policy,
        ) == record)
        #expect(try index.record(
            with: rebound.id,
            generationID: rebound.dataGenerationID,
            policy: policy,
        ) == rebound)
        #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 1)) {
            try index.records(in: .initial, policy: .foundation)
        }
    }

    @Test func conflictingBodiesCannotBeHiddenByTheIndex() throws {
        let records = try [
            RecordingControlCodec.encode(
                .source(RecordingAssessmentTestSupport.decision(1)),
                generationID: .initial,
            ),
            RecordingControlCodec.encode(
                .source(RecordingAssessmentTestSupport.decision(1, action: .automatic)),
                generationID: .initial,
            ),
        ]
        for order in [records, records.reversed()] {
            let index = try VersionedHistoryIndex(envelopes: order.map(JSONEncoder().encode))
            #expect(throws: DataCompatibilityError.conflictingRecord) {
                try index.records(in: .initial, policy: RecordingBackupTestSupport.policy)
            }
        }
    }
}
