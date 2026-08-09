import PatchlightCore
import SwiftUI

struct PatchlightWorkspaceView: View {
    private enum Selection: Hashable, Identifiable {
        case overview
        case conversation
        case snapshots
        case file(String)

        var id: String {
            switch self {
                case .overview: "overview"
                case .conversation: "conversation"
                case .snapshots: "snapshots"
                case let .file(path): "file:\(path)"
            }
        }
    }

    private enum LayoutPreference: String, CaseIterable, Identifiable {
        case automatic
        case unified
        case split

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .automatic: String(localized: .automatic)
                case .unified: String(localized: .unified)
                case .split: String(localized: .split)
            }
        }
    }

    let content: PatchlightWorkspaceContent
    let model: PatchlightAppModel
    @State private var selection: Selection? = .overview
    @AppStorage("Patchlight.diffLayoutPreference") private var storedLayout = LayoutPreference
        .automatic.rawValue
    @AppStorage("Patchlight.explicitViewedOnly") private var explicitViewedOnly = false
    @AppStorage("Patchlight.reviewDepth") private var storedReviewDepth = ReviewDepth.balanced
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.globallyEnabled) private var globallyEnabled = false
    @AppStorage(PatchlightAIUserDefaults.provider) private var providerCode = AIProvider.openAI
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.preset) private var presetCode = AnalysisPreset.balanced
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.advancedModelID) private var advancedModelID = ""
    @State private var selectedDraftAnchor: DiffAnchor?
    @State private var selectedDraftInitialBody = ""
    @State private var reanchoringDraft: ReviewDraft?
    @State private var fileCommentPath: String?
    @State private var showsHiddenChanges = false
    @State private var showsReviewComposer = false
    @State private var showsAISettings = false

    private var workspace: PullRequestWorkspace {
        content.workspace
    }

    private var snapshotFiles: [DiffFile] {
        reviewFilePlans.filter(\.isSnapshot).map(\.file)
    }

    private var codeFiles: [DiffFile] {
        visibleCodePlans.map(\.file)
    }

    private var reviewDepth: ReviewDepth {
        ReviewDepth(rawValue: storedReviewDepth) ?? .balanced
    }

    private var reviewFilePlans: [FileReviewPlan] {
        model.reviewPlan?.files ?? workspace.files.map {
            FileReviewPlan(
                file: $0,
                minimumDepth: .critical,
                hunks: [],
                isSnapshot: $0.path.lowercased().hasSuffix(".png"),
            )
        }
    }

    private var visibleCodePlans: [FileReviewPlan] {
        reviewFilePlans.filter { !$0.isSnapshot && $0.minimumDepth <= reviewDepth }
    }

    private var hiddenCodePlans: [FileReviewPlan] {
        reviewFilePlans.filter { !$0.isSnapshot && $0.minimumDepth > reviewDepth }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label(String(localized: .overview), systemImage: "doc.text")
                        .tag(Selection.overview)
                    Label(
                        String(localized: .conversation),
                        systemImage: "bubble.left.and.bubble.right",
                    )
                    .tag(Selection.conversation)
                    Label(String(localized: .snapshots), systemImage: "photo.on.rectangle.angled")
                        .badge(snapshotFiles.count)
                        .tag(Selection.snapshots)
                }
                Section(String(localized: .files)) {
                    ForEach(visibleCodePlans) { plan in
                        fileRow(plan)
                    }
                }
                if !hiddenCodePlans.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showsHiddenChanges) {
                            ForEach(hiddenCodePlans) { plan in
                                fileRow(plan)
                            }
                        } label: {
                            Label(
                                String(localized: "hiddenChanges", defaultValue: "Hidden Changes"),
                                systemImage: "eye.slash",
                            )
                            .badge(hiddenCodePlans.count)
                        }
                    }
                }
            }
            .navigationTitle("#\(workspace.summary.id.number)")
            .navigationSplitViewColumnWidth(min: 260, ideal: 330, max: 440)
        } detail: {
            selectedDetail
                .navigationTitle(detailTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: .backToDashboard)) { model.closeWorkspace() }
                    }
                    if case .file = selection {
                        ToolbarItem(placement: .primaryAction) {
                            Picker(String(localized: .diffLayout), selection: $storedLayout) {
                                ForEach(LayoutPreference.allCases) { preference in
                                    Text(preference.title).tag(preference.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            Menu {
                                Toggle(
                                    String(
                                        localized: "explicitViewedOnly",
                                        defaultValue: "Mark Viewed Explicitly Only",
                                    ),
                                    isOn: $explicitViewedOnly,
                                )
                                if case let .file(path) = selection {
                                    Button(String(
                                        localized: "sendFileComment",
                                        defaultValue: "Send File Comment",
                                    )) {
                                        fileCommentPath = path
                                    }
                                    Button(String(
                                        localized: "markFileViewed",
                                        defaultValue: "Mark File Viewed",
                                    )) {
                                        Task {
                                            await model.markViewed(path: path, depth: reviewDepth)
                                        }
                                    }
                                }
                            } label: {
                                Label(
                                    String(
                                        localized: "viewedBehavior",
                                        defaultValue: "Viewed Behavior",
                                    ),
                                    systemImage: "eye",
                                )
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if canRunAnalysis {
                                Task {
                                    await model.runAnalysis(
                                        globallyEnabled: globallyEnabled,
                                        provider: selectedProvider,
                                        preset: selectedPreset,
                                        advancedModelID: advancedModelID,
                                    )
                                }
                            } else {
                                showsAISettings = true
                            }
                        } label: {
                            Label(
                                canRunAnalysis
                                    ? String(
                                        localized: "runAnalysis",
                                        defaultValue: "Run Analysis",
                                    )
                                    : String(
                                        localized: "configureAI",
                                        defaultValue: "Configure AI",
                                    ),
                                systemImage: "sparkles",
                            )
                        }
                        .disabled(isAnalysisRunning)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsReviewComposer = true
                        } label: {
                            Label(
                                String(localized: "submitReview", defaultValue: "Submit Review"),
                                systemImage: "checkmark.bubble",
                            )
                        }
                        .badge(model.reviewDrafts.count)
                    }
                }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                attentionControl
                if let warning = model.reviewPlan?.configurationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .patchlightWorkspaceStatus(color: .orange)
                }
                if !workspace.isFileListComplete {
                    Label(
                        String(localized: .fileListIncomplete),
                        systemImage: "exclamationmark.triangle",
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.14))
                } else if let reason = content.fallbackReason {
                    Label(reason.message, systemImage: "icloud.slash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.14))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                analysisStatus
                submissionStatus
            }
        }
        .sheet(isPresented: draftEditorPresented) {
            if let selectedDraftAnchor {
                PatchlightDraftEditor(
                    anchor: selectedDraftAnchor,
                    initialBody: selectedDraftInitialBody,
                    model: model,
                )
            }
        }
        .sheet(isPresented: $showsReviewComposer) {
            PatchlightReviewComposer(model: model)
        }
        .sheet(isPresented: fileCommentPresented) {
            if let fileCommentPath {
                PatchlightFileCommentComposer(path: fileCommentPath, model: model)
            }
        }
        .sheet(isPresented: $showsAISettings) {
            PatchlightAISettingsView(model: model)
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection ?? .overview {
            case .overview:
                overview
            case .conversation:
                PatchlightConversationView(model: model)
            case .snapshots:
                snapshots
            case let .file(path):
                if let file = reviewFilePlans.first(where: { $0.file.path == path })?.file {
                    fileDetail(file)
                } else {
                    ContentUnavailableView(
                        String(localized: .patchUnavailable),
                        systemImage: "doc.questionmark",
                    )
                }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(workspace.summary.title)
                    .font(.largeTitle.bold())
                HStack {
                    Label(workspace.summary.authorLogin, systemImage: "person")
                    Text(workspace.summary.repository.displayName)
                    if workspace.summary.isDraft {
                        Text(String(localized: .draft))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.14), in: .capsule)
                    }
                }
                .foregroundStyle(.secondary)
                if let body = workspace.bodyMarkdown, !body.isEmpty {
                    markdown(body)
                        .textSelection(.enabled)
                }
                Divider()
                analysisOverview
                LabeledContent(String(localized: .files), value: "\(workspace.files.count)")
                LabeledContent(
                    String(localized: .snapshots),
                    value: "\(snapshotFiles.count)",
                )
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var snapshots: some View {
        if snapshotFiles.isEmpty {
            ContentUnavailableView(
                String(localized: .noSnapshots),
                systemImage: "photo.on.rectangle",
            )
        } else {
            PatchlightSnapshotWorkspaceView(files: snapshotFiles, model: model)
        }
    }

    @ViewBuilder
    private func fileDetail(_ file: DiffFile) -> some View {
        switch file.availability {
            case .complete where !file.hunks.isEmpty:
                GeometryReader { proxy in
                    let preference = LayoutPreference(rawValue: storedLayout) ?? .automatic
                    let mode: DiffRendererMode = switch preference {
                        case .automatic: proxy.size.width >= 1000 ? .split : .unified
                        case .unified: .unified
                        case .split: .split
                    }
                    PatchlightDiffCollectionView(
                        file: file,
                        headOID: workspace.summary.headOID,
                        mode: mode,
                        threads: threads(for: file),
                        hunkPlans: filePlan(for: file)?.hunks ?? [],
                        reviewDepth: reviewDepth,
                        onSelectAnchor: { anchor in
                            if let draft = reanchoringDraft {
                                reanchoringDraft = nil
                                Task { await model.reanchorDraft(draft, to: anchor) }
                            } else {
                                selectedDraftInitialBody = ""
                                selectedDraftAnchor = anchor
                            }
                        },
                        onReachedEnd: {
                            guard !explicitViewedOnly else { return }
                            Task { await model.markViewed(path: file.path, depth: reviewDepth) }
                        },
                    )
                }
            case .complete:
                ContentUnavailableView(String(localized: .noTextChanges), systemImage: "equal")
            case let .unavailable(reason):
                unavailableFile(file, reason: reason)
            case .binary:
                unavailableFile(file, reason: String(localized: .binaryFile))
            case let .tooLarge(baseBytes, headBytes):
                unavailableFile(
                    file,
                    reason: String(
                        localized: .fileTooLargeForLocalDiff(baseBytes ?? 0, headBytes ?? 0),
                    ),
                )
            case .undecodable:
                unavailableFile(file, reason: String(localized: .undecodableFile))
        }
    }

    private func unavailableFile(_: DiffFile, reason: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: .patchUnavailable), systemImage: "doc.questionmark")
        } description: {
            Text(reason)
        } actions: {
            if let url = githubFilesURL {
                Link(String(localized: .openOnGitHub), destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var attentionControl: some View {
        HStack(spacing: 12) {
            Button {
                storedReviewDepth = max(ReviewDepth.critical.rawValue, storedReviewDepth - 1)
            } label: {
                Image(systemName: "minus")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(reviewDepth == .critical)
            Slider(
                value: Binding(
                    get: { Double(storedReviewDepth) },
                    set: { storedReviewDepth = Int($0.rounded()) },
                ),
                in: Double(ReviewDepth.critical.rawValue) ...
                    Double(ReviewDepth.everything.rawValue),
                step: 1,
            )
            .accessibilityLabel(String(localized: "reviewDepth", defaultValue: "Review Depth"))
            .accessibilityValue(reviewDepthTitle)
            Text(reviewDepthTitle)
                .font(.headline)
                .frame(minWidth: 92, alignment: .leading)
            Button {
                storedReviewDepth = min(ReviewDepth.everything.rawValue, storedReviewDepth + 1)
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(reviewDepth == .everything)
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var reviewDepthTitle: String {
        switch reviewDepth {
            case .critical: String(localized: "critical", defaultValue: "Critical")
            case .focused: String(localized: "focused", defaultValue: "Focused")
            case .balanced: String(localized: "balanced", defaultValue: "Balanced")
            case .thorough: String(localized: "thorough", defaultValue: "Thorough")
            case .everything: String(localized: "everything", defaultValue: "Everything")
        }
    }

    private func fileRow(_ plan: FileReviewPlan) -> some View {
        Label {
            HStack {
                Text(plan.file.path)
                    .lineLimit(1)
                if model.hasUnreadRevealedChanges(path: plan.file.path, at: reviewDepth) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(String(
                            localized: "unreadAtDepth",
                            defaultValue: "Unread at this depth",
                        ))
                }
                if plan.hunks.contains(where: \.assessment.isPartial) {
                    Text(String(localized: "partialAnalysis", defaultValue: "Partial"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(
                            localized: "partialAnalysisBadge",
                            defaultValue: "Partial analysis",
                        ))
                }
                Spacer()
                Text("+\(plan.file.additions) −\(plan.file.deletions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol(for: plan.file.status))
        }
        .tag(Selection.file(plan.file.path))
        .contextMenu {
            Button(String(localized: "alwaysShow", defaultValue: "Always Show")) {
                Task {
                    await model.setCorrection(.alwaysShow, path: plan.file.path, hunkID: nil)
                }
            }
            Button(String(localized: "markMechanical", defaultValue: "Mark Mechanical")) {
                Task {
                    await model.setCorrection(.mechanical, path: plan.file.path, hunkID: nil)
                }
            }
            Button(String(localized: "clearCorrection", defaultValue: "Clear Correction")) {
                Task { await model.clearCorrection(path: plan.file.path, hunkID: nil) }
            }
            if plan.file.path.lowercased().hasSuffix(".png") {
                Button(String(localized: "moveToSnapshots", defaultValue: "Move to Snapshots")) {
                    Task { await model.moveToSnapshots(path: plan.file.path) }
                }
            }
        }
    }

    private func filePlan(for file: DiffFile) -> FileReviewPlan? {
        reviewFilePlans.first { $0.file.path == file.path }
    }

    @ViewBuilder
    private var analysisOverview: some View {
        if case let .ready(run) = model.analysisState {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(run.analysis.summary)
                        .textSelection(.enabled)
                    Divider()
                    LabeledContent(
                        String(localized: "providerAndModel", defaultValue: "Provider / Model"),
                        value: "\(providerTitle(run.provider)) / \(run.modelID)",
                    )
                    if run.isCacheHit {
                        Label(
                            String(
                                localized: "cachedAnalysis",
                                defaultValue: "Encrypted Cache Hit",
                            ),
                            systemImage: "externaldrive.badge.checkmark",
                        )
                        .foregroundStyle(.secondary)
                    }
                    analysisUsage(run.analysis.usage)
                    let findings = run.analysis.hunks.flatMap(\.findings)
                    if !findings.isEmpty {
                        Divider()
                        Text(String(localized: "aiFindings", defaultValue: "AI Findings"))
                            .font(.headline)
                        ForEach(findings) { finding in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(finding.title).font(.headline)
                                    Text(finding.body).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let draft = suggestedDraft(for: finding) {
                                    Button(String(
                                        localized: "createDraft",
                                        defaultValue: "Create Draft",
                                    )) {
                                        selectedDraftInitialBody = draft.body
                                        selectedDraftAnchor = draft.anchor
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(
                    String(localized: "analysis", defaultValue: "Analysis"),
                    systemImage: "sparkles",
                )
            }
        }
    }

    @ViewBuilder
    private func analysisUsage(_ usage: AnalysisUsage) -> some View {
        if let promptTokens = usage.promptTokens {
            LabeledContent(
                String(localized: "promptTokens", defaultValue: "Prompt Tokens"),
                value: promptTokens.formatted(),
            )
        }
        if let cachedTokens = usage.cachedPromptTokens {
            LabeledContent(
                String(localized: "cachedPromptTokens", defaultValue: "Cached Prompt Tokens"),
                value: cachedTokens.formatted(),
            )
        }
        if let outputTokens = usage.outputTokens {
            LabeledContent(
                String(localized: "outputTokens", defaultValue: "Output Tokens"),
                value: outputTokens.formatted(),
            )
        }
        if let reasoningTokens = usage.reasoningTokens {
            LabeledContent(
                String(localized: "reasoningTokens", defaultValue: "Reasoning Tokens"),
                value: reasoningTokens.formatted(),
            )
        }
        LabeledContent(
            String(localized: "providerCalls", defaultValue: "Provider Calls"),
            value: usage.providerCalls.formatted(),
        )
        LabeledContent(
            String(localized: "toolContext", defaultValue: "Tool Context"),
            value: String(
                format: String(
                    localized: "toolContextFormat",
                    defaultValue: "%1$lld calls, %2$lld files, %3$@",
                ),
                locale: .current,
                usage.toolCalls,
                usage.filesRetrieved,
                ByteCountFormatter.string(
                    fromByteCount: Int64(usage.bytesRetrieved),
                    countStyle: .file,
                ),
            ),
        )
        LabeledContent(
            String(localized: "duration", defaultValue: "Duration"),
            value: Duration.milliseconds(usage.durationMilliseconds)
                .formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)),
        )
        if let requestID = usage.requestID {
            LabeledContent(
                String(localized: "requestID", defaultValue: "Request ID"),
                value: requestID,
            )
        }
    }

    @ViewBuilder
    private var analysisStatus: some View {
        switch model.analysisState {
            case .idle:
                EmptyView()
            case .running:
                HStack {
                    ProgressView()
                    Text(String(localized: "analyzingReview", defaultValue: "Analyzing review…"))
                }
                .patchlightWorkspaceStatus(color: .blue)
            case let .ready(run):
                Label(
                    run.isCacheHit
                        ? String(
                            localized: "loadedCachedAnalysis",
                            defaultValue: "Loaded cached analysis",
                        )
                        : String(localized: "analysisComplete", defaultValue: "Analysis complete"),
                    systemImage: run.isCacheHit ? "externaldrive.badge.checkmark" : "sparkles",
                )
                .patchlightWorkspaceStatus(color: .green)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .patchlightWorkspaceStatus(color: .red)
        }
    }

    private func suggestedDraft(for finding: AIReviewFinding) -> SuggestedAnalysisDraft? {
        guard let filePlan = reviewFilePlans.first(where: { plan in
            plan.hunks.contains { $0.id == finding.hunkID }
        }),
            let hunk = filePlan.hunks.first(where: { $0.id == finding.hunkID })?.hunk
        else { return nil }
        let lineIndex = finding.line.flatMap { line in
            hunk.lines.firstIndex {
                switch finding.side {
                    case .base: $0.oldLine == line
                    case .head: $0.newLine == line
                    case nil: false
                }
            }
        }
        let line = lineIndex.map { hunk.lines[$0] }
        let side = finding.side ?? .head
        let anchor = DiffAnchor(
            path: filePlan.file.path,
            side: side,
            commitOID: workspace.summary.headOID,
            blobOID: side == .base ? filePlan.file.baseBlobOID : filePlan.file.headBlobOID,
            line: side == .base ? line?.oldLine : line?.newLine,
            startLine: nil,
            contextFingerprint: lineIndex.map {
                DraftAnchorMapper.fingerprint(lineIndex: $0, in: hunk.lines)
            } ?? hunk.id.rawValue,
        )
        return SuggestedAnalysisDraft(
            anchor: anchor,
            body: "\(finding.title)\n\n\(finding.body)",
        )
    }

    private func providerTitle(_ provider: AIProvider) -> String {
        switch provider {
            case .openAI: "OpenAI"
            case .anthropic: "Anthropic"
        }
    }

    @ViewBuilder
    private var submissionStatus: some View {
        switch model.submissionState {
            case .idle:
                EmptyView()
            case .submitting:
                HStack {
                    ProgressView()
                    Text(String(localized: "submittingReview", defaultValue: "Submitting review…"))
                }
                .patchlightWorkspaceStatus(color: .blue)
            case let .sent(reconciled):
                Label(
                    reconciled
                        ? String(
                            localized: "reconciledSubmission",
                            defaultValue: "GitHub confirmed the review after reconciliation.",
                        )
                        : String(localized: "reviewSubmitted", defaultValue: "Review submitted."),
                    systemImage: "checkmark.circle",
                )
                .patchlightWorkspaceStatus(color: .green)
            case let .uncertain(requestID):
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        requestID.map { "Submission status is uncertain (request \($0))." }
                            ?? String(
                                localized: "reviewUncertain",
                                defaultValue: "Submission status is uncertain.",
                            ),
                        systemImage: "questionmark.circle",
                    )
                    Text(String(
                        localized: "uncertainNoRetry",
                        defaultValue: "Patchlight did not retry. Refresh and reconcile before submitting again.",
                    ))
                    .font(.caption)
                    Button(String(localized: .refresh)) { Task { await model.refreshReview() } }
                }
                .patchlightWorkspaceStatus(color: .orange)
            case let .staleHead(results):
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        String(
                            localized: "headChanged",
                            defaultValue: "The pull request head changed. Draft submission is frozen.",
                        ),
                        systemImage: "arrow.triangle.2.circlepath",
                    )
                    Text(staleSummary(results))
                        .font(.caption)
                    HStack {
                        Button(String(
                            localized: "applyUniqueMatches",
                            defaultValue: "Apply Unique Matches",
                        )) {
                            Task { await model.applyUniqueDraftRemappings() }
                        }
                        .buttonStyle(.borderedProminent)
                        ForEach(unresolvedDrafts(results)) { result in
                            Button(String(localized: "reanchor", defaultValue: "Re-anchor")) {
                                reanchoringDraft = result.draft
                            }
                            Button(String(
                                localized: "convertToFileLevel",
                                defaultValue: "Convert to File Level",
                            )) {
                                Task { await model.convertDraftToFileLevel(result.draft) }
                            }
                            Button(
                                String(localized: "discard", defaultValue: "Discard"),
                                role: .destructive,
                            ) {
                                Task { await model.removeDraft(result.draft.id) }
                            }
                            .accessibilityLabel(String(
                                format: String(
                                    localized: "discardDraftFormat",
                                    defaultValue: "Discard %1$@",
                                ),
                                locale: .current,
                                result.draft.anchor?.path ?? String(
                                    localized: "draft",
                                    defaultValue: "Draft",
                                ),
                            ))
                        }
                    }
                }
                .patchlightWorkspaceStatus(color: .orange)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .patchlightWorkspaceStatus(color: .red)
        }
    }

    private func staleSummary(_ results: [DraftAnchorMapper.Result]) -> String {
        let remapped = results.count(where: {
            if case .remapped = $0.resolution { true } else { false }
        })
        let unresolved = results.count - remapped
        return "\(remapped) uniquely matched; \(unresolved) require re-anchoring, file-level conversion, or discard."
    }

    private func unresolvedDrafts(
        _ results: [DraftAnchorMapper.Result],
    ) -> [DraftAnchorMapper.Result] {
        results.filter {
            switch $0.resolution {
                case .ambiguous, .deleted: true
                case .current, .remapped: false
            }
        }
    }

    private func threads(for file: DiffFile) -> [ReviewThread] {
        model.conversationRead?.value.threads.filter { $0.path == file.path } ?? []
    }

    private var draftEditorPresented: Binding<Bool> {
        Binding(
            get: { selectedDraftAnchor != nil },
            set: {
                if !$0 {
                    selectedDraftAnchor = nil
                    selectedDraftInitialBody = ""
                }
            },
        )
    }

    private var fileCommentPresented: Binding<Bool> {
        Binding(
            get: { fileCommentPath != nil },
            set: { if !$0 { fileCommentPath = nil } },
        )
    }

    private func markdown(_ source: String) -> Text {
        do {
            return try Text(AttributedString(markdown: source))
        } catch {
            return Text(source)
        }
    }

    private var detailTitle: String {
        switch selection ?? .overview {
            case .overview: String(localized: .overview)
            case .conversation: String(localized: .conversation)
            case .snapshots: String(localized: .snapshots)
            case let .file(path): path
        }
    }

    private var selectedProvider: AIProvider {
        PatchlightAIUserDefaults.provider(from: providerCode)
    }

    private var selectedPreset: AnalysisPreset {
        PatchlightAIUserDefaults.preset(from: presetCode)
    }

    private var canRunAnalysis: Bool {
        globallyEnabled &&
            model.repositorySettings?.aiEnabled == true &&
            model.configuredProviders.contains(selectedProvider) &&
            (selectedPreset != .advanced || !advancedModelID
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var isAnalysisRunning: Bool {
        if case .running = model.analysisState { true } else { false }
    }

    private var githubFilesURL: URL? {
        URL(
            string: "https://github.com/\(workspace.summary.repository.displayName)/pull/\(workspace.summary.id.number)/files",
        )
    }

    private func symbol(for status: DiffFileStatus) -> String {
        switch status {
            case .added: "plus.square"
            case .modified, .changed: "pencil"
            case .removed: "minus.square"
            case .renamed: "arrow.right.square"
            case .copied: "doc.on.doc"
        }
    }
}

private struct SuggestedAnalysisDraft {
    let anchor: DiffAnchor
    let body: String
}

extension View {
    fileprivate func patchlightWorkspaceStatus(color: Color) -> some View {
        padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12))
    }
}
