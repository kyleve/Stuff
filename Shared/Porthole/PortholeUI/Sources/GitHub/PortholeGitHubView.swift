import PortholeGitHub
import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

public struct PortholeGitHubView: View {
    @Bindable private var model: PortholeGitHubPresentationModel
    @Environment(\.portholeStylesheet) private var stylesheet

    public init(model: PortholeGitHubPresentationModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if model.needsClientID {
                Section("GitHub App setup") {
                    Text(
                        "Enter the public client ID for a GitHub App with device authorization enabled. The client ID is not a client secret.",
                    )
                    TextField("GitHub App client ID", text: $model.clientIDInput)
                    Button("Save client ID") { Task { await model.configureClientID() } }
                        .disabled(model.clientIDInput.isEmpty)
                }
            }
            authentication.disabled(model.isBusy)
            Section("Repository workspace") {
                TextField("Owner", text: $model.owner)
                TextField("Repository", text: $model.repositoryName)
                TextField("Base branch", text: $model.branch)
                TextField("Files to load, one path per line", text: $model.paths, axis: .vertical)
                Button("Load repository source") { Task { await model.loadRepository() } }
                    .disabled(!model.canEditWorkspace || model.needsClientID)
                if model.snapshot != nil {
                    Button("Refresh base from branch") {
                        Task { await model.refreshRepositoryBase() }
                    }
                    .disabled(!model.canRefreshRepositoryBase || model.needsClientID)
                    Text(
                        "To refresh the base, discard the saved patch and any unsaved editor changes. Reconcile any pending publication first.",
                    )
                    .foregroundStyle(.secondary)
                }
                Button("Refresh workspace") { Task { await model.refreshWorkspace() } }
                    .disabled(model.isBusy)
                if case .loading = model
                    .workspaceState { ProgressView("Reading repository source…") }
                if case let .failed(message, _) = model.workspaceState { Label(
                    message,
                    systemSymbol: .exclamationmarkTriangle,
                ) }
            }
            if let snapshot = model.snapshot {
                Section("Source identity") {
                    LabeledContent(
                        "Repository commit",
                        value: snapshot.workspace.repositoryBase.commit.rawValue,
                    )
                    LabeledContent(
                        "Installed build",
                        value: snapshot.workspace.installedSource.buildIdentity,
                    )
                    if snapshot.workspace.installedSource.isDirty {
                        Text(
                            "The installed app includes local edits. The patch starts from repository source; installed edits enter it only through explicit workspace changes.",
                        )
                    }
                }
                Section("Installed source compared with repository base") {
                    Picker("File to compare", selection: $model.comparisonPath) {
                        Text("Select a file").tag(GitHubRepositoryPath?.none)
                        ForEach(snapshot.workspace.repositoryBase.files, id: \.path) { file in
                            Text(file.path.rawValue).tag(Optional(file.path))
                        }
                    }
                    if let comparison = model.sourceComparison {
                        PortholeGitHubSourceComparisonView(comparison: comparison)
                    }
                }
                Section("Edit source") {
                    ForEach(snapshot.workspace.repositoryBase.files, id: \.path) { file in
                        Button(file.path.rawValue) {
                            model.editorPath = file.path.rawValue; model.openFile()
                        }.disabled(!model.canEditWorkspace)
                    }
                    TextField("File path", text: $model.editorPath)
                    Button("Open file or create new file") { model.openFile() }
                        .disabled(!model.canEditWorkspace)
                    if let editor = model.editor {
                        Text(editor.path.rawValue).font(stylesheet.code.font)
                        TextEditor(text: $model.editorText).font(stylesheet.code.font)
                            .disabled(!model.canEditWorkspace)
                            .frame(minHeight: stylesheet.code.minimumHeight)
                            .accessibilityLabel("Repository source editor")
                        Button("Save to patch workspace") { Task { await model.saveFile() } }
                            .disabled(!model.canEditWorkspace)
                        Button("Delete from patch", role: .destructive) {
                            Task { await model.deleteFile() }
                        }.disabled(!model.canEditWorkspace)
                    }
                }
                Section("Prepare review") {
                    Picker("Regression evidence", selection: $model.reviewEvidence) {
                        Text("Synthetic examples only").tag(GitHubReviewEvidence.synthetic)
                        Text("Includes personal diagnostics").tag(GitHubReviewEvidence.personal)
                    }
                    Text(
                        "Use invented values in regression tests. Review the description and changed files for personal data before saving.",
                    )
                    TextField("Pull request title", text: $model.title)
                    TextField(
                        "Pull request description",
                        text: $model.pullRequestBody,
                        axis: .vertical,
                    )
                    Text("\(snapshot.workspace.patch.count) files changed")
                    Button("Prepare exact patch for review") { Task { await model.prepareReview() }
                    }
                    .disabled(snapshot.workspace.patch.isEmpty || model.title.isEmpty || !model
                        .canEditWorkspace)
                    Button("Discard local patch", role: .destructive) {
                        Task { await model.discardChanges() }
                    }.disabled(!model.canEditWorkspace)
                }
                switch snapshot.review {
                    case .unreviewed: EmptyView()
                    case let .prepared(proposal): review(proposal, published: nil)
                    case let .publicationUncertain(proposal): review(proposal, published: nil)
                    case let .published(proposal, result): review(proposal, published: result)
                }
            }
        }
        .navigationTitle("GitHub")
        .portholeBroadwayRoot()
        .task { await model.restore() }
        .onDisappear { Task { await model.cancelSignIn() } }
    }

    private var authentication: some View {
        Section("GitHub sign-in") {
            switch model.authenticationState {
                case .signedOut:
                    Button("Sign in to GitHub") { model.startSignIn() }
                        .disabled(model.needsClientID)
                case .starting: ProgressView("Requesting sign-in code…")
                case .cancelling: ProgressView("Cancelling sign-in…")
                case let .awaiting(_, authorization):
                    Text(authorization.userCode).font(.title.monospaced()).textSelection(.enabled)
                    Link("Open GitHub device sign-in", destination: authorization.verificationURL)
                    Text("Enter this code on GitHub. Waiting for authorization…")
                    Button("Cancel sign-in", role: .cancel) { Task { await model.cancelSignIn() } }
                case let .signedIn(account):
                    LabeledContent("Account", value: account.login)
                    Button("Sign out") { Task { await model.signOut() } }
                case let .failed(message):
                    Text(message)
                    Button("Sign in again") { model.startSignIn() }
            }
        }
    }

    private func review(
        _ proposal: GitHubPullRequestProposal,
        published: GitHubPublishedPullRequest?,
    ) -> some View {
        Section("Saved review") {
            Text(proposal.title).font(.headline)
            Text(proposal.body).textSelection(.enabled)
            Text(
                "\(proposal.base.repository.owner)/\(proposal.base.repository.name) · \(proposal.base.branch)",
            )
            Text(proposal.branch).font(stylesheet.code.font).textSelection(.enabled)
            PortholeGitHubDiffView(proposal: proposal)
            switch proposal.evidence {
                case .synthetic:
                    Text(
                        "Declared evidence: synthetic examples only. Verify that the description and patch contain no personal diagnostics.",
                    )
                case .personal:
                    Toggle(
                        "Allow personal diagnostics in this exact draft pull request",
                        isOn: Binding(
                            get: { model.personalEvidenceAllowed(for: proposal) },
                            set: { model.allowPersonalEvidence($0, for: proposal) },
                        ),
                    )
            }
            if let published {
                Link("Open pull request #\(published.number)", destination: published.url)
                Button("Refresh CI status") { Task { await model.refreshCI(
                    proposal: proposal,
                    result: published,
                ) } }
            } else {
                if model.requiresPublicationReconciliation {
                    Text(
                        "GitHub may already have created this branch or pull request. Reconcile this saved proposal before changing the workspace.",
                    )
                }
                Button(model
                    .requiresPublicationReconciliation ? "Reconcile this exact publication" :
                    "Publish this patch as a draft pull request")
                {
                    Task { await model.publish(proposal) }
                }.disabled(model.isBusy)
            }
            switch model.publicationState {
                case .idle, .published: EmptyView()
                case .publishing: ProgressView("Publishing the saved proposal…")
                case let .failed(message):
                    Text(message)
                    Text(
                        "Retry uses this same saved proposal and checks for an existing branch and pull request.",
                    )
                    .foregroundStyle(.secondary)
            }
            switch model.ciState {
                case .idle:
                    PortholeGitHubValidationNotice(phase: published != nil ? .published : model
                        .requiresPublicationReconciliation ? .uncertain : .unpublished)
                case .loading: ProgressView("Reading CI status…")
                case let .failed(message): Text(message)
                case let .loaded(status):
                    Text("CI: \(String(describing: status.state))")
                    LabeledContent("CI commit", value: status.commit.rawValue)
                    ForEach(status.checks.indices, id: \.self) { index in
                        let check = status.checks[index]
                        if let url = check.detailsURL { Link(
                            "\(check.name): \(String(describing: check.state))",
                            destination: url,
                        ) } else { Text("\(check.name): \(String(describing: check.state))") }
                    }
            }
        }
    }
}

#if DEBUG && canImport(UIKit)
    #Preview { PortholeGitHubView.snapshotPreviews }
#endif

#if canImport(UIKit)
    extension PortholeGitHubView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(name: "Workspace setup", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    PortholeGitHubView(model: PortholeGitHubSnapshotServices.makeModel())
                }
            }
            SnapshotCase(
                name: "Installed source comparison",
                configurations: .fullContentScreenDefaults,
            ) {
                NavigationStack {
                    Form {
                        Section("Installed source compared with repository base") {
                            PortholeGitHubSourceComparisonView(
                                comparison: PortholeGitHubSnapshotServices
                                    .comparison(),
                            )
                        }
                        Section("Validation") { PortholeGitHubValidationNotice(phase: .unpublished)
                        }
                    }
                    .navigationTitle("GitHub")
                    .portholeBroadwayRoot()
                }
            }
            #if DEBUG
                SnapshotCase(
                    name: "Reconcile locked workspace",
                    configurations: workspaceSnapshotConfigurations,
                    settle: .settledAtLeast(minDuration: 1),
                ) {
                    PortholeGitHubWorkspaceSnapshotSurface(phase: .uncertain)
                }
                SnapshotCase(
                    name: "Published diff and CI",
                    configurations: workspaceSnapshotConfigurations,
                    settle: .settledAtLeast(minDuration: 1),
                ) {
                    PortholeGitHubWorkspaceSnapshotSurface(phase: .published)
                }
            #endif
            SnapshotCase(
                name: "Uncertain publication validation",
                configurations: .fullContentScreenDefaults,
            ) {
                NavigationStack {
                    Form {
                        Section("Validation") { PortholeGitHubValidationNotice(phase: .uncertain) }
                    }
                    .navigationTitle("GitHub")
                    .portholeBroadwayRoot()
                }
            }
        }

        #if DEBUG
            private static var workspaceSnapshotConfigurations: [SnapshotConfiguration] {
                SnapshotConfiguration.combinations(
                    devices: [.iPhoneFullContent],
                    colorSchemes: [.light, .dark],
                ) + [.init(dynamicType: .accessibility5, device: .iPhoneFullContent)]
            }
        #endif
    }
#endif

private struct PortholeGitHubDiffView: View {
    let proposal: GitHubPullRequestProposal
    @State private var diff: Result<String, any Error>?
    @Environment(\.portholeStylesheet) private var stylesheet
    var body: some View {
        Group {
            switch diff {
                case .none: ProgressView("Preparing diff…")
                case let .success(text): Text(text).font(stylesheet.code.font)
                .textSelection(.enabled)
                case let .failure(error): Text(error.localizedDescription)
            }
        }
        .task(id: proposal.proposalID) { diff = Result { try proposal.diff } }
    }
}

private struct PortholeGitHubSourceComparisonView: View {
    let comparison: PortholeGitHubSourceComparison
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        Text(
            "Removed lines are from the installed app. Added lines are from the fixed repository base. These differences do not enter the patch automatically.",
        )
        .foregroundStyle(.secondary)
        switch comparison.state {
            case .identical: Text("The installed source matches the repository base.")
            case let .different(diff): Text(diff).font(stylesheet.code.font).textSelection(.enabled)
            case let .unavailable(message), let .failed(message): Text(message)
        }
    }
}

private struct PortholeGitHubValidationNotice: View {
    enum Phase { case unpublished, uncertain, published }
    let phase: Phase

    var body: some View {
        switch phase {
            case .published: Text("CI status has not been fetched for this published commit.")
            case .uncertain: Text(
                    "Validation is not confirmed. Reconcile the publication to identify its commit and read CI results.",
                )
            case .unpublished: Text(
                    "Validation: not run for this saved proposal. Porthole has no compiler or test results for it. Review proposed regression tests in the diff. CI runs after draft publication when the repository is configured for it.",
                )
        }
    }
}
