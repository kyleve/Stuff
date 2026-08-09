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

    init(
        workspace: PullRequestWorkspace,
        source: CachedReadSource,
        refreshedAt: Date,
        fallbackReason: ReadFallbackReason?,
    ) {
        self.workspace = workspace
        self.source = source
        self.refreshedAt = refreshedAt
        self.fallbackReason = fallbackReason
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

    public enum ReviewState {
        case none
        case loading
        case ready(ConversationRead, drafts: [ReviewDraft])
        case failed(cached: ConversationRead?, drafts: [ReviewDraft], message: String)
    }

    public enum SubmissionState {
        case idle
        case submitting
        case sent(reconciledAfterUncertainResponse: Bool)
        case uncertain(requestID: String?)
        case staleHead([DraftAnchorMapper.Result])
        case failed(String)
    }

    public enum ImmediateWriteState {
        case idle
        case sending
        case sent(reconciledAfterUncertainResponse: Bool)
        case uncertain(requestID: String?)
        case failed(String)
    }

    public enum SnapshotState {
        case none
        case loading(String)
        case ready(SnapshotImagePair)
        case failed(String, message: String)
    }

    public enum AnalysisState {
        case idle
        case running
        case ready(ReviewAnalysisRun)
        case failed(String)
    }

    public enum ImageAnalysisState {
        case idle
        case running(String)
        case ready(SnapshotImageAnalysisRun)
        case failed(String)
    }

    public private(set) var accountState: AccountState = .signedOut
    public private(set) var workspaceState: WorkspaceState = .none
    public private(set) var repositoryState: RepositoryState = .none
    public private(set) var reviewState: ReviewState = .none
    public private(set) var submissionState: SubmissionState = .idle
    public private(set) var immediateWriteState: ImmediateWriteState = .idle
    public private(set) var reviewPlan: DeterministicReviewPlan?
    public private(set) var repositorySettings: PatchlightRepositorySettings?
    public private(set) var corrections: [ReviewCorrection] = []
    public private(set) var viewedDepths: [ViewedFileDepth] = []
    public private(set) var snapshotState: SnapshotState = .none
    public private(set) var analysisState: AnalysisState = .idle
    public private(set) var imageAnalysisState: ImageAnalysisState = .idle
    public private(set) var configuredProviders = Set<AIProvider>()
    public private(set) var providerCredentialError: String?

    @ObservationIgnored private let dependencies: PatchlightApplicationDependencies
    @ObservationIgnored private let credentials: GitHubCredentialManager
    @ObservationIgnored private let providerCredentials: ProviderCredentialManager
    @ObservationIgnored private let github: GitHubAPIClient
    @ObservationIgnored private var world: AccountWorld?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var imageAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var deterministicReviewPlan: DeterministicReviewPlan?

    public init(dependencies: PatchlightApplicationDependencies) {
        self.dependencies = dependencies
        let credentials = GitHubCredentialManager(
            configuration: dependencies.githubConfiguration,
            credentials: dependencies.credentialStore,
            transport: dependencies.transport,
        )
        self.credentials = credentials
        providerCredentials = ProviderCredentialManager(store: dependencies.credentialStore)
        github = GitHubAPIClient(credentials: credentials, transport: dependencies.transport)
    }

    public func restore() async {
        await refreshProviderCredentialStatus()
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

    public func signOut() async {
        guard let world else { return }
        cancelAIWork()
        do {
            try await world.scope.signOut { [credentials] in
                try await credentials.removeCredentials()
            }
            self.world = nil
            accountState = .signedOut
            workspaceState = .none
            repositoryState = .none
            reviewState = .none
            submissionState = .idle
            immediateWriteState = .idle
            reviewPlan = nil
            repositorySettings = nil
            corrections = []
            viewedDepths = []
            snapshotState = .none
            analysisState = .idle
            imageAnalysisState = .idle
            deterministicReviewPlan = nil
        } catch {
            accountState = .failed(previous: dashboardContent, message: error.localizedDescription)
        }
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
            await refreshReview()
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
        cancelAIWork()
        workspaceState = .none
        reviewState = .none
        submissionState = .idle
        immediateWriteState = .idle
        reviewPlan = nil
        repositorySettings = nil
        corrections = []
        viewedDepths = []
        snapshotState = .none
        analysisState = .idle
        imageAnalysisState = .idle
        deterministicReviewPlan = nil
        if let world {
            Task { await world.snapshots.finishWorkspace() }
        }
    }

    public func refreshWorkspace() async {
        guard let summary = workspaceSummary, let world else { return }
        do {
            let read = try await world.reads.workspace(for: summary.id)
            if read.value.summary.headOID != summary.headOID {
                cancelAIWork()
            }
            workspaceState = .ready(PatchlightWorkspaceContent(read))
            await refreshReview()
        } catch {
            workspaceState = .failed(summary, message: error.localizedDescription)
        }
    }

    public func refreshReview() async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        let previous = conversationRead
        let existingDrafts = reviewDrafts
        reviewState = .loading
        do {
            async let conversation = world.reviews.conversation(
                for: PullRequestRoute(summary: workspace.summary),
            )
            async let drafts = world.reviews.drafts(for: workspace.summary.id)
            reviewState = try await .ready(conversation, drafts: drafts)
            await refreshPolicy()
        } catch {
            reviewState = .failed(
                cached: previous,
                drafts: existingDrafts,
                message: error.localizedDescription,
            )
        }
    }

    public func refreshPolicy() async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        do {
            async let loadedCorrections = world.scope.accountStore.corrections(
                for: workspace.summary.id,
                headOID: workspace.summary.headOID,
            )
            async let loadedSettings = world.scope.accountStore.repositorySettings(
                for: workspace.summary.id.repository,
            )
            async let loadedViewedDepths = world.reviews.viewedDepths(
                for: workspace.summary.id,
            )
            let (corrections, settings, viewedDepths) = try await (
                loadedCorrections,
                loadedSettings,
                loadedViewedDepths,
            )
            self.corrections = corrections
            self.viewedDepths = viewedDepths
            repositorySettings = settings
            let deterministic = DeterministicReviewAnalyzer.analyze(
                workspace: workspace,
                localRules: settings.overrides.review,
                localSnapshotRules: settings.overrides.snapshots,
                manualSnapshotPaths: settings.overrides.manualSnapshotPaths,
                threadPaths: Set(conversationRead?.value.threads.map(\.path) ?? []),
                draftPaths: Set(reviewDrafts.compactMap { $0.anchor?.path }),
                corrections: corrections,
            )
            deterministicReviewPlan = deterministic
            switch analysisState {
                case let .ready(run) where run.headOID == workspace.summary.headOID:
                    reviewPlan = AIReviewMerger.merge(
                        deterministic: deterministic,
                        analysis: run.analysis,
                        allowHiding: workspace.isFileListComplete,
                    )
                case .running:
                    reviewPlan = deterministic
                case .ready:
                    analysisState = .idle
                    reviewPlan = deterministic
                case .idle, .failed:
                    reviewPlan = deterministic
            }
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func setCorrection(
        _ kind: ReviewCorrectionKind,
        path: String,
        hunkID: DiffHunk.ID?,
    ) async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        do {
            try await world.scope.accountStore.removeCorrections(
                for: workspace.summary.id,
                headOID: workspace.summary.headOID,
                path: path,
                hunkID: hunkID,
            )
            try await world.scope.accountStore.saveCorrection(ReviewCorrection(
                id: UUID(),
                pullRequest: workspace.summary.id,
                headOID: workspace.summary.headOID,
                path: path,
                hunkID: hunkID,
                kind: kind,
            ))
            await refreshPolicy()
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func clearCorrection(path: String, hunkID: DiffHunk.ID?) async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        do {
            try await world.scope.accountStore.removeCorrections(
                for: workspace.summary.id,
                headOID: workspace.summary.headOID,
                path: path,
                hunkID: hunkID,
            )
            await refreshPolicy()
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func moveToSnapshots(path: String) async {
        guard let workspace = workspaceContent?.workspace,
              let world,
              let current = repositorySettings
        else { return }
        var paths = current.overrides.manualSnapshotPaths
        paths.insert(path)
        let settings = PatchlightRepositorySettings(
            repository: workspace.summary.id.repository,
            aiEnabled: current.aiEnabled,
            imageAIEnabled: current.imageAIEnabled,
            overrides: PatchlightLocalRepositoryOverrides(
                review: current.overrides.review,
                snapshots: current.overrides.snapshots,
                manualSnapshotPaths: paths,
            ),
        )
        do {
            try await world.scope.accountStore.saveRepositorySettings(settings)
            repositorySettings = settings
            await refreshPolicy()
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func loadSnapshot(_ file: DiffFile) async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        imageAnalysisTask?.cancel()
        imageAnalysisTask = nil
        snapshotState = .loading(file.path)
        imageAnalysisState = .idle
        do {
            snapshotState = try await .ready(world.snapshots.load(
                file: file,
                repository: workspace.summary.id.repository,
            ))
        } catch {
            snapshotState = .failed(file.path, message: error.localizedDescription)
        }
    }

    public func postSnapshotAnnotation(
        _ annotation: SnapshotAnnotationV1,
        body: String,
    ) async {
        do {
            let marker = try annotation.marker()
            let visible = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = visible.isEmpty ? marker : "\(visible)\n\n\(marker)"
            await postFileComment(combined, path: annotation.path)
        } catch {
            immediateWriteState = .failed(error.localizedDescription)
        }
    }

    public func refreshProviderCredentialStatus() async {
        do {
            var configured = Set<AIProvider>()
            for provider in AIProvider.allCases where try await providerCredentials
                .hasCredential(for: provider)
            {
                configured.insert(provider)
            }
            configuredProviders = configured
            providerCredentialError = nil
        } catch {
            providerCredentialError = error.localizedDescription
        }
    }

    public func saveProviderCredential(_ value: String, for provider: AIProvider) async {
        do {
            try await providerCredentials.set(ProviderAPIKey(value), for: provider)
            configuredProviders.insert(provider)
            providerCredentialError = nil
        } catch {
            providerCredentialError = error.localizedDescription
        }
    }

    public func removeProviderCredential(_ provider: AIProvider) async {
        do {
            try await providerCredentials.remove(provider)
            cancelAIWork()
            configuredProviders.remove(provider)
            providerCredentialError = nil
        } catch {
            providerCredentialError = error.localizedDescription
        }
    }

    public func setRepositoryAI(enabled: Bool, imageEnabled: Bool) async {
        guard let workspace = workspaceContent?.workspace,
              let world,
              let current = repositorySettings
        else { return }
        let settings = PatchlightRepositorySettings(
            repository: workspace.summary.id.repository,
            aiEnabled: enabled,
            imageAIEnabled: enabled && imageEnabled,
            overrides: current.overrides,
        )
        do {
            try await world.scope.accountStore.saveRepositorySettings(settings)
            repositorySettings = settings
            if !enabled {
                cancelAIWork()
            }
        } catch {
            providerCredentialError = error.localizedDescription
        }
    }

    public func runAnalysis(
        globallyEnabled: Bool,
        provider: AIProvider,
        preset: AnalysisPreset,
        advancedModelID: String?,
    ) async {
        guard let world,
              let workspace = workspaceContent?.workspace,
              let deterministicReviewPlan,
              let repositorySettings
        else { return }
        let configuration: ReviewAnalysisConfiguration
        do {
            configuration = try analysisConfiguration(
                globallyEnabled: globallyEnabled,
                provider: provider,
                preset: preset,
                advancedModelID: advancedModelID,
                workspace: workspace,
                settings: repositorySettings,
            )
        } catch {
            analysisState = .failed(error.localizedDescription)
            return
        }
        analysisState = .running
        analysisTask?.cancel()
        let task = Task { [weak self] in
            do {
                let run = try await world.analysis.analyze(
                    workspace: workspace,
                    deterministicPlan: deterministicReviewPlan,
                    configuration: configuration,
                )
                guard !Task.isCancelled else { throw CancellationError() }
                self?.applyAnalysis(run, workspace: workspace)
            } catch is CancellationError {
                self?.setAnalysisIdle()
            } catch {
                self?.setAnalysisFailure(error.localizedDescription)
            }
        }
        analysisTask = task
        let workID = await world.scope.work.register(task)
        await task.value
        await world.scope.work.finish(workID)
        analysisTask = nil
    }

    public func runImageAnalysis(
        globallyEnabled: Bool,
        provider: AIProvider,
        preset: AnalysisPreset,
        advancedModelID: String?,
    ) async {
        guard let world,
              let workspace = workspaceContent?.workspace,
              let repositorySettings,
              case let .ready(pair) = snapshotState
        else { return }
        let configuration: ReviewAnalysisConfiguration
        do {
            configuration = try analysisConfiguration(
                globallyEnabled: globallyEnabled,
                provider: provider,
                preset: preset,
                advancedModelID: advancedModelID,
                workspace: workspace,
                settings: repositorySettings,
            )
        } catch {
            imageAnalysisState = .failed(error.localizedDescription)
            return
        }
        imageAnalysisState = .running(pair.file.path)
        imageAnalysisTask?.cancel()
        let task = Task { [weak self] in
            do {
                let run = try await world.analysis.analyzeImages(
                    pair: pair,
                    workspace: workspace,
                    configuration: configuration,
                )
                guard !Task.isCancelled else { throw CancellationError() }
                self?.applyImageAnalysis(run, pair: pair)
            } catch is CancellationError {
                self?.setImageAnalysisIdle()
            } catch {
                self?.setImageAnalysisFailure(error.localizedDescription)
            }
        }
        imageAnalysisTask = task
        let workID = await world.scope.work.register(task)
        await task.value
        await world.scope.work.finish(workID)
        imageAnalysisTask = nil
    }

    public func cancelAIWork() {
        analysisTask?.cancel()
        imageAnalysisTask?.cancel()
        analysisTask = nil
        imageAnalysisTask = nil
        analysisState = .idle
        imageAnalysisState = .idle
        reviewPlan = deterministicReviewPlan
    }

    public func saveDraft(anchor: DiffAnchor, body: String, id: UUID = UUID()) async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        do {
            try await world.reviews.saveDraft(ReviewDraft(
                id: id,
                pullRequest: workspace.summary.id,
                anchor: anchor,
                body: body,
                updatedAt: Date(),
            ))
            await refreshReview()
        } catch {
            reviewState = .failed(
                cached: conversationRead,
                drafts: reviewDrafts,
                message: error.localizedDescription,
            )
        }
    }

    public func removeDraft(_ id: UUID) async {
        guard let world else { return }
        do {
            try await world.reviews.removeDraft(id)
            await refreshReview()
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func submitReview(event: ReviewEvent, summary: String?) async {
        guard let workspace = workspaceContent?.workspace,
              let world,
              let viewerLogin
        else { return }
        submissionState = .submitting
        do {
            switch try await world.reviews.submit(
                workspace: workspace,
                event: event,
                summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                viewerLogin: viewerLogin,
            ) {
                case let .submitted(_, reconciled):
                    submissionState = .sent(reconciledAfterUncertainResponse: reconciled)
                    await refreshReview()
                case let .uncertain(requestID):
                    submissionState = .uncertain(requestID: requestID)
                case let .staleHead(freshWorkspace, mappings):
                    workspaceState = .ready(PatchlightWorkspaceContent(
                        workspace: freshWorkspace,
                        source: .live,
                        refreshedAt: Date(),
                        fallbackReason: nil,
                    ))
                    submissionState = .staleHead(mappings)
                    await refreshReview()
            }
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func applyUniqueDraftRemappings() async {
        guard case let .staleHead(results) = submissionState, let world else { return }
        do {
            try await world.reviews.applyUniqueRemappings(results)
            let unresolved = results.filter {
                switch $0.resolution {
                    case .ambiguous, .deleted: true
                    case .current, .remapped: false
                }
            }
            submissionState = unresolved.isEmpty ? .idle : .staleHead(unresolved)
            await refreshReview()
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func reanchorDraft(_ draft: ReviewDraft, to anchor: DiffAnchor) async {
        guard let world else { return }
        do {
            try await world.reviews.saveDraft(ReviewDraft(
                id: draft.id,
                pullRequest: draft.pullRequest,
                anchor: anchor,
                body: draft.body,
                updatedAt: Date(),
            ))
            removeFromStaleState(draft.id)
            await refreshReview()
        } catch {
            submissionState = .failed(error.localizedDescription)
        }
    }

    public func convertDraftToFileLevel(_ draft: ReviewDraft) async {
        guard let workspace = workspaceContent?.workspace,
              let oldPath = draft.anchor?.path,
              let file = workspace.files.first(where: {
                  $0.path == oldPath || $0.previousPath == oldPath
              })
        else { return }
        await reanchorDraft(
            draft,
            to: DiffAnchor(
                path: file.path,
                side: .head,
                commitOID: workspace.summary.headOID,
                blobOID: file.headBlobOID,
                line: nil,
                startLine: nil,
                contextFingerprint: draft.anchor?.contextFingerprint ?? "file-level",
            ),
        )
    }

    public func postConversationComment(_ body: String) async {
        guard let workspace = workspaceContent?.workspace,
              let world,
              let viewerLogin
        else { return }
        immediateWriteState = .sending
        do {
            let outcome = try await world.reviews.postConversationComment(
                body,
                in: PullRequestRoute(summary: workspace.summary),
                viewerLogin: viewerLogin,
            )
            applyImmediateOutcome(outcome)
            await refreshReview()
        } catch {
            immediateWriteState = .failed(error.localizedDescription)
        }
    }

    public func postFileComment(_ body: String, path: String) async {
        guard let workspace = workspaceContent?.workspace,
              let world,
              let viewerLogin
        else { return }
        immediateWriteState = .sending
        do {
            let outcome = try await world.reviews.postFileComment(
                body,
                path: path,
                headOID: workspace.summary.headOID,
                in: PullRequestRoute(summary: workspace.summary),
                viewerLogin: viewerLogin,
            )
            applyImmediateOutcome(outcome)
            await refreshReview()
        } catch {
            immediateWriteState = .failed(error.localizedDescription)
        }
    }

    public func reply(to commentID: GitHubCommentID, body: String) async {
        guard let workspace = workspaceContent?.workspace,
              let world,
              let viewerLogin
        else { return }
        immediateWriteState = .sending
        do {
            let outcome = try await world.reviews.reply(
                to: commentID,
                body: body,
                in: PullRequestRoute(summary: workspace.summary),
                viewerLogin: viewerLogin,
            )
            applyImmediateOutcome(outcome)
            await refreshReview()
        } catch {
            immediateWriteState = .failed(error.localizedDescription)
        }
    }

    public func setThread(_ threadID: GitHubNodeID, resolved: Bool) async {
        guard let world else { return }
        immediateWriteState = .sending
        do {
            try await world.reviews.setThread(threadID, resolved: resolved)
            immediateWriteState = .sent(reconciledAfterUncertainResponse: false)
            await refreshReview()
        } catch let error as GitHubReviewWriteError {
            if case let .submissionStatusUncertain(requestID) = error {
                immediateWriteState = .uncertain(requestID: requestID)
            } else {
                immediateWriteState = .failed(error.localizedDescription)
            }
        } catch {
            immediateWriteState = .failed(error.localizedDescription)
        }
    }

    public func markViewed(path: String, depth: ReviewDepth) async {
        guard let workspace = workspaceContent?.workspace, let world else { return }
        do {
            try await world.reviews.markFile(
                path,
                at: depth,
                headOID: workspace.summary.headOID,
                in: PullRequestRoute(summary: workspace.summary),
            )
            await refreshPolicy()
        } catch {
            immediateWriteState = .failed(error.localizedDescription)
        }
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

    public var workspaceContent: PatchlightWorkspaceContent? {
        guard case let .ready(content) = workspaceState else { return nil }
        return content
    }

    public var conversationRead: ConversationRead? {
        switch reviewState {
            case let .ready(conversation, _), let .failed(.some(conversation), _, _):
                conversation
            case .none, .loading, .failed(.none, _, _):
                nil
        }
    }

    public var reviewDrafts: [ReviewDraft] {
        switch reviewState {
            case let .ready(_, drafts), let .failed(_, drafts, _):
                drafts
            case .none, .loading:
                []
        }
    }

    public var viewerLogin: String? {
        dashboardContent?.dashboard.viewer.login
    }

    public func canSubmit(_ event: ReviewEvent) -> Bool {
        guard let workspace = workspaceContent?.workspace else { return false }
        if event == .comment { return true }
        return workspace.summary.authorLogin
            .caseInsensitiveCompare(viewerLogin ?? "") != .orderedSame
    }

    public func hasUnreadRevealedChanges(path: String, at depth: ReviewDepth) -> Bool {
        guard let workspace = workspaceContent?.workspace else { return false }
        guard let viewed = viewedDepths.first(where: {
            $0.path == path && $0.headOID == workspace.summary.headOID
        }) else {
            return true
        }
        return viewed.depth < depth
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
        let reviewClient = GitHubReviewClient(
            credentials: credentials,
            transport: dependencies.transport,
        )
        world = AccountWorld(
            scope: scope,
            reads: GitHubReadCoordinator(github: github, cache: scope.readCache),
            reviews: PatchlightReviewCoordinator(
                github: github,
                discussion: reviewClient,
                writer: reviewClient,
                store: scope.accountStore,
            ),
            snapshots: SnapshotWorkspaceCoordinator(
                github: github,
                readCache: scope.readCache,
                contentCache: scope.cache,
            ),
            analysis: ReviewAnalysisCoordinator(
                accountID: viewer.id,
                github: github,
                store: scope.accountStore,
                credentials: providerCredentials,
                transport: dependencies.transport,
            ),
        )
    }

    private func analysisConfiguration(
        globallyEnabled: Bool,
        provider: AIProvider,
        preset: AnalysisPreset,
        advancedModelID: String?,
        workspace: PullRequestWorkspace,
        settings: PatchlightRepositorySettings,
    ) throws -> ReviewAnalysisConfiguration {
        try ReviewAnalysisConfiguration(
            globallyEnabled: globallyEnabled,
            repositoryEnabled: settings.aiEnabled,
            imageAnalysisEnabled: settings.imageAIEnabled,
            selection: AnalysisModelSelection(
                provider: provider,
                preset: preset,
                advancedModelID: advancedModelID,
            ),
            policyFingerprint: ReviewAnalysisCoordinator.policyFingerprint(
                workspace: workspace,
                settings: settings,
            ),
        )
    }

    private func applyAnalysis(
        _ run: ReviewAnalysisRun,
        workspace: PullRequestWorkspace,
    ) {
        guard workspaceContent?.workspace.summary.headOID == run.headOID,
              let deterministicReviewPlan
        else { return }
        analysisState = .ready(run)
        reviewPlan = AIReviewMerger.merge(
            deterministic: deterministicReviewPlan,
            analysis: run.analysis,
            allowHiding: workspace.isFileListComplete,
        )
    }

    private func setAnalysisIdle() {
        analysisState = .idle
        reviewPlan = deterministicReviewPlan
    }

    private func setAnalysisFailure(_ message: String) {
        analysisState = .failed(message)
        reviewPlan = deterministicReviewPlan
    }

    private func applyImageAnalysis(
        _ run: SnapshotImageAnalysisRun,
        pair: SnapshotImagePair,
    ) {
        guard case let .ready(current) = snapshotState,
              current.file.path == pair.file.path,
              current.base?.oid == run.baseOID,
              current.head?.oid == run.headOID
        else { return }
        imageAnalysisState = .ready(run)
    }

    private func setImageAnalysisIdle() {
        imageAnalysisState = .idle
    }

    private func setImageAnalysisFailure(_ message: String) {
        imageAnalysisState = .failed(message)
    }

    private var workspaceSummary: PullRequestSummary? {
        switch workspaceState {
            case let .loading(summary), let .failed(summary, _): summary
            case let .ready(content): content.workspace.summary
            case .none: nil
        }
    }

    private func applyImmediateOutcome(_ outcome: ImmediateWriteOutcome) {
        switch outcome {
            case let .submitted(_, reconciled):
                immediateWriteState = .sent(reconciledAfterUncertainResponse: reconciled)
            case let .uncertain(requestID):
                immediateWriteState = .uncertain(requestID: requestID)
        }
    }

    private func removeFromStaleState(_ draftID: UUID) {
        guard case let .staleHead(results) = submissionState else { return }
        let remaining = results.filter { $0.draft.id != draftID }
        submissionState = remaining.isEmpty ? .idle : .staleHead(remaining)
    }

    private struct AccountWorld {
        let scope: PatchlightScope
        let reads: GitHubReadCoordinator
        let reviews: PatchlightReviewCoordinator
        let snapshots: SnapshotWorkspaceCoordinator
        let analysis: ReviewAnalysisCoordinator
    }
}
