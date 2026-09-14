#if DEBUG && canImport(UIKit)
    import Foundation
    @_spi(Testing) import PortholeGitHub
    import SwiftUI

    /// Exercises the real publication model with a validated in-memory review and synthetic
    /// remotes.
    struct PortholeGitHubWorkspaceSnapshotSurface: View {
        enum Phase { case uncertain, published }
        let phase: Phase
        @State private var model: Result<PortholeGitHubPresentationModel, any Error>?

        var body: some View {
            NavigationStack {
                switch model {
                    case nil: ProgressView("Preparing synthetic workspace…")
                    case let .success(model): PortholeGitHubView(model: model)
                    case let .failure(error): Text(
                            "Snapshot setup failed: \(error.localizedDescription)",
                        )
                }
            }
            .portholeBroadwayRoot()
            .task {
                guard model == nil else { return }
                do {
                    let prepared = try await makeModel()
                    try Task.checkCancellation()
                    model = .success(prepared)
                } catch is CancellationError {
                    return
                } catch {
                    model = .failure(error)
                }
            }
        }

        @MainActor private func makeModel() async throws -> PortholeGitHubPresentationModel {
            let repository = try GitHubRepository(owner: "example", name: "Example")
            let path = try GitHubRepositoryPath("Sources/FlightDetector.swift")
            let base = try GitHubRepositorySnapshot(
                repository: repository,
                branch: "main",
                commit: GitHubObjectID(String(repeating: "a", count: 40)),
                tree: GitHubObjectID(String(repeating: "b", count: 40)),
                knownPaths: [path],
                files: [.init(path: path, text: "let minimumSamples = 4\n", mode: .regular)],
            )
            let source = GitHubInstalledSource(
                buildIdentity: "synthetic-installed-build",
                isDirty: true,
                files: [.init(path: path, text: "let minimumSamples = 6\n", mode: .regular)],
            )
            var workspace = GitHubSourceWorkspace(installedSource: source, repositoryBase: base)
            try workspace.setText("let minimumSamples = 5\n", at: path, mode: .regular)
            try workspace.setText(
                """
                import Testing
                @testable import Example

                @Test func requiresFiveSamples() {
                    #expect(4 < minimumSamples)
                    #expect(5 >= minimumSamples)
                }

                """,
                at: GitHubRepositoryPath("Tests/FlightDetectorTests.swift"),
                mode: .regular,
            )
            let account = GitHubAccount(userID: 123, login: "example-developer")
            let proposal = try GitHubPullRequestProposal(
                proposalID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                workspace: workspace,
                title: "Check the flight sample threshold",
                body: "Synthetic fixture only. Add a regression test for a five-sample candidate and inspect the endpoint attribution.",
                evidence: .synthetic,
                author: account,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            )
            let result = try GitHubPublishedPullRequest(
                number: 42,
                url: URL(string: "https://github.com/example/Example/pull/42")!,
                commit: GitHubObjectID(String(repeating: "c", count: 40)),
            )
            let services = PortholeGitHubWorkspaceSnapshotServices(
                identity: account,
                base: base,
                result: result,
                phase: phase,
            )
            let store = try GitHubWorkspaceStore(workspace: workspace, review: .prepared(proposal))
            let model = PortholeGitHubPresentationModel(
                authentication: services,
                repository: services,
                publisher: services,
                workspaceStore: store,
                installedSource: source,
                initialRepository: repository,
                initialBranch: base.branch,
                initialPaths: [path],
            )
            await model.restore()
            model.title = proposal.title
            model.pullRequestBody = proposal.body
            model.editorPath = path.rawValue
            model.openFile()
            await model.publish(proposal)
            guard model.editor != nil else { throw GitHubError.missingBaseFile }
            switch phase {
                case .uncertain:
                    guard model.requiresPublicationReconciliation, !model.canEditWorkspace else {
                        throw GitHubError.publicationReconciliationRequired
                    }
                case .published:
                    guard case .published = model.snapshot?.review,
                          case .loaded = model.ciState else { throw GitHubError.invalidResponse }
            }
            return model
        }
    }

    private struct PortholeGitHubWorkspaceSnapshotServices: GitHubAuthenticating,
        GitHubRepositoryReading, GitHubPublishing
    {
        let identity: GitHubAccount
        let base: GitHubRepositorySnapshot
        let result: GitHubPublishedPullRequest
        let phase: PortholeGitHubWorkspaceSnapshotSurface.Phase

        func begin(at _: Date) throws -> GitHubDeviceFlow.Authorization {
            throw GitHubError.authorizationDenied
        }

        func poll(at _: Date) throws -> GitHubDeviceFlow.PollResult {
            throw GitHubError.noAuthorization
        }

        func cancel() {}
        func signOut() {}
        func account() -> GitHubAccount {
            identity
        }

        func snapshot(
            repository _: GitHubRepository,
            branch _: String,
            paths _: [GitHubRepositoryPath],
            maximumFileBytes _: Int,
        ) -> GitHubRepositorySnapshot {
            base
        }

        func snapshot(
            base: GitHubRepositorySnapshot,
            paths _: [GitHubRepositoryPath],
            maximumFileBytes _: Int,
        ) -> GitHubRepositorySnapshot {
            base
        }

        func ciStatus(repository _: GitHubRepository, commit: GitHubObjectID) -> GitHubCIStatus {
            GitHubCIStatus(commit: commit, checks: [
                .init(name: "Synthetic iOS build", state: .passed, detailsURL: nil),
                .init(name: "Synthetic regression tests", state: .failed, detailsURL: nil),
            ])
        }

        func publish(_: GitHubPullRequestProposal) throws -> GitHubPublishedPullRequest {
            switch phase {
                case .uncertain: throw GitHubError.publicationUncertain(.pullRequest)
                case .published: return result
            }
        }
    }
#endif
