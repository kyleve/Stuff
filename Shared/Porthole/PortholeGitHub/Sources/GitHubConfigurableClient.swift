import Foundation

/// A public GitHub App client ID can be configured after installation. Its user token stays in
/// Keychain.
public actor GitHubConfigurableClient: GitHubAuthenticating, GitHubRepositoryReading,
    GitHubPublishing
{
    private struct Services {
        let clientID: GitHubClientID
        let authentication: GitHubDeviceFlow
        let repository: GitHubRepositoryClient
        let publisher: GitHubPublisher
    }

    private let transport: any GitHubHTTPTransport
    private let credentials: any GitHubCredentialStore
    private let configurationURL: URL?
    private var services: Services?

    public init(
        clientID: GitHubClientID?,
        configurationURL: URL?,
        transport: any GitHubHTTPTransport,
        credentials: any GitHubCredentialStore,
    ) throws {
        self.transport = transport
        self.credentials = credentials
        self.configurationURL = configurationURL
        let resolved: GitHubClientID? = if let clientID { clientID }
        else if let configurationURL,
                FileManager.default.fileExists(atPath: configurationURL.path)
        {
            try JSONDecoder().decode(GitHubClientID.self, from: Data(contentsOf: configurationURL))
        } else { nil }
        if let resolved { services = Self.makeServices(
            clientID: resolved,
            transport: transport,
            credentials: credentials,
        ) }
    }

    public func configuredClientID() -> GitHubClientID? {
        services?.clientID
    }

    public func configure(clientID: GitHubClientID) throws {
        guard services == nil else { throw GitHubError.busy }
        if let configurationURL {
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try JSONEncoder().encode(clientID).write(to: configurationURL, options: .atomic)
        }
        services = Self.makeServices(
            clientID: clientID,
            transport: transport,
            credentials: credentials,
        )
    }

    public func begin(at now: Date) async throws -> GitHubDeviceFlow
        .Authorization
    {
        try await configured().authentication.begin(at: now)
    }

    public func poll(at now: Date) async throws -> GitHubDeviceFlow
        .PollResult
    {
        try await configured().authentication.poll(at: now)
    }

    public func cancel() async {
        if let services { await services.authentication.cancel() }
    }

    public func signOut() async throws {
        try await configured().authentication.signOut()
    }

    public func account() async throws -> GitHubAccount {
        try await configured().repository
            .account()
    }

    public func snapshot(
        repository: GitHubRepository,
        branch: String,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot {
        try await configured().repository.snapshot(
            repository: repository,
            branch: branch,
            paths: paths,
            maximumFileBytes: maximumFileBytes,
        )
    }

    public func snapshot(
        base: GitHubRepositorySnapshot,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot {
        try await configured().repository.snapshot(
            base: base,
            paths: paths,
            maximumFileBytes: maximumFileBytes,
        )
    }

    public func ciStatus(
        repository: GitHubRepository,
        commit: GitHubObjectID,
    ) async throws -> GitHubCIStatus {
        try await configured().repository.ciStatus(repository: repository, commit: commit)
    }

    public func publish(_ approvedProposal: GitHubPullRequestProposal) async throws
        -> GitHubPublishedPullRequest
    {
        try await configured().publisher.publish(approvedProposal)
    }

    private func configured() throws -> Services {
        guard let services else { throw GitHubError.invalidIdentifier }
        return services
    }

    private static func makeServices(
        clientID: GitHubClientID,
        transport: any GitHubHTTPTransport,
        credentials: any GitHubCredentialStore,
    ) -> Services {
        let authentication = GitHubDeviceFlow(
            clientID: clientID,
            transport: transport,
            credentials: credentials,
        )
        let repository = GitHubRepositoryClient(
            clientID: clientID,
            transport: transport,
            credentials: credentials,
            now: { Date() },
        )
        return Services(
            clientID: clientID,
            authentication: authentication,
            repository: repository,
            publisher: GitHubPublisher(remote: repository),
        )
    }
}
