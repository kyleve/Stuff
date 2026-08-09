import Foundation
import PatchlightCore
import Testing

struct PatchlightAccountStoreTests {
    @Test func draftsRoundTripThroughEncryptedPersistence() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let draft = ReviewDraft(
            id: UUID(),
            pullRequest: PatchlightCoreTestSupport.pullRequestID,
            anchor: DiffAnchor(
                path: "Sources/Auth.swift",
                side: .head,
                commitOID: PatchlightCoreTestSupport.objectID(),
                blobOID: PatchlightCoreTestSupport.objectID("b"),
                line: 42,
                startLine: nil,
                contextFingerprint: "fingerprint",
            ),
            body: "Could this race during token rotation?",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        try await setup.scope.accountStore.saveDraft(draft)
        #expect(
            try await setup.scope.accountStore.drafts(for: draft.pullRequest) == [draft],
        )

        try await setup.scope.accountStore.removeDraft(draft.id)
        #expect(try await setup.scope.accountStore.drafts(for: draft.pullRequest).isEmpty)
    }
}
