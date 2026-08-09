import Foundation
import PatchlightCore
import Testing

struct ReviewDashboardRankerTests {
    @Test func ranksNewAndUnseenRequestsAheadOfDeterministicWaitingSignals() {
        let current = [
            summary(1, actionability: .waiting, source: .direct, updated: 20, head: "b"),
            summary(2, actionability: .waiting, source: .direct, updated: 19),
            summary(
                3,
                actionability: .waiting,
                source: .team(organization: "acme", slug: "ios"),
                updated: 18,
            ),
            summary(4, actionability: .unresolvedThreads, source: .direct, updated: 17),
            summary(5, actionability: .pendingChecks, source: .direct, updated: 16),
            summary(6, actionability: .draft, source: .direct, updated: 15),
            summary(7, actionability: .failedChecks, source: .direct, updated: 14),
            summary(8, actionability: .changesRequested, source: .direct, updated: 13),
            summary(9, actionability: .waiting, source: .direct, updated: 12),
        ]
        let previous = [
            summary(1, actionability: .waiting, source: .direct, updated: 10, head: "a"),
            summary(4, actionability: .unresolvedThreads, source: .direct, updated: 17),
            summary(5, actionability: .pendingChecks, source: .direct, updated: 16),
            summary(6, actionability: .draft, source: .direct, updated: 15),
            summary(7, actionability: .failedChecks, source: .direct, updated: 14),
            summary(8, actionability: .changesRequested, source: .direct, updated: 13),
            summary(9, actionability: .waiting, source: .direct, updated: 12),
        ]

        let ranked = ReviewDashboardRanker.rank(
            dashboard(current),
            previous: dashboard(previous),
        )

        #expect(ranked.reviewRequests.map(\.id.number) == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(ranked.reviewRequests.map(\.actionability) == [
            .newActivity,
            .directRequest,
            .teamRequest,
            .unresolvedThreads,
            .pendingChecks,
            .draft,
            .failedChecks,
            .changesRequested,
            .waiting,
        ])
    }

    @Test func tiesUseRelevantActivityThenOldestCreationDate() {
        let values = [
            summary(1, actionability: .pendingChecks, source: nil, created: 5, updated: 10),
            summary(2, actionability: .pendingChecks, source: nil, created: 1, updated: 10),
            summary(3, actionability: .pendingChecks, source: nil, created: 0, updated: 11),
        ]

        let ranked = ReviewDashboardRanker.rank(dashboard(values), previous: dashboard(values))

        #expect(ranked.reviewRequests.map(\.id.number) == [3, 2, 1])
    }

    private func dashboard(_ values: [PullRequestSummary]) -> ReviewDashboard {
        ReviewDashboard(
            viewer: GitHubViewer(
                id: PatchlightAccountID(rawValue: 42),
                login: "reviewer",
                avatarURL: nil,
            ),
            reviewRequests: values,
            ownPullRequests: [],
            installations: [],
            warnings: [],
        )
    }

    private func summary(
        _ number: Int,
        actionability: ReviewActionability,
        source: ReviewRequestSource?,
        created: TimeInterval = 0,
        updated: TimeInterval,
        head: Character = "a",
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PullRequestID(
                repository: RepositoryID(rawValue: 7),
                number: number,
            ),
            repository: RepositoryCoordinates(owner: "acme", name: "widget"),
            title: "Review \(number)",
            authorLogin: "author",
            isDraft: actionability == .draft,
            headOID: GitObjectID(rawValue: String(repeating: head, count: 40)),
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            reviewRequestSource: source,
            actionability: actionability,
        )
    }
}
