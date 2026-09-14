import Foundation

public struct GitHubCICheck: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case pending
        case passed
        case failed
        case cancelled
        case skipped
        case unknown(String)
    }

    public let name: String
    public let state: State
    public let detailsURL: URL?

    public init(name: String, state: State, detailsURL: URL?) {
        self.name = name
        self.state = state
        self.detailsURL = detailsURL
    }
}

/// Checks and legacy statuses are both required: external CI providers can use either GitHub API.
public struct GitHubCIStatus: Sendable {
    public let commit: GitHubObjectID
    public let checks: [GitHubCICheck]

    public init(commit: GitHubObjectID, checks: [GitHubCICheck]) {
        self.commit = commit
        self.checks = checks
    }

    /// No reported checks is pending, never a passing build.
    public var state: GitHubCICheck.State {
        if checks.isEmpty { return .pending }
        if checks.contains(where: { $0.state == .failed }) { return .failed }
        if checks.contains(where: { $0.state == .cancelled }) { return .cancelled }
        for check in checks {
            if case .unknown = check.state { return check.state }
        }
        if checks.contains(where: { $0.state == .pending }) { return .pending }
        if checks.allSatisfy({ $0.state == .skipped }) { return .skipped }
        return .passed
    }
}

extension GitHubRepositoryClient {
    public func ciStatus(
        repository: GitHubRepository,
        commit: GitHubObjectID,
    ) async throws -> GitHubCIStatus {
        try repository.validate()
        try commit.validate()
        let prefix = repositoryPath(repository) + ["commits", commit.rawValue]
        var checks: [GitHubCICheck] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let result: CheckRuns = try await get(path: prefix + ["check-runs"], query: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(
                    name: "page",
                    value: String(page),
                ),
                URLQueryItem(name: "filter", value: "latest"),
            ])
            checks += result.check_runs.map(\.check)
            if result.check_runs.count < 100 { break }
            page += 1
        }
        page = 1
        var seenContexts: Set<String> = []
        while true {
            try Task.checkCancellation()
            let result: CombinedStatus = try await get(path: prefix + ["status"], query: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(
                    name: "page",
                    value: String(page),
                ),
            ])
            for status in result.statuses where seenContexts.insert(status.context).inserted {
                checks.append(status.check)
            }
            if result.statuses.count < 100 { break }
            page += 1
        }
        return GitHubCIStatus(commit: commit, checks: checks)
    }
}

private struct CheckRuns: Decodable {
    struct Run: Decodable {
        let name: String
        let status: String
        let conclusion: String?
        let html_url: URL?

        var check: GitHubCICheck {
            let state: GitHubCICheck.State = if status != "completed" {
                ["queued", "in_progress", "waiting", "pending", "requested"]
                    .contains(status) ? .pending : .unknown(status)
            } else {
                switch conclusion {
                    case "success": .passed
                    case "failure", "timed_out", "action_required", "startup_failure",
                         "stale": .failed
                    case "cancelled": .cancelled
                    case "skipped", "neutral": .skipped
                    case let other: .unknown(other ?? "missing_conclusion")
                }
            }
            return GitHubCICheck(name: name, state: state, detailsURL: html_url)
        }
    }

    let check_runs: [Run]
}

private struct CombinedStatus: Decodable {
    struct Status: Decodable {
        let context: String
        let state: String
        let target_url: URL?

        var check: GitHubCICheck {
            let result: GitHubCICheck.State = switch state {
                case "success": .passed
                case "failure", "error": .failed
                case "pending": .pending
                case let other: .unknown(other)
            }
            return GitHubCICheck(name: context, state: result, detailsURL: target_url)
        }
    }

    let statuses: [Status]
}
