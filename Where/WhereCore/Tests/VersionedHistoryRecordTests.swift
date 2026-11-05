import Foundation
import Testing
@testable import WhereCore

struct VersionedHistoryRecordTests {
    @Test func intervalScopeKeepsAnOngoingBoundaryAndClipsUnknownMeaningToTheQuery() throws {
        let time = RecordingAssessmentTestSupport.time
        let interval = try RecordingInterval(start: time(50), end: nil)
        let scope = VersionedHistoryRecord.Scope.intervals([interval])
        try scope.validate()
        #expect(!scope.contains(time(49)))
        #expect(scope.contains(time(1e8)))
        #expect(try scope.intersections(with: RecordingAssessmentTestSupport.period(0, 100)) == [
            RecordingAssessmentTestSupport.period(50, 100),
        ])
        let finite = try VersionedHistoryRecord.Scope
            .periods([RecordingAssessmentTestSupport.period(
                0,
                50,
            )])
        #expect(!finite.overlaps(interval))
        #expect(try finite.overlaps(.init(start: time(49), end: nil)))
        #expect(try RecordingControlsTestSupport.roundTrip(scope) == scope)
    }

    @Test func futurePayloadShapeCannotBeDecodedBeforeItsHeader() throws {
        let wire = Data(
            #"{"semantics":{"major":2,"minor":0,"patch":0},"payload":{"future":"shape"}}"#
                .utf8,
        )
        #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
            try VersionedHistoryRecord.admit(wire, policy: DataCompatibilityTestSupport.policy)
        }
    }

    @Test func opaqueEnvelopePreservesIdentityAndBytes() throws {
        let value = VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 2, patch: 3),
            scope: .entireHistory,
            kind: "test",
            payload: Data([0, 255, 100]),
        )
        #expect(try VersionedHistoryRecord.admit(
            JSONEncoder().encode(value),
            policy: DataCompatibilityTestSupport.policy,
        ) == value)
    }
}
