import Foundation
import PortholeGitHub

enum PortholeGitHubUITestSupport {
    static let account = GitHubAccount(userID: 123, login: "fixture")
    static func base() throws -> GitHubRepositorySnapshot {
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        return try GitHubRepositorySnapshot(
            repository: .init(owner: "fixture", name: "Example"),
            branch: "main",
            commit: GitHubObjectID(String(repeating: "a", count: 40)),
            tree: GitHubObjectID(String(repeating: "b", count: 40)),
            knownPaths: [path],
            files: [GitHubSourceFile(path: path, text: "let value = 1\n", mode: .regular)],
        )
    }

    static func installed() throws -> GitHubInstalledSource {
        try GitHubInstalledSource(
            buildIdentity: "dirty-installed-build",
            isDirty: true,
            files: [.init(
                path: GitHubRepositoryPath("Sources/Example.swift"),
                text: "let value = 99\n",
                mode: .regular,
            )],
        )
    }
}

struct PortholeGitHubUIAuthentication: GitHubAuthenticating {
    func begin(at _: Date) throws -> GitHubDeviceFlow
        .Authorization
    {
        throw GitHubError.authorizationDenied
    }

    func poll(at _: Date) throws -> GitHubDeviceFlow.PollResult {
        throw GitHubError.noAuthorization
    }

    func cancel() {}
    func signOut() {}
}

struct PortholeGitHubUIRepository: GitHubRepositoryReading {
    func account() -> GitHubAccount {
        PortholeGitHubUITestSupport.account
    }

    func snapshot(
        repository _: GitHubRepository,
        branch _: String,
        paths _: [GitHubRepositoryPath],
        maximumFileBytes _: Int,
    ) throws -> GitHubRepositorySnapshot {
        try PortholeGitHubUITestSupport.base()
    }

    func snapshot(
        base: GitHubRepositorySnapshot,
        paths: [GitHubRepositoryPath],
        maximumFileBytes _: Int,
    ) throws -> GitHubRepositorySnapshot {
        try GitHubRepositorySnapshot(
            repository: base.repository,
            branch: base.branch,
            commit: base.commit,
            tree: base.tree,
            knownPaths: base.knownPaths,
            files: base.files.filter { paths.contains($0.path) },
        )
    }

    func ciStatus(
        repository _: GitHubRepository,
        commit: GitHubObjectID,
    ) -> GitHubCIStatus {
        GitHubCIStatus(
            commit: commit,
            checks: [],
        )
    }
}

actor PortholeGitHubUIPublisher: GitHubPublishing {
    private(set) var proposals: [GitHubPullRequestProposal] = []
    private var loseNextReply = false
    func loseReply() {
        loseNextReply = true
    }

    func publish(_ approvedProposal: GitHubPullRequestProposal) throws
        -> GitHubPublishedPullRequest
    {
        proposals.append(approvedProposal)
        if loseNextReply {
            loseNextReply = false; throw GitHubError.publicationUncertain(.pullRequest)
        }
        return try GitHubPublishedPullRequest(
            number: 12,
            url: URL(string: "https://github.com/fixture/Example/pull/12")!,
            commit: GitHubObjectID(String(repeating: "c", count: 40)),
        )
    }
}

actor PortholeGitHubUIControlledAuthentication: GitHubAuthenticating {
    private(set) var beginCount = 0
    private var pendingBegin: CheckedContinuation<GitHubDeviceFlow.Authorization, any Error>?
    private var beginArrival: CheckedContinuation<Void, Never>?
    private var pendingCancel: CheckedContinuation<Void, Never>?
    private var cancelArrival: CheckedContinuation<Void, Never>?

    func begin(at _: Date) async throws -> GitHubDeviceFlow.Authorization {
        beginCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingBegin = continuation
            beginArrival?.resume(); beginArrival = nil
        }
    }

    func waitForBegin() async {
        if pendingBegin != nil { return }
        await withCheckedContinuation { beginArrival = $0 }
    }

    func poll(at _: Date) throws -> GitHubDeviceFlow.PollResult {
        throw GitHubError.noAuthorization
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            pendingCancel = continuation
            cancelArrival?.resume(); cancelArrival = nil
        }
    }

    func waitForCancellation() async {
        if pendingCancel != nil { return }
        await withCheckedContinuation { cancelArrival = $0 }
    }

    func completeCancellation() {
        pendingBegin?.resume(throwing: CancellationError()); pendingBegin = nil
        pendingCancel?.resume(); pendingCancel = nil
    }

    func signOut() {}
}

actor PortholeGitHubUIControlledRepository: GitHubRepositoryReading {
    private var pauseNextCI = false
    private var pending: CheckedContinuation<GitHubCIStatus, Never>?
    private var pendingCommit: GitHubObjectID?
    private var arrival: CheckedContinuation<Void, Never>?
    private(set) var fixedBaseReads = 0
    private(set) var branchReads = 0
    private var branchSnapshot: GitHubRepositorySnapshot?
    private var pauseNextLoad = false
    private var pendingLoad: CheckedContinuation<Void, Never>?
    private var loadArrival: CheckedContinuation<Void, Never>?

    func suspendNextLoad() {
        pauseNextLoad = true
    }

    func waitForLoad() async {
        if pendingLoad != nil { return }
        await withCheckedContinuation { loadArrival = $0 }
    }

    func completeLoad() {
        guard let pendingLoad else { preconditionFailure("No suspended repository load") }
        self.pendingLoad = nil
        pendingLoad.resume()
    }

    func setBranchSnapshot(_ snapshot: GitHubRepositorySnapshot) {
        branchSnapshot = snapshot
    }

    func account() -> GitHubAccount {
        PortholeGitHubUITestSupport.account
    }

    func snapshot(
        repository: GitHubRepository,
        branch: String,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) throws -> GitHubRepositorySnapshot {
        branchReads += 1
        if let branchSnapshot { return branchSnapshot }
        return try PortholeGitHubUIRepository().snapshot(
            repository: repository,
            branch: branch,
            paths: paths,
            maximumFileBytes: maximumFileBytes,
        )
    }

    func snapshot(
        base: GitHubRepositorySnapshot,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot {
        fixedBaseReads += 1
        if pauseNextLoad {
            pauseNextLoad = false
            await withCheckedContinuation { continuation in
                pendingLoad = continuation
                loadArrival?.resume(); loadArrival = nil
            }
        }
        return try PortholeGitHubUIRepository().snapshot(
            base: base,
            paths: paths,
            maximumFileBytes: maximumFileBytes,
        )
    }

    func suspendNextCI() {
        pauseNextCI = true
    }

    func ciStatus(repository _: GitHubRepository, commit: GitHubObjectID) async -> GitHubCIStatus {
        if pauseNextCI {
            pauseNextCI = false
            return await withCheckedContinuation { continuation in
                pending = continuation
                pendingCommit = commit
                arrival?.resume(); arrival = nil
            }
        }
        return passing(commit: commit)
    }

    func waitForCI() async {
        if pending != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func completeCI() {
        guard let pending, let pendingCommit else { preconditionFailure("No suspended CI read") }
        self.pending = nil; self.pendingCommit = nil
        pending.resume(returning: passing(commit: pendingCommit))
    }

    private func passing(commit: GitHubObjectID) -> GitHubCIStatus {
        GitHubCIStatus(
            commit: commit,
            checks: [.init(name: "Synthetic regression suite", state: .passed, detailsURL: nil)],
        )
    }
}
