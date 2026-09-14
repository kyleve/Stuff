import Foundation

public enum GitHubPublicationStep: String, Codable, Sendable {
    case branch
    case pullRequest
}

/// The review declares whether its text and changed files contain personal diagnostic evidence.
/// Preserve these raw values in saved proposals.
public enum GitHubReviewEvidence: String, Codable, Sendable {
    case synthetic
    case personal
}

/// A frozen proposal is the unit of review and retry. Reuse it after an uncertain network result.
public struct GitHubPullRequestProposal: Codable, Sendable {
    public let proposalID: UUID
    public let base: GitHubRepositorySnapshot
    public let changes: [GitHubFileChange]
    public let title: String
    public let body: String
    public let evidence: GitHubReviewEvidence
    public let author: GitHubAccount
    public let createdAt: Date
    public let installedBuildIdentity: String
    public let installedSourceIsDirty: Bool

    public init(
        proposalID: UUID,
        workspace: GitHubSourceWorkspace,
        title: String,
        body: String,
        evidence: GitHubReviewEvidence,
        author: GitHubAccount,
        createdAt: Date,
    ) throws {
        self.proposalID = proposalID
        base = workspace.repositoryBase
        changes = workspace.patch
        self.title = title
        self.body = body
        self.evidence = evidence
        self.author = author
        self.createdAt = createdAt
        installedBuildIdentity = workspace.installedSource.buildIdentity
        installedSourceIsDirty = workspace.installedSource.isDirty
        try validate()
    }

    public var branch: String {
        "codex/porthole-" + proposalID.uuidString.lowercased()
    }

    public var diff: String {
        get throws { try GitHubPatchReview.unifiedDiff(for: changes) }
    }

    public var fingerprint: String {
        get throws {
            // Sets have no stable Codable order. Canonical arrays keep retries identical across
            // processes.
            struct Content: Encodable {
                let proposalID: UUID
                let repository: GitHubRepository
                let branch: String
                let commit: GitHubObjectID
                let tree: GitHubObjectID
                let knownPaths: [GitHubRepositoryPath]
                let baseFiles: [GitHubSourceFile]
                let changes: [GitHubFileChange]
                let title: String
                let body: String
                let evidence: GitHubReviewEvidence
                let author: GitHubAccount
                let createdAt: Date
                let installedBuildIdentity: String
                let installedSourceIsDirty: Bool
            }
            return try GitHubFingerprint.value(Content(
                proposalID: proposalID,
                repository: base.repository,
                branch: base.branch,
                commit: base.commit,
                tree: base.tree,
                knownPaths: base.knownPaths.sorted(),
                baseFiles: base.files.sorted { $0.path < $1.path },
                changes: changes.sorted { $0.path < $1.path },
                title: title,
                body: body,
                evidence: evidence,
                author: author,
                createdAt: createdAt,
                installedBuildIdentity: installedBuildIdentity,
                installedSourceIsDirty: installedSourceIsDirty,
            ))
        }
    }

    public var marker: String {
        get throws { try "<!-- porthole:\(proposalID.uuidString.lowercased()):\(fingerprint) -->" }
    }

    func validate() throws {
        try base.validate()
        guard !changes.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.contains("\n"), Set(changes.map(\.path)).count == changes.count,
              author.userID > 0, !author.login.isEmpty,
              author.login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              createdAt.timeIntervalSince1970.isFinite else { throw GitHubError.emptyPatch }
        for change in changes {
            try change.validate()
            guard change.before == base.files.first(where: { $0.path == change.path }) else {
                throw GitHubError.missingBaseFile
            }
            if change.before == nil,
               base.knownPaths.contains(change.path) { throw GitHubError.missingBaseFile }
        }
    }
}

public struct GitHubPublishedPullRequest: Equatable, Codable, Sendable {
    public let number: Int
    public let url: URL
    public let commit: GitHubObjectID

    public init(number: Int, url: URL, commit: GitHubObjectID) {
        self.number = number
        self.url = url
        self.commit = commit
    }
}

public struct GitHubExistingPullRequest: Sendable {
    public let result: GitHubPublishedPullRequest
    public let body: String
    public let baseBranch: String
    public let isDraft: Bool

    public init(
        result: GitHubPublishedPullRequest,
        body: String,
        baseBranch: String,
        isDraft: Bool,
    ) {
        self.result = result
        self.body = body
        self.baseBranch = baseBranch
        self.isDraft = isDraft
    }
}

/// Git objects are content-addressed. Remote implementations must use the proposal's fixed author
/// and date.
public protocol GitHubPublishingRemote: Sendable {
    func createCommit(for proposal: GitHubPullRequestProposal) async throws -> GitHubObjectID
    func branchHead(repository: GitHubRepository, branch: String) async throws -> GitHubObjectID?
    func createBranch(
        repository: GitHubRepository,
        branch: String,
        commit: GitHubObjectID,
    ) async throws
    func pullRequests(repository: GitHubRepository, branch: String) async throws
        -> [GitHubExistingPullRequest]
    func createDraftPullRequest(
        proposal: GitHubPullRequestProposal,
        commit: GitHubObjectID,
    ) async throws -> GitHubPublishedPullRequest
}

/// Publishes only an approved immutable proposal. A failed write is reconciled before another write
/// is attempted.
public actor GitHubPublisher {
    /// Credential refresh may replace a token, but no publication request may change its author.
    enum Authorization {
        @TaskLocal static var expectedAccount: GitHubAccount?
    }

    private let remote: any GitHubPublishingRemote
    private var isPublishing = false

    public init(remote: any GitHubPublishingRemote) {
        self.remote = remote
    }

    public func publish(_ approvedProposal: GitHubPullRequestProposal) async throws
        -> GitHubPublishedPullRequest
    {
        guard !isPublishing else { throw GitHubError.busy }
        try approvedProposal.validate()
        isPublishing = true
        defer { isPublishing = false }
        return try await Authorization.$expectedAccount.withValue(approvedProposal.author) {
            try await publishBoundProposal(approvedProposal)
        }
    }

    private func publishBoundProposal(_ proposal: GitHubPullRequestProposal) async throws
        -> GitHubPublishedPullRequest
    {
        // Retrying these immutable Git objects produces the same IDs, including after a lost
        // response.
        let commit = try await remote.createCommit(for: proposal)
        try Task.checkCancellation()
        if let existing = try await remote.branchHead(
            repository: proposal.base.repository,
            branch: proposal.branch,
        ) {
            guard existing == commit else { throw GitHubError.branchConflict }
        } else {
            do {
                try await remote.createBranch(
                    repository: proposal.base.repository,
                    branch: proposal.branch,
                    commit: commit,
                )
            } catch {
                let observed: GitHubObjectID?
                do {
                    observed = try await remote.branchHead(
                        repository: proposal.base.repository,
                        branch: proposal.branch,
                    )
                } catch {
                    throw GitHubError.publicationUncertain(.branch)
                }
                guard let observed else { throw GitHubError.publicationUncertain(.branch) }
                guard observed == commit else { throw GitHubError.branchConflict }
            }
        }
        try Task.checkCancellation()
        if let existing = try await matchingPullRequest(proposal: proposal, commit: commit) {
            return existing
        }
        do {
            return try await remote.createDraftPullRequest(proposal: proposal, commit: commit)
        } catch {
            do {
                if let existing = try await matchingPullRequest(
                    proposal: proposal,
                    commit: commit,
                ) {
                    return existing
                }
            } catch GitHubError.pullRequestConflict {
                throw GitHubError.pullRequestConflict
            } catch {
                throw GitHubError.publicationUncertain(.pullRequest)
            }
            throw GitHubError.publicationUncertain(.pullRequest)
        }
    }

    private func matchingPullRequest(
        proposal: GitHubPullRequestProposal,
        commit: GitHubObjectID,
    ) async throws -> GitHubPublishedPullRequest? {
        let existing = try await remote.pullRequests(
            repository: proposal.base.repository,
            branch: proposal.branch,
        )
        guard !existing.isEmpty else { return nil }
        let marker = try proposal.marker
        guard existing.count == 1, let request = existing.first,
              request.result.commit == commit, request.baseBranch == proposal.base.branch,
              request.body.contains(marker) else { throw GitHubError.pullRequestConflict }
        // A user can promote or close an already-created draft. Never create another request for
        // it.
        return request.result
    }
}
