import Foundation
import Testing
@testable import WhereCore

struct RecordingControlCodecTests {
    @Test func ongoingPlaceEnvelopeMustMatchItsCompleteUnboundedPayloadScope() throws {
        let place = try RecordingControlsTestSupport.place(1, end: nil)
        let record = try RecordingControlCodec.encode(.place(place), generationID: .initial)
        #expect(record.scope == .intervals(place.periods))
        #expect(try RecordingControlCodec.admit(
            record,
            policy: RecordingBackupTestSupport.policy,
        ) ==
            .understood(.place(place)))
        #expect(try RecordingControlCodec.encode(
            .place(RecordingControlsTestSupport.roundTrip(place)),
            generationID: .initial,
        ) == record)
        let narrowed = try VersionedHistoryRecord(
            id: record.id,
            dataGenerationID: record.dataGenerationID,
            semantics: record.semantics,
            scope: .intervals([RecordingInterval(RecordingAssessmentTestSupport.period(0, 100))]),
            kind: record.kind,
            payload: record.payload,
        )
        #expect(throws: DataCompatibilityError.conflictingRecord) {
            try RecordingControlCodec.admit(narrowed, policy: RecordingBackupTestSupport.policy)
        }
    }

    @Test func retryEncodingPreservesCanonicalBytesAcrossRestoration() throws {
        let initial = try RecordingAssessmentTestSupport.decision(1, predecessors: [
            RecordingAssessmentTestSupport.decisionID(5),
            RecordingAssessmentTestSupport.decisionID(2),
            RecordingAssessmentTestSupport.decisionID(4),
            RecordingAssessmentTestSupport.decisionID(3),
        ])
        let restored = try RecordingControlsTestSupport.roundTrip(initial)
        let record = try RecordingControlCodec.encode(.source(initial), generationID: .initial)
        #expect(try RecordingControlCodec
            .encode(.source(restored), generationID: .initial) == record)
        let object = try #require(JSONSerialization
            .jsonObject(with: record.payload) as? [String: Any])
        #expect(object["predecessorIDs"] as? [String] == (2 ... 5)
            .map { RecordingAssessmentTestSupport.decisionID($0).rawValue.uuidString })
        #expect(try RecordingControlCodec.admit(
            record,
            policy: DataCompatibilityTestSupport.policy,
        ) == .understood(.source(initial)))
    }

    @Test func mismatchedEnvelopeIdentityVersionOrScopeCannotChangeMeaning() throws {
        let value = try RecordingAssessmentTestSupport.decision(1)
        let record = try RecordingControlCodec.encode(.source(value), generationID: .initial)
        let variants = [
            VersionedHistoryRecord(
                id: .init(rawValue: UUID()),
                dataGenerationID: .initial,
                semantics: record.semantics,
                scope: record.scope,
                kind: record.kind,
                payload: record.payload,
            ),
            VersionedHistoryRecord(
                id: record.id,
                dataGenerationID: .initial,
                semantics: .init(major: 1, minor: 0, patch: 1),
                scope: record.scope,
                kind: record.kind,
                payload: record.payload,
            ),
            VersionedHistoryRecord(
                id: record.id,
                dataGenerationID: .initial,
                semantics: record.semantics,
                scope: .entireHistory,
                kind: record.kind,
                payload: record.payload,
            ),
        ]
        for variant in variants {
            #expect(throws: DataCompatibilityError.conflictingRecord) {
                try RecordingControlCodec.admit(
                    variant,
                    policy: DataCompatibilityTestSupport.policy,
                )
            }
        }
    }

    @Test func uncertainOlderMeaningRetainsOpaqueBytesAndItsAffectedScope() throws {
        let record = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 0, minor: 9, patch: 0),
            scope: .periods([RecordingAssessmentTestSupport
                    .period(
                        20,
                        30,
                    )]),
            kind: "recording.source",
            payload: Data([0, 255]),
        )
        #expect(try RecordingControlCodec.admit(
            record,
            policy: DataCompatibilityTestSupport.policy,
        ) == .requiresReview(record))
    }

    @Test func unknownCurrentKindRetainsReviewScopeAndUnsupportedMajorGatesBeforePayload() throws {
        let record = VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 0, patch: 0),
            scope: .entireHistory,
            kind: "unrecognized",
            payload: Data([255]),
        )
        #expect(try RecordingControlCodec.admit(
            record,
            policy: DataCompatibilityTestSupport.policy,
        ) == .requiresReview(record))
        #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 1)) {
            try RecordingControlCodec.admit(record, policy: .foundation)
        }
    }

    @Test func unsortedOrDuplicateWirePredecessorsFailAdmission() throws {
        let source = try RecordingAssessmentTestSupport.decision(1)
        let record = try RecordingControlCodec.encode(.source(source), generationID: .initial)
        for predecessorIDs in [[3, 2], [2, 2]] {
            var wire = try #require(JSONSerialization
                .jsonObject(with: record.payload) as? [String: Any])
            wire["predecessorIDs"] = predecessorIDs
                .map { RecordingAssessmentTestSupport.decisionID($0).rawValue.uuidString }
            let invalid = try VersionedHistoryRecord(
                id: record.id,
                dataGenerationID: record.dataGenerationID,
                semantics: record.semantics,
                scope: record.scope,
                kind: record.kind,
                payload: JSONSerialization.data(withJSONObject: wire),
            )
            #expect(throws: HistoryDecisionResolver.ValidationError
                .invalidPredecessors(source.id))
            {
                try RecordingControlCodec.admit(
                    invalid,
                    policy: DataCompatibilityTestSupport.policy,
                )
            }
        }
    }
}
