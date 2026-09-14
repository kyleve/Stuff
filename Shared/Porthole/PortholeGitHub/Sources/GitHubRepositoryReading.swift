import Foundation

public protocol GitHubRepositoryReading: Sendable {
    func account() async throws -> GitHubAccount
    func snapshot(
        repository: GitHubRepository,
        branch: String,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot
    func snapshot(
        base: GitHubRepositorySnapshot,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot
    func ciStatus(repository: GitHubRepository, commit: GitHubObjectID) async throws
        -> GitHubCIStatus
}

extension GitHubRepositoryClient: GitHubRepositoryReading {}

public protocol GitHubAuthenticating: Sendable {
    func begin(at now: Date) async throws -> GitHubDeviceFlow.Authorization
    func poll(at now: Date) async throws -> GitHubDeviceFlow.PollResult
    func cancel() async
    func signOut() async throws
}

extension GitHubDeviceFlow: GitHubAuthenticating {}

public protocol GitHubPublishing: Sendable {
    func publish(_ approvedProposal: GitHubPullRequestProposal) async throws
        -> GitHubPublishedPullRequest
}

extension GitHubPublisher: GitHubPublishing {}
