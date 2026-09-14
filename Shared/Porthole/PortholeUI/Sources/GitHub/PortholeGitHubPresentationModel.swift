import Foundation
import Observation
import PortholeGitHub

/// The phone edits an isolated workspace. This native controller alone can publish its saved
/// review.
@MainActor @Observable
public final class PortholeGitHubPresentationModel {
    enum AuthenticationState {
        case signedOut
        case starting(UUID)
        case awaiting(UUID, GitHubDeviceFlow.Authorization)
        case cancelling(UUID)
        case signedIn(GitHubAccount)
        case failed(String)
    }

    enum WorkspaceState {
        case empty
        case loading(UUID, GitHubWorkspaceSnapshot?)
        case ready(GitHubWorkspaceSnapshot)
        case failed(String, GitHubWorkspaceSnapshot?)
    }

    enum PublicationState {
        case idle
        case publishing(UUID)
        case published(GitHubPublishedPullRequest)
        case failed(String)
    }

    enum CIState { case idle, loading, loaded(GitHubCIStatus), failed(String) }
    struct Editor {
        let path: GitHubRepositoryPath
        let revision: UUID
        let mode: GitHubTextFileMode
        var text: String
    }

    private struct AuthenticationTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct PersonalEvidenceApproval {
        let proposalID: UUID
        let fingerprint: String
    }

    public let workspaceStore: GitHubWorkspaceStore
    private let authentication: any GitHubAuthenticating
    private let repository: any GitHubRepositoryReading
    private let publisher: any GitHubPublishing
    private let installedSource: GitHubInstalledSource
    private var setupClient: GitHubConfigurableClient?
    @ObservationIgnored private var authenticationTask: AuthenticationTask?
    private var personalEvidenceApproval: PersonalEvidenceApproval?
    private(set) var authenticationState: AuthenticationState = .signedOut
    @ObservationIgnored private var workspacePresentationID = UUID()
    private(set) var workspaceState: WorkspaceState = .empty {
        didSet { workspacePresentationID = UUID() }
    }

    private(set) var publicationState: PublicationState = .idle
    private struct CIReview: Equatable {
        let proposalID: UUID
        let fingerprint: String
        let commit: GitHubObjectID

        init(proposal: GitHubPullRequestProposal, result: GitHubPublishedPullRequest) throws {
            proposalID = proposal.proposalID
            fingerprint = try proposal.fingerprint
            commit = result.commit
        }
    }

    private struct CIOperation {
        enum State { case loading, loaded(GitHubCIStatus), failed(String) }
        let id: UUID
        let review: CIReview
        var state: State
    }

    private var ciOperation: CIOperation?
    var ciState: CIState {
        switch ciOperation?.state {
            case .none: .idle
            case .loading: .loading
            case let .loaded(status): .loaded(status)
            case let .failed(message): .failed(message)
        }
    }

    var comparisonPath: GitHubRepositoryPath? {
        didSet {
            guard oldValue != comparisonPath else { return }
            refreshSourceComparison()
        }
    }

    private(set) var sourceComparison: PortholeGitHubSourceComparison?

    var requiresPublicationReconciliation: Bool {
        if case .publicationUncertain = snapshot?.review { return true }
        return false
    }

    var canEditWorkspace: Bool {
        !isBusy && !requiresPublicationReconciliation && snapshot?.isPublishing != true
    }

    var canRefreshRepositoryBase: Bool {
        guard canEditWorkspace, let snapshot, !snapshot.isPublishing,
              snapshot.workspace.patch.isEmpty else { return false }
        guard let editor else { return true }
        return editor.text == (snapshot.workspace.file(at: editor.path)?.text ?? "")
    }

    private(set) var editor: Editor?
    var owner: String
    var repositoryName: String
    var branch: String
    var paths: String
    var editorPath = ""
    var title = ""
    var pullRequestBody = ""
    var reviewEvidence: GitHubReviewEvidence = .synthetic
    var clientIDInput = ""
    var needsClientID: Bool {
        setupClient != nil
    }

    public init(
        authentication: any GitHubAuthenticating,
        repository: any GitHubRepositoryReading,
        publisher: any GitHubPublishing,
        workspaceStore: GitHubWorkspaceStore,
        installedSource: GitHubInstalledSource,
        initialRepository: GitHubRepository,
        initialBranch: String,
        initialPaths: [GitHubRepositoryPath],
    ) {
        self.authentication = authentication
        self.repository = repository
        self.publisher = publisher
        self.workspaceStore = workspaceStore
        self.installedSource = installedSource
        owner = initialRepository.owner
        repositoryName = initialRepository.name
        branch = initialBranch
        paths = initialPaths.map(\.rawValue).joined(separator: "\n")
    }

    var snapshot: GitHubWorkspaceSnapshot? {
        switch workspaceState {
            case .empty: nil
            case let .ready(snapshot): snapshot
            case let .loading(_, snapshot), let .failed(_, snapshot): snapshot
        }
    }

    func requireClientIDConfiguration(using client: GitHubConfigurableClient) {
        setupClient = client
    }

    func configureClientID() async {
        guard let setupClient else { return }
        do {
            try await setupClient
                .configure(clientID: GitHubClientID(clientIDInput
                        .trimmingCharacters(in: .whitespacesAndNewlines)))
            self.setupClient = nil
            await restore()
        } catch { authenticationState = .failed(error.localizedDescription); log(error) }
    }

    var isBusy: Bool {
        if case .loading = workspaceState { return true }
        if case .publishing = publicationState { return true }
        return false
    }

    var editorText: String {
        get { editor?.text ?? "" }
        set { editor?.text = newValue }
    }

    func restore() async {
        guard !needsClientID,
              authenticationOperationID == nil,
              authenticationTask == nil else { await refreshWorkspace(); return }
        do { authenticationState = try await .signedIn(repository.account()) }
        catch GitHubError.unauthenticated { authenticationState = .signedOut }
        catch { authenticationState = .failed(error.localizedDescription); log(error) }
        await refreshWorkspace()
    }

    func startSignIn() {
        guard !isBusy, authenticationTask == nil else { return }
        let operationID = UUID()
        authenticationState = .starting(operationID)
        let task = Task { [weak self] in
            await self?.signIn(operationID: operationID)
            guard let self, authenticationTask?.id == operationID else { return }
            if case .cancelling = authenticationState { return }
            authenticationTask = nil
        }
        authenticationTask = AuthenticationTask(id: operationID, task: task)
    }

    private func signIn(operationID: UUID) async {
        do {
            try Task.checkCancellation()
            var authorization = try await authentication.begin(at: Date())
            while true {
                try Task.checkCancellation()
                guard authenticationOperationID == operationID else { return }
                authenticationState = .awaiting(operationID, authorization)
                let delay = max(0, authorization.nextPollAt.timeIntervalSinceNow)
                try await Task.sleep(for: .seconds(delay))
                guard authenticationOperationID == operationID else { return }
                let result = try await authentication.poll(at: Date())
                guard authenticationOperationID == operationID else { return }
                switch result {
                    case let .waiting(next): authorization = next
                    case let .authorized(account): authenticationState = .signedIn(account); return
                }
            }
        } catch is CancellationError {
            if authenticationOperationID ==
                operationID { authenticationState = .signedOut; await authentication.cancel() }
        } catch {
            if authenticationOperationID ==
                operationID
            { authenticationState = .failed(error.localizedDescription); log(error)
            }
        }
    }

    func cancelSignIn() async {
        guard let operation = authenticationTask else { return }
        if case .cancelling = authenticationState { return }
        operation.task.cancel()
        authenticationState = .cancelling(operation.id)
        await authentication.cancel()
        guard authenticationTask?.id == operation.id else { return }
        authenticationTask = nil
        authenticationState = .signedOut
    }

    private var authenticationOperationID: UUID? {
        switch authenticationState {
            case let .starting(operationID), let .awaiting(operationID, _): operationID
            case .signedOut, .signedIn, .failed, .cancelling: nil
        }
    }

    func signOut() async {
        guard !isBusy else { return }
        do { try await authentication.signOut(); authenticationState = .signedOut }
        catch { authenticationState = .failed(error.localizedDescription); log(error) }
    }

    func refreshWorkspace() async {
        guard !isBusy else { return }
        do {
            if let loaded = try await workspaceStore.loadedSnapshot() { try accept(loaded) }
            else { workspaceState = .empty; ciOperation = nil; sourceComparison = nil }
        } catch { failWorkspace(error, previous: snapshot) }
    }

    func loadRepository() async {
        guard canEditWorkspace else { return }
        let previous = snapshot
        let operationID = UUID()
        workspaceState = .loading(operationID, previous)
        do {
            let repositoryID = try GitHubRepository(owner: owner, name: repositoryName)
            let selectedPaths = try paths.split(whereSeparator: \.isNewline)
                .map { try GitHubRepositoryPath(String($0).trimmingCharacters(in: .whitespaces)) }
            let base: GitHubRepositorySnapshot = if let captured = previous?.workspace
                .repositoryBase,
                captured.repository == repositoryID, captured.branch == branch
            {
                try await repository.snapshot(
                    base: captured,
                    paths: selectedPaths,
                    maximumFileBytes: 1024 * 1024,
                )
            } else {
                try await repository.snapshot(
                    repository: repositoryID,
                    branch: branch,
                    paths: selectedPaths,
                    maximumFileBytes: 1024 * 1024,
                )
            }
            try Task.checkCancellation()
            let loaded = try await workspaceStore.load(base: base, installedSource: installedSource)
            try accept(loaded)
            editor = nil
            publicationState = .idle
        } catch { failWorkspace(error, previous: previous) }
    }

    func refreshRepositoryBase() async {
        guard canRefreshRepositoryBase, let previous = snapshot else { return }
        let captured = previous.workspace.repositoryBase
        workspaceState = .loading(UUID(), previous)
        do {
            let base = try await repository.snapshot(
                repository: captured.repository,
                branch: captured.branch,
                paths: captured.files.map(\.path),
                maximumFileBytes: 1024 * 1024,
            )
            try Task.checkCancellation()
            let loaded = try await workspaceStore.load(base: base, installedSource: installedSource)
            try accept(loaded)
            if captured.commit != base.commit || captured.tree != base.tree {
                editor = nil
                publicationState = .idle
            } else if let editor,
                      loaded.workspace.file(at: editor.path) == previous.workspace
                      .file(at: editor.path)
            {
                self.editor = Editor(
                    path: editor.path,
                    revision: loaded.revision,
                    mode: editor.mode,
                    text: editor.text,
                )
            }
        } catch { failWorkspace(error, previous: previous) }
    }

    func openFile() {
        guard let snapshot, canEditWorkspace else { return }
        do {
            let path = try GitHubRepositoryPath(editorPath)
            let file = snapshot.workspace.file(at: path)
            guard file != nil || !snapshot.workspace.repositoryBase.knownPaths.contains(path)
            else { throw GitHubError.missingBaseFile }
            editor = Editor(
                path: path,
                revision: snapshot.revision,
                mode: file?.mode ?? .regular,
                text: file?.text ?? "",
            )
        } catch { failWorkspace(error, previous: snapshot) }
    }

    func saveFile() async {
        guard let editor, canEditWorkspace else { return }
        let previous = snapshot
        do {
            let saved = try await workspaceStore.setText(
                editor.text,
                at: editor.path,
                mode: editor.mode,
                expectedRevision: editor.revision,
            )
            try accept(saved)
            self.editor = Editor(
                path: editor.path,
                revision: saved.revision,
                mode: editor.mode,
                text: editor.text,
            )
            publicationState = .idle
        } catch { failWorkspace(error, previous: previous) }
    }

    func deleteFile() async {
        guard let editor, canEditWorkspace else { return }
        let previous = snapshot
        do {
            try await accept(workspaceStore.remove(
                at: editor.path,
                expectedRevision: editor.revision,
            ))
            self.editor = nil
            publicationState = .idle
        } catch { failWorkspace(error, previous: previous) }
    }

    func discardChanges() async {
        guard let snapshot, canEditWorkspace else { return }
        do {
            try await accept(workspaceStore.discardChanges(expectedRevision: snapshot.revision))
            editor = nil
            publicationState = .idle
        } catch { failWorkspace(error, previous: snapshot) }
    }

    func prepareReview() async {
        guard let snapshot, canEditWorkspace else { return }
        do {
            let account = try await repository.account()
            try await accept(workspaceStore.prepare(
                title: title,
                body: pullRequestBody,
                evidence: reviewEvidence,
                author: account,
                at: Date(),
                expectedRevision: snapshot.revision,
            ))
        } catch { failWorkspace(error, previous: snapshot) }
    }

    /// This method is called only by the explicit native publish button after the saved diff is
    /// shown.
    func publish(_ proposal: GitHubPullRequestProposal) async {
        guard !isBusy else { return }
        publicationState = .publishing(proposal.proposalID)
        do {
            if proposal.evidence == .personal {
                guard let approval = personalEvidenceApproval,
                      approval.proposalID == proposal.proposalID,
                      try approval.fingerprint == proposal.fingerprint
                else {
                    throw GitHubError.personalEvidenceApprovalRequired
                }
            }
            let approved = try await workspaceStore.beginPublication(
                proposalID: proposal.proposalID,
                fingerprint: proposal.fingerprint,
            )
            do {
                let result = try await publisher.publish(approved)
                try await accept(workspaceStore.finishPublication(
                    result,
                    proposalID: approved.proposalID,
                    fingerprint: approved.fingerprint,
                ))
                publicationState = .published(result)
                await refreshCI(proposal: approved, result: result)
            } catch {
                try await workspaceStore.publicationFailed(
                    proposalID: approved.proposalID,
                    fingerprint: approved.fingerprint,
                )
                try await accept(workspaceStore.snapshot())
                throw error
            }
        } catch {
            publicationState = .failed(error.localizedDescription)
            log(error)
        }
    }

    func personalEvidenceAllowed(for proposal: GitHubPullRequestProposal) -> Bool {
        personalEvidenceApproval?.proposalID == proposal.proposalID
    }

    func allowPersonalEvidence(_ allowed: Bool, for proposal: GitHubPullRequestProposal) {
        do {
            personalEvidenceApproval = try allowed ? PersonalEvidenceApproval(
                proposalID: proposal.proposalID,
                fingerprint: proposal.fingerprint,
            ) : nil
        } catch { publicationState = .failed(error.localizedDescription); log(error) }
    }

    func refreshCI(proposal: GitHubPullRequestProposal, result: GitHubPublishedPullRequest) async {
        let operationID = UUID()
        do {
            let review = try CIReview(proposal: proposal, result: result)
            let initialPresentationID = workspacePresentationID
            let current = try await workspaceStore.snapshot()
            guard workspacePresentationID == initialPresentationID else { return }
            try acceptCI(current)
            guard try publishedReview(in: current) == review else { return }
            ciOperation = CIOperation(id: operationID, review: review, state: .loading)
            let outcome: Result<GitHubCIStatus, any Error>
            do {
                let status = try await repository.ciStatus(
                    repository: proposal.base.repository,
                    commit: result.commit,
                )
                guard status.commit == review.commit else { throw GitHubError.invalidResponse }
                outcome = .success(status)
            } catch { outcome = .failure(error) }
            let latestPresentationID = workspacePresentationID
            let latest = try await workspaceStore.snapshot()
            guard ciOperation?.id == operationID else { return }
            guard workspacePresentationID == latestPresentationID else {
                ciOperation = nil
                return
            }
            try acceptCI(latest)
            guard ciOperation?.id == operationID else { return }
            switch outcome {
                case let .success(status): ciOperation?.state = .loaded(status)
                case let .failure(error):
                    ciOperation?.state = .failed(error.localizedDescription)
                    log(error)
            }
        } catch {
            if ciOperation?
                .id == operationID { ciOperation?.state = .failed(error.localizedDescription) }
            log(error)
        }
    }

    private func publishedReview(in snapshot: GitHubWorkspaceSnapshot) throws -> CIReview? {
        switch snapshot.review {
            case .unreviewed, .prepared, .publicationUncertain: nil
            case let .published(proposal, result): try CIReview(proposal: proposal, result: result)
        }
    }

    private func accept(_ snapshot: GitHubWorkspaceSnapshot) throws {
        workspaceState = .ready(snapshot)
        try refreshReviewEvidence(snapshot)
    }

    private func acceptCI(_ snapshot: GitHubWorkspaceSnapshot) throws {
        switch workspaceState {
            case let .loading(operationID, _): workspaceState = .loading(operationID, snapshot)
            case .empty, .ready, .failed: workspaceState = .ready(snapshot)
        }
        try refreshReviewEvidence(snapshot)
    }

    private func refreshReviewEvidence(_ snapshot: GitHubWorkspaceSnapshot) throws {
        let review = try publishedReview(in: snapshot)
        if ciOperation?.review != review { ciOperation = nil }
        let paths = snapshot.workspace.repositoryBase.files.map(\.path)
        let selected = comparisonPath.flatMap { paths.contains($0) ? $0 : nil } ?? paths.first
        if comparisonPath != selected { comparisonPath = selected }
        else { refreshSourceComparison() }
    }

    private func refreshSourceComparison() {
        guard let snapshot, let comparisonPath else { sourceComparison = nil; return }
        sourceComparison = PortholeGitHubSourceComparison(
            workspace: snapshot.workspace,
            path: comparisonPath,
        )
    }

    private func failWorkspace(_ error: any Error, previous: GitHubWorkspaceSnapshot?) {
        workspaceState = .failed(error.localizedDescription, previous)
        log(error)
    }

    private func log(_ error: any Error) {
        PortholeUILog.failures
            .error("GitHub workspace failed: \(error.localizedDescription, privacy: .private)")
    }
}
