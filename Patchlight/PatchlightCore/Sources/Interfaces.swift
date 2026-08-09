import Foundation

public struct RepositorySummary: Identifiable, Hashable, Codable, Sendable {
    public let id: RepositoryID
    public let coordinates: RepositoryCoordinates
    public let installationID: GitHubInstallationID?
    public let isPrivate: Bool
    public let defaultBranch: String

    public init(
        id: RepositoryID,
        coordinates: RepositoryCoordinates,
        installationID: GitHubInstallationID?,
        isPrivate: Bool,
        defaultBranch: String,
    ) {
        self.id = id
        self.coordinates = coordinates
        self.installationID = installationID
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
    }
}

public struct GitHubInstallationSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: GitHubInstallationID
    public let accountLogin: String
    public let accountType: AccountType
    public let repositories: [RepositorySummary]
    public let teamDiscovery: TeamDiscoveryAvailability

    public enum AccountType: String, Codable, Sendable {
        case user = "U"
        case organization = "O"
    }

    public init(
        id: GitHubInstallationID,
        accountLogin: String,
        accountType: AccountType,
        repositories: [RepositorySummary],
        teamDiscovery: TeamDiscoveryAvailability,
    ) {
        self.id = id
        self.accountLogin = accountLogin
        self.accountType = accountType
        self.repositories = repositories
        self.teamDiscovery = teamDiscovery
    }
}

public enum TeamDiscoveryAvailability: String, Codable, Sendable {
    case available = "A"
    case permissionWithheld = "W"
    case notApplicable = "N"
}

public struct GitHubReadWarning: Hashable, Codable, Sendable {
    public enum Code: String, Codable, Sendable {
        case teamDiscoveryUnavailable = "T"
        case partialGraphQLResponse = "G"
    }

    public let code: Code
    public let context: String?

    public init(code: Code, context: String?) {
        self.code = code
        self.context = context
    }
}

public enum ReviewRequestSource: Hashable, Codable, Sendable {
    case direct
    case team(organization: String, slug: String)
    case teamDiscoveryUnavailable

    private enum Code: String, Codable {
        case direct = "D"
        case team = "T"
        case teamDiscoveryUnavailable = "U"
    }

    private enum CodingKeys: String, CodingKey {
        case code = "c"
        case organization = "o"
        case slug = "s"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Code.self, forKey: .code) {
            case .direct:
                self = .direct
            case .team:
                self = try .team(
                    organization: container.decode(String.self, forKey: .organization),
                    slug: container.decode(String.self, forKey: .slug),
                )
            case .teamDiscoveryUnavailable:
                self = .teamDiscoveryUnavailable
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .direct:
                try container.encode(Code.direct, forKey: .code)
            case let .team(organization, slug):
                try container.encode(Code.team, forKey: .code)
                try container.encode(organization, forKey: .organization)
                try container.encode(slug, forKey: .slug)
            case .teamDiscoveryUnavailable:
                try container.encode(Code.teamDiscoveryUnavailable, forKey: .code)
        }
    }
}

public struct PullRequestSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: PullRequestID
    public let repository: RepositoryCoordinates
    public let title: String
    public let authorLogin: String
    public let isDraft: Bool
    public let headOID: GitObjectID
    public let updatedAt: Date
    public let reviewRequestSource: ReviewRequestSource?

    public init(
        id: PullRequestID,
        repository: RepositoryCoordinates,
        title: String,
        authorLogin: String,
        isDraft: Bool,
        headOID: GitObjectID,
        updatedAt: Date,
        reviewRequestSource: ReviewRequestSource?,
    ) {
        self.id = id
        self.repository = repository
        self.title = title
        self.authorLogin = authorLogin
        self.isDraft = isDraft
        self.headOID = headOID
        self.updatedAt = updatedAt
        self.reviewRequestSource = reviewRequestSource
    }
}

public struct GitHubViewer: Hashable, Codable, Sendable {
    public let id: PatchlightAccountID
    public let login: String
    public let avatarURL: URL?

    public init(id: PatchlightAccountID, login: String, avatarURL: URL?) {
        self.id = id
        self.login = login
        self.avatarURL = avatarURL
    }
}

public struct ReviewDashboard: Hashable, Codable, Sendable {
    public let viewer: GitHubViewer
    public let reviewRequests: [PullRequestSummary]
    public let ownPullRequests: [PullRequestSummary]
    public let installations: [GitHubInstallationSummary]
    public let warnings: [GitHubReadWarning]

    public init(
        viewer: GitHubViewer,
        reviewRequests: [PullRequestSummary],
        ownPullRequests: [PullRequestSummary],
        installations: [GitHubInstallationSummary],
        warnings: [GitHubReadWarning],
    ) {
        self.viewer = viewer
        self.reviewRequests = reviewRequests
        self.ownPullRequests = ownPullRequests
        self.installations = installations
        self.warnings = warnings
    }
}

public struct PullRequestWorkspace: Hashable, Codable, Sendable {
    public let summary: PullRequestSummary
    public let bodyMarkdown: String?
    public let baseOID: GitObjectID
    public let files: [DiffFile]
    public let isFileListComplete: Bool

    public init(
        summary: PullRequestSummary,
        bodyMarkdown: String?,
        baseOID: GitObjectID,
        files: [DiffFile],
        isFileListComplete: Bool,
    ) {
        self.summary = summary
        self.bodyMarkdown = bodyMarkdown
        self.baseOID = baseOID
        self.files = files
        self.isFileListComplete = isFileListComplete
    }
}

public protocol GitHubReading: Sendable {
    func viewer() async throws -> GitHubViewer
    func dashboard() async throws -> ReviewDashboard
    func installations() async throws -> [GitHubInstallationSummary]
    func repositories() async throws -> [RepositorySummary]
    func reviewRequests() async throws -> [PullRequestSummary]
    func ownPullRequests() async throws -> [PullRequestSummary]
    func pullRequests(in repository: RepositoryID) async throws -> [PullRequestSummary]
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
