import Foundation
import Testing
@testable import WhereCore

struct VersionedHistoryRecordTests {
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
            kind: "test",
            payload: Data([0, 255, 100]),
        )
        #expect(try VersionedHistoryRecord.admit(
            JSONEncoder().encode(value),
            policy: DataCompatibilityTestSupport.policy,
        ) == value)
    }
}
