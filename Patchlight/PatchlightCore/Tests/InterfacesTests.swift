import PatchlightCore
import Testing

struct InterfacesTests {
    @Test func ownPullRequestsCanRepresentDraftsForSoloReview() {
        let summary = PullRequestSummary(
            id: PatchlightCoreTestSupport.pullRequestID,
            repository: RepositoryCoordinates(owner: "example", name: "project"),
            title: "Ship Patchlight",
            authorLogin: "solo",
            isDraft: true,
            headOID: PatchlightCoreTestSupport.objectID(),
            updatedAt: .distantPast,
            reviewRequestSource: nil,
        )
        #expect(summary.isDraft)
    }
}
