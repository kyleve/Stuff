import Foundation
import Observation
import PatchlightCore

public struct PatchlightDashboardContent: Sendable {
    public let dashboard: ReviewDashboard
    public let source: CachedReadSource
    public let refreshedAt: Date
    public let fallbackReason: ReadFallbackReason?

    init(_ read: CachedRead<ReviewDashboard>) {
        dashboard = read.value
        source = read.source
        refreshedAt = read.refreshedAt
        fallbackReason = read.fallbackReason
    }
}

public struct PatchlightWorkspaceContent: Sendable {
    public let workspace: PullRequestWorkspace
    public let source: CachedReadSource
    public let refreshedAt: Date
    public let fallbackReason: ReadFallbackReason?

    init(_ read: CachedRead<PullRequestWorkspace>) {
        workspace = read.value
        source = read.source
        refreshedAt = read.refreshedAt
        fallbackReason = read.fallbackReason
    }
}

/// The process model owns exactly one optional account world and exposes
/// state-machine values rather than parallel loading/error/data properties.
@MainActor
@Observable
public final class PatchlightAppModel {
    public enum AccountState {
        case signedOut
        case connecting(GitHubDeviceAuthorization?)
        case loading(previous: PatchlightDashboardContent?)
        case ready(PatchlightDashboardContent)
        case reauthorization(PatchlightDashboardContent?)
        case failed(previous: PatchlightDashboardContent?, message: String)
    }

    public enum WorkspaceState {
        case none
        case loading(PullRequestSummary)
        case ready(PatchlightWorkspaceContent)
        case failed(PullRequestSummary, message: String)
    }

    public enum RepositoryState {
        case none
        case loading(RepositorySummary)
        case ready(RepositorySummary, CachedRead<[PullRequestSummary]>)
        case failed(RepositorySummary, message: String)
    }

    public private(set) var accountState: AccountState = .signedOut
    public private(set) var workspaceState: WorkspaceState = .none
    public private(set) var repositoryState: RepositoryState = .none

    @ObservationIgnored private let dependencies: PatchlightApplicationDependencies
    @ObservationIgnored private let credentials: GitHubCredentialManager
    @ObservationIgnored private let github: GitHubAPIClient
    @ObservationIgnored private var world: AccountWorld?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?

    public init(dependencies: PatchlightApplicationDependencies) {
        self.dependencies = dependencies
        let credentials = GitHubCredentialManager(
            configuration: dependencies.githubConfiguration,
            credentials: dependencies.credentialStore,
            transport: dependencies.transport,
        )
        self.credentials = credentials
        github = GitHubAPIClient(credentials: credentials, transport: dependencies.transport)
    }

    public func restore() async {
        do {
            guard try await credentials.hasStoredCredentials() else {
                accountState = .signedOut
                return
            }

            if let identity = try await credentials.storedIdentity() {
                try activateWorld(for: identity)
                await refreshDashboard()
                return
            }

            accountState = .loading(previous: nil)
            let identity = try await github.viewer()
            try await credentials.storeIdentity(identity)
            try activateWorld(for: identity)
            await refreshDashboard()
        } catch let error as GitHubAuthenticationError
            where error == .reauthorizationRequired
        {
            accountState = .reauthorization(nil)
        } catch {
            accountState = .failed(previous: nil, message: error.localizedDescription)
        }
    }

    public func startAuthorization() {
        guard authorizationTask == nil else { return }
        accountState = .connecting(nil)
        authorizationTask = Task { [weak self] in
            await self?.authorize()
        }
    }

    public func cancelAuthorization() {
        authorizationTask?.cancel()
        authorizationTask = nil
        accountState = .signedOut
    }

    public func refreshDashboard() async {
        guard let world else { return }
        let previous = dashboardContent
        accountState = .loading(previous: previous)
        do {
            let content = try await PatchlightDashboardContent(world.reads.dashboard())
            if content.fallbackReason?.code == .reauthorizationRequired {
                accountState = .reauthorization(content)
            } else {
                accountState = .ready(content)
            }
        } catch let error as GitHubAuthenticationError
            where error == .reauthorizationRequired
        {
            accountState = .reauthorization(previous)
        } catch let error as GitHubAPIError where error == .authenticationExpired {
            accountState = .reauthorization(previous)
        } catch {
            accountState = .failed(previous: previous, message: error.localizedDescription)
        }
    }

    public func openWorkspace(_ pullRequest: PullRequestSummary) async {
        guard let world else { return }
        workspaceState = .loading(pullRequest)
        do {
            let read = try await world.reads.workspace(for: pullRequest.id)
            workspaceState = .ready(PatchlightWorkspaceContent(read))
        } catch {
            workspaceState = .failed(pullRequest, message: error.localizedDescription)
        }
    }

    public func openRepository(_ repository: RepositorySummary) async {
        guard let world else { return }
        repositoryState = .loading(repository)
        do {
            repositoryState = try await .ready(
                repository,
                world.reads.pullRequests(in: repository.id),
            )
        } catch {
            repositoryState = .failed(repository, message: error.localizedDescription)
        }
    }

    public func closeWorkspace() {
        workspaceState = .none
    }

    public func runVisibleDashboardRefreshLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(300))
            } catch {
                return
            }
            await refreshDashboard()
        }
    }

    public var dashboardContent: PatchlightDashboardContent? {
        switch accountState {
            case let .ready(content), let .reauthorization(.some(content)):
                content
            case let .loading(.some(content)), let .failed(.some(content), _):
                content
            case .signedOut, .connecting, .loading(.none), .reauthorization(.none), .failed(
            .none,
            _,
        ):
                nil
        }
    }

    public var githubAppInstallationURL: URL? {
        dependencies.githubConfiguration.installationURL
    }

    private func authorize() async {
        defer { authorizationTask = nil }
        do {
            let authorization = try await credentials.beginDeviceAuthorization()
            try Task.checkCancellation()
            accountState = .connecting(authorization)
            _ = try await credentials.completeDeviceAuthorization(authorization)
            try Task.checkCancellation()
            let identity = try await github.viewer()
            try await credentials.storeIdentity(identity)
            try activateWorld(for: identity)
            await refreshDashboard()
        } catch is CancellationError {
            accountState = .signedOut
        } catch {
            accountState = .failed(previous: nil, message: error.localizedDescription)
        }
    }

    private func activateWorld(for viewer: GitHubViewer) throws {
        if world?.scope.accountID == viewer.id { return }
        let scope = try PatchlightScope.make(
            accountID: viewer.id,
            rootURL: dependencies.accountsRootURL,
            credentialStore: dependencies.credentialStore,
            cacheCapacity: dependencies.cacheCapacity,
        )
        world = AccountWorld(
            scope: scope,
            reads: GitHubReadCoordinator(github: github, cache: scope.readCache),
        )
    }

    private struct AccountWorld {
        let scope: PatchlightScope
        let reads: GitHubReadCoordinator
    }
}
