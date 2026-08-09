import PatchlightCore
import Testing

struct InterfacesTests {
    @Test func ownPullRequestsCanRepresentDraftsForSoloReview() {
        let summary = PullRequestSummary(
            id: PatchlightCoreTestSupport.pullRequestID,
            title: "Ship Patchlight",
            authorLogin: "solo",
            isDraft: true,
            headOID: PatchlightCoreTestSupport.objectID(),
            updatedAt: .distantPast,
        )
        #expect(summary.isDraft)
    }
}
