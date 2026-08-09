import Foundation

/// Ranks the review inbox from GitHub metadata and the last encrypted inbox
/// snapshot. It never fetches PR diffs or invokes a provider.
public enum ReviewDashboardRanker {
    public static func rank(
        _ current: ReviewDashboard,
        previous: ReviewDashboard?,
    ) -> ReviewDashboard {
        let previousByID = Dictionary(
            uniqueKeysWithValues: (previous?.reviewRequests ?? []).map { ($0.id, $0) },
        )
        let requests = current.reviewRequests.map { pullRequest in
            let actionability = actionability(
                for: pullRequest,
                previous: previousByID[pullRequest.id],
            )
            return PullRequestSummary(
                id: pullRequest.id,
                repository: pullRequest.repository,
                title: pullRequest.title,
                authorLogin: pullRequest.authorLogin,
                isDraft: pullRequest.isDraft,
                headOID: pullRequest.headOID,
                createdAt: pullRequest.createdAt,
                updatedAt: pullRequest.updatedAt,
                reviewRequestSource: pullRequest.reviewRequestSource,
                actionability: actionability,
            )
        }.sorted(by: comesBefore)
        return ReviewDashboard(
            viewer: current.viewer,
            reviewRequests: requests,
            ownPullRequests: current.ownPullRequests,
            installations: current.installations,
            warnings: current.warnings,
        )
    }

    private static func actionability(
        for current: PullRequestSummary,
        previous: PullRequestSummary?,
    ) -> ReviewActionability {
        guard let previous else {
            return switch current.reviewRequestSource {
                case .direct: .directRequest
                case .team: .teamRequest
                case .teamDiscoveryUnavailable, nil: current.actionability
            }
        }
        if current.headOID != previous.headOID || current.updatedAt > previous.updatedAt {
            return .newActivity
        }
        return current.actionability
    }

    private static func comesBefore(
        _ lhs: PullRequestSummary,
        _ rhs: PullRequestSummary,
    ) -> Bool {
        if lhs.actionability.priority != rhs.actionability.priority {
            return lhs.actionability.priority < rhs.actionability.priority
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        if lhs.repository != rhs.repository {
            return lhs.repository.displayName.localizedStandardCompare(rhs.repository.displayName)
                == .orderedAscending
        }
        return lhs.id.number < rhs.id.number
    }
}
