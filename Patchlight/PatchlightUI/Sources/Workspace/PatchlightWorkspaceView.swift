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
    @State private var selectedDraftAnchor: DiffAnchor?
    @State private var reanchoringDraft: ReviewDraft?
    @State private var fileCommentPath: String?
    @State private var showsReviewComposer = false

    private var workspace: PullRequestWorkspace {
        content.workspace
    }

    private var snapshotFiles: [DiffFile] {
        workspace.files.filter { $0.path.lowercased().hasSuffix(".png") }
    }

    private var codeFiles: [DiffFile] {
        workspace.files.filter { !$0.path.lowercased().hasSuffix(".png") }
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
                    ForEach(codeFiles) { file in
                        Label {
                            HStack {
                                Text(file.path)
                                    .lineLimit(1)
                                Spacer()
                                Text("+\(file.additions) −\(file.deletions)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: symbol(for: file.status))
                        }
                        .tag(Selection.file(file.path))
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
                                            await model.markViewed(path: path, depth: .everything)
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
        .safeAreaInset(edge: .bottom) { submissionStatus }
        .sheet(isPresented: draftEditorPresented) {
            if let selectedDraftAnchor {
                PatchlightDraftEditor(anchor: selectedDraftAnchor, model: model)
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
                if let file = codeFiles.first(where: { $0.path == path }) {
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
            List(snapshotFiles) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.path)
                    Text("+\(file.additions) −\(file.deletions)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
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
                        onSelectAnchor: { anchor in
                            if let draft = reanchoringDraft {
                                reanchoringDraft = nil
                                Task { await model.reanchorDraft(draft, to: anchor) }
                            } else {
                                selectedDraftAnchor = anchor
                            }
                        },
                        onReachedEnd: {
                            guard !explicitViewedOnly else { return }
                            Task { await model.markViewed(path: file.path, depth: .everything) }
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
                            .accessibilityLabel("Discard \(result.draft.anchor?.path ?? "draft")")
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
            set: { if !$0 { selectedDraftAnchor = nil } },
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

extension View {
    fileprivate func patchlightWorkspaceStatus(color: Color) -> some View {
        padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12))
    }
}
