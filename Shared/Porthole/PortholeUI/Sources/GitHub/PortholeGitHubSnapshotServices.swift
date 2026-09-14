#if canImport(UIKit)
    import Foundation
    import PortholeGitHub

    /// Snapshot dependencies never access GitHub, Keychain, or a user's repository workspace.
    struct PortholeGitHubSnapshotServices: GitHubAuthenticating, GitHubRepositoryReading,
        GitHubPublishing
    {
        @MainActor static func makeModel() -> PortholeGitHubPresentationModel {
            do {
                let services = Self()
                return try PortholeGitHubPresentationModel(
                    authentication: services,
                    repository: services,
                    publisher: services,
                    workspaceStore: GitHubWorkspaceStore(storageURL: nil),
                    installedSource: GitHubInstalledSource(
                        buildIdentity: "snapshot-build",
                        isDirty: false,
                        files: [],
                    ),
                    initialRepository: GitHubRepository(owner: "example", name: "Example"),
                    initialBranch: "main",
                    initialPaths: [],
                )
            } catch { preconditionFailure("Invalid GitHub snapshot fixture: \(error)") }
        }

        @MainActor static func comparison() -> PortholeGitHubSourceComparison {
            do {
                let path = try GitHubRepositoryPath("Sources/FlightDetector.swift")
                let base = try GitHubRepositorySnapshot(
                    repository: GitHubRepository(owner: "example", name: "Example"),
                    branch: "main",
                    commit: GitHubObjectID(String(repeating: "a", count: 40)),
                    tree: GitHubObjectID(String(repeating: "b", count: 40)),
                    knownPaths: [path],
                    files: [.init(path: path, text: "let minimumSamples = 4\n", mode: .regular)],
                )
                let source = GitHubInstalledSource(
                    buildIdentity: "snapshot-build",
                    isDirty: true,
                    files: [
                        .init(path: path, text: "let minimumSamples = 6\n", mode: .regular),
                    ],
                )
                return PortholeGitHubSourceComparison(
                    workspace: GitHubSourceWorkspace(installedSource: source, repositoryBase: base),
                    path: path,
                )
            } catch { preconditionFailure("Invalid source comparison fixture: \(error)") }
        }

        func begin(at _: Date) throws -> GitHubDeviceFlow
            .Authorization
        {
            throw GitHubError.unauthenticated
        }

        func poll(at _: Date) throws -> GitHubDeviceFlow
            .PollResult
        {
            throw GitHubError.unauthenticated
        }

        func cancel() {}
        func signOut() {}
        func account() throws -> GitHubAccount {
            throw GitHubError.unauthenticated
        }

        func snapshot(
            repository _: GitHubRepository,
            branch _: String,
            paths _: [GitHubRepositoryPath],
            maximumFileBytes _: Int,
        ) throws -> GitHubRepositorySnapshot {
            throw GitHubError.unauthenticated
        }

        func snapshot(
            base _: GitHubRepositorySnapshot,
            paths _: [GitHubRepositoryPath],
            maximumFileBytes _: Int,
        ) throws -> GitHubRepositorySnapshot {
            throw GitHubError.unauthenticated
        }

        func ciStatus(
            repository _: GitHubRepository,
            commit _: GitHubObjectID,
        ) throws -> GitHubCIStatus {
            throw GitHubError.unauthenticated
        }

        func publish(_: GitHubPullRequestProposal) throws
            -> GitHubPublishedPullRequest
        {
            throw GitHubError.unauthenticated
        }
    }
#endif
