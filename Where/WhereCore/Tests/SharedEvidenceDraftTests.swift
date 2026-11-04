import Foundation
import Testing
@testable import WhereCore

struct SharedEvidenceDraftTests {
    @Test func receiptSurvivesEncodingAndCoversMetadataAndAttachmentBytes() throws {
        let draft = try makeSharedEvidenceDraft()
        let decoded = try JSONDecoder().decode(
            SharedEvidenceDraft.self,
            from: JSONEncoder().encode(draft),
        )
        #expect(decoded == draft)
        #expect(try decoded.receipt() == draft.receipt())
        let changed = try SharedEvidenceDraft(id: draft.id, items: [
            .init(evidence: draft.items[0].evidence, blob: Data("different receipt".utf8)),
            draft.items[1],
        ])
        #expect(try changed.receipt() != draft.receipt())
    }

    @Test func validationRejectsEmptyDuplicateAndUnknownFormatDrafts() throws {
        #expect(throws: SharedEvidenceDraft.ValidationError.emptyDraft) {
            try SharedEvidenceDraft(id: .init(rawValue: UUID()), items: [])
        }
        let draft = try makeSharedEvidenceDraft()
        #expect(throws: SharedEvidenceDraft.ValidationError.duplicateEvidence) {
            try SharedEvidenceDraft(id: draft.id, items: [draft.items[0], draft.items[0]])
        }
        var payload = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        payload["formatVersion"] = 2
        let newer = try JSONDecoder().decode(
            SharedEvidenceDraft.self,
            from: JSONSerialization.data(withJSONObject: payload),
        )
        #expect(throws: SharedEvidenceDraft.ValidationError.unsupportedFormat(2)) {
            try newer.validate()
        }
    }
}
