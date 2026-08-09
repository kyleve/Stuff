import Foundation
@_spi(Testing) import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct PatchlightReadCacheTests {
    @Test func failedRefreshReturnsEncryptedCacheWithHonestOfflineState() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: "read-cache")
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let dashboard = sampleDashboard()
        let reader = SwitchingGitHubReader(dashboard: dashboard)
        let timestamp = Date(timeIntervalSince1970: 2000)
        let coordinator = GitHubReadCoordinator(
            github: reader,
            cache: setup.scope.readCache,
            now: { timestamp },
        )

        let live = try await coordinator.dashboard()
        #expect(live.source == .live)
        #expect(live.refreshedAt == timestamp)

        await reader.fail(with: .offline)
        let cached = try await coordinator.dashboard()
        #expect(cached.value == dashboard)
        #expect(cached.source == .cache)
        #expect(cached.fallbackReason?.code == .offline)
        #expect(cached.refreshedAt == timestamp)
    }

    @Test func authenticationExpiryUsesCacheWithoutDeletingTheAccountWorld() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: "reauthorization-cache")
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let reader = SwitchingGitHubReader(dashboard: sampleDashboard())
        let coordinator = GitHubReadCoordinator(
            github: reader,
            cache: setup.scope.readCache,
            now: { Date(timeIntervalSince1970: 3000) },
        )
        _ = try await coordinator.dashboard()

        await reader.fail(with: .reauthorization)
        let cached = try await coordinator.dashboard()

        #expect(cached.source == .cache)
        #expect(cached.fallbackReason?.code == .reauthorizationRequired)
        #expect(FileManager.default.fileExists(atPath: setup.root.path))
    }
}

private actor SwitchingGitHubReader: GitHubReading {
    enum Failure {
        case offline
        case reauthorization
    }

    private let dashboardValue: ReviewDashboard
    private var failure: Failure?

    init(dashboard: ReviewDashboard) {
        dashboardValue = dashboard
    }

    func fail(with failure: Failure) {
        self.failure = failure
    }

    func viewer() async throws -> GitHubViewer {
        try currentDashboard().viewer
    }

    func dashboard() async throws -> ReviewDashboard {
        try currentDashboard()
    }

    func installations() async throws -> [GitHubInstallationSummary] {
        try currentDashboard().installations
    }

    func repositories() async throws -> [RepositorySummary] {
        try currentDashboard().installations.flatMap(\.repositories)
    }

    func reviewRequests() async throws -> [PullRequestSummary] {
        try currentDashboard().reviewRequests
    }

    func ownPullRequests() async throws -> [PullRequestSummary] {
        try currentDashboard().ownPullRequests
    }

    func pullRequests(in _: RepositoryID) async throws -> [PullRequestSummary] {
        try currentDashboard().ownPullRequests
    }

    func workspace(for _: PullRequestID) async throws -> PullRequestWorkspace {
        _ = try currentDashboard()
        throw GitHubAPIError.notFound
    }

    func blob(repository _: RepositoryID, oid _: GitObjectID, path _: String) async throws -> Data {
        _ = try currentDashboard()
        return Data()
    }

    private func currentDashboard() throws -> ReviewDashboard {
        switch failure {
            case .none:
                dashboardValue
            case .offline:
                throw URLError(.notConnectedToInternet)
            case .reauthorization:
                throw GitHubAuthenticationError.reauthorizationRequired
        }
    }
}

private func sampleDashboard() -> ReviewDashboard {
    let installationID = GitHubInstallationID(rawValue: 91)
    let repository = RepositorySummary(
        id: PatchlightCoreTestSupport.repositoryID,
        coordinates: RepositoryCoordinates(owner: "acme", name: "widget"),
        installationID: installationID,
        isPrivate: true,
        defaultBranch: "main",
    )
    return ReviewDashboard(
        viewer: GitHubViewer(
            id: PatchlightAccountID(rawValue: 42),
            login: "reviewer",
            avatarURL: nil,
        ),
        reviewRequests: [],
        ownPullRequests: [],
        installations: [GitHubInstallationSummary(
            id: installationID,
            accountLogin: "acme",
            accountType: .organization,
            repositories: [repository],
            teamDiscovery: .available,
        )],
        warnings: [],
    )
}
