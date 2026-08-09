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
            createdAt: .distantPast,
            updatedAt: .distantPast,
            reviewRequestSource: nil,
            actionability: .draft,
        )
        #expect(summary.isDraft)
    }
}
