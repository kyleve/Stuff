import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Bounded guided review from either an issue-list entry or admitted notification references.
/// Closing keeps committed choices; skipped and newly arriving work remains in the issue list.
struct RecordingReviewFlowView: View {
    @State var model: RecordingReviewFlowModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationStack {
            Group {
                if let page = model.page {
                    RecordingChoiceView(model: page.choice, completion: .saveAndContinue)
                        .id(page.id)
                        .disabled(!model.canReview)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            RecordingFlowStatus(model: model)
                                .padding(stylesheet.spacing.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.regularMaterial)
                        }
                } else {
                    summary
                        .navigationTitle(String(localized: .recordingReviewTitle))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .commonDone)) { dismiss() }
                        .accessibilityIdentifier("where_recording_close")
                }
                if let page = model.page {
                    ToolbarItem(placement: .bottomBar) {
                        Button(String(localized: .recordingFlowSkip)) { model.skipCurrent() }
                            .disabled(page.choice.isBusy || !model.canReview)
                            .accessibilityIdentifier("where_recording_skip")
                    }
                }
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.observeChanges() }
        }
        .onDisappear { model.deactivate() }
    }

    @ViewBuilder
    private var summary: some View {
        switch model.state {
            case .idle, .refreshing:
                ProgressView(String(localized: .recordingFlowReassessing))
            case .failed:
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                } description: {
                    Text(String(localized: .recordingFlowFailedDetail))
                } actions: {
                    Button(String(localized: .commonRetry)) { Task { await model.refresh() } }
                }
            case let .pending(progress):
                ContentUnavailableView {
                    Label(String(localized: .recordingFlowSkippedTitle), systemSymbol: .pauseCircle)
                } description: {
                    Text(String(localized: .recordingFlowSkippedDetail(progress.remaining.count)))
                } actions: {
                    Button(String(localized: .recordingFlowReviewRemaining)) {
                        Task { await model.reviewRemaining() }
                    }
                    .accessibilityIdentifier("where_recording_resume")
                }
            case .resolved:
                ContentUnavailableView {
                    Label(
                        String(localized: .recordingFlowResolvedTitle),
                        systemSymbol: .checkmarkCircle,
                    )
                    .accessibilityIdentifier("where_recording_complete")
                } description: {
                    Text(String(localized: .recordingFlowResolvedDetail))
                }
        }
    }
}

private struct RecordingFlowStatus: View {
    let model: RecordingReviewFlowModel

    var body: some View {
        VStack(alignment: .leading) {
            if let progress = model.state.progress {
                Text(String(localized: .recordingFlowRemaining(
                    progress.remaining.count,
                    progress.skipped.count,
                )))
            }
            switch model.state {
                case .idle, .pending, .resolved: EmptyView()
                case .refreshing: ProgressView(String(localized: .recordingFlowReassessing))
                case .failed:
                    Label(
                        String(localized: .recordingFlowFailedDetail),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                    Button(String(localized: .commonRetry)) { Task { await model.refresh() } }
            }
        }
    }
}

#if DEBUG
    extension RecordingReviewFlowView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for skipped in [false, true] {
                let fixture = RecordingReviewPreviewFixture(scenario: .browsing)
                whereSnapshot(
                    name: skipped ? "Skipped" : "Remaining",
                    configurations: skipped ? .fullContentPhoneLightDark :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: { await fixture.prepareFlow(skipped: skipped) },
                    onReadyToSnapshot: { await fixture.prepareFlow(skipped: skipped) },
                ) {
                    RecordingReviewPreview(fixture: fixture) { fixture in
                        if let flow = fixture.flow {
                            RecordingReviewFlowView(model: flow).id(flow.id)
                        }
                    }
                }
            }
        }
    }

    #Preview { RecordingReviewFlowView.snapshotPreviews }

    extension RecordingReviewFlowView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingReviewFlowView.self,
            title: "Guided recording review",
            navigationContainer: .none,
            routes: [.modal(to: RecordingScopeEditor.flyoverID)],
        )
    }
#endif
