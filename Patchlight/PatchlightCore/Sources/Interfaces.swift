import Foundation

public struct RepositorySummary: Identifiable, Hashable, Codable, Sendable {
    public let id: RepositoryID
    public let owner: String
    public let name: String
    public let isPrivate: Bool

    public init(id: RepositoryID, owner: String, name: String, isPrivate: Bool) {
        self.id = id
        self.owner = owner
        self.name = name
        self.isPrivate = isPrivate
    }
}

public struct PullRequestSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: PullRequestID
    public let title: String
    public let authorLogin: String
    public let isDraft: Bool
    public let headOID: GitObjectID
    public let updatedAt: Date

    public init(
        id: PullRequestID,
        title: String,
        authorLogin: String,
        isDraft: Bool,
        headOID: GitObjectID,
        updatedAt: Date,
    ) {
        self.id = id
        self.title = title
        self.authorLogin = authorLogin
        self.isDraft = isDraft
        self.headOID = headOID
        self.updatedAt = updatedAt
    }
}

public struct PullRequestWorkspace: Hashable, Codable, Sendable {
    public let summary: PullRequestSummary
    public let baseOID: GitObjectID
    public let files: [DiffFile]
    public let isFileListComplete: Bool

    public init(
        summary: PullRequestSummary,
        baseOID: GitObjectID,
        files: [DiffFile],
        isFileListComplete: Bool,
    ) {
        self.summary = summary
        self.baseOID = baseOID
        self.files = files
        self.isFileListComplete = isFileListComplete
    }
}

public protocol GitHubReading: Sendable {
    func repositories() async throws -> [RepositorySummary]
    func reviewRequests() async throws -> [PullRequestSummary]
    func ownPullRequests() async throws -> [PullRequestSummary]
    func workspace(for id: PullRequestID) async throws -> PullRequestWorkspace
    func blob(repository: RepositoryID, oid: GitObjectID, path: String) async throws -> Data
}

public enum ReviewEvent: String, Codable, Sendable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
}

public struct ReviewDraft: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let pullRequest: PullRequestID
    public let anchor: DiffAnchor?
    public let body: String
    public let updatedAt: Date

    public init(
        id: UUID,
        pullRequest: PullRequestID,
        anchor: DiffAnchor?,
        body: String,
        updatedAt: Date,
    ) {
        self.id = id
        self.pullRequest = pullRequest
        self.anchor = anchor
        self.body = body
        self.updatedAt = updatedAt
    }
}

public struct ReviewSubmission: Hashable, Codable, Sendable {
    public let pullRequest: PullRequestID
    public let headOID: GitObjectID
    public let event: ReviewEvent
    public let summary: String?
    public let drafts: [ReviewDraft]

    public init(
        pullRequest: PullRequestID,
        headOID: GitObjectID,
        event: ReviewEvent,
        summary: String?,
        drafts: [ReviewDraft],
    ) {
        self.pullRequest = pullRequest
        self.headOID = headOID
        self.event = event
        self.summary = summary
        self.drafts = drafts
    }
}

public protocol GitHubReviewWriting: Sendable {
    func submit(_ review: ReviewSubmission) async throws
    func reply(to threadID: String, body: String) async throws
    func setThread(_ threadID: String, resolved: Bool) async throws
    func markFile(_ path: String, viewed: Bool, in pullRequest: PullRequestID) async throws
}

public struct ReviewAnalysisRequest: Hashable, Codable, Sendable {
    public let pullRequest: PullRequestID
    public let headOID: GitObjectID
    public let files: [DiffFile]

    public init(pullRequest: PullRequestID, headOID: GitObjectID, files: [DiffFile]) {
        self.pullRequest = pullRequest
        self.headOID = headOID
        self.files = files
    }
}

public struct ReviewAnalysis: Hashable, Codable, Sendable {
    public let assessments: [ReviewAssessment]
    public let summary: String

    public init(assessments: [ReviewAssessment], summary: String) {
        self.assessments = assessments
        self.summary = summary
    }
}

public protocol ReviewAnalysisProvider: Sendable {
    var providerID: String { get }
    var modelID: String { get }
    func analyze(_ request: ReviewAnalysisRequest) async throws -> ReviewAnalysis
}
