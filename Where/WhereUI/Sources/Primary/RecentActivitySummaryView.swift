import SwiftUI
import WhereCore

/// A sheet showing an on-device, AI-generated summary of the last 24 hours of
/// tracked locations. Presented from the Primary tab. Renders each
/// `RecentActivityModel.LoadState` distinctly — a real summary, an empty
/// window, an unavailable model (with guidance), or a failure — and offers a
/// refresh.
struct RecentActivitySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: RecentActivityModel

    init(report: YearReportModel) {
        _model = State(initialValue: RecentActivityModel(services: report.services))
    }

    #if DEBUG
        /// Preview seam: inject a model already in a chosen state.
        init(model: RecentActivityModel) {
            _model = State(initialValue: model)
        }
    #endif

    var body: some View {
        NavigationStack {
            content
                .animation(.smooth, value: model.loadState)
                .navigationTitle(Strings.recentActivityTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.commonDone) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { await model.load() }
                        } label: {
                            Label(Strings.recentActivityRefresh, systemImage: "arrow.clockwise")
                        }
                        .disabled(model.loadState == .loading)
                    }
                }
                .task {
                    if model.loadState == .idle { await model.load() }
                }
        }
    }

    /// Each state fades into the next (see `.animation` in `body`) rather than
    /// hard-cutting — a crossfade suits swapping between a spinner, prose, and a
    /// `ContentUnavailableView`.
    @ViewBuilder
    private var content: some View {
        switch model.loadState {
            case .idle, .loading:
                ProgressView(Strings.recentActivityLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            case let .loaded(text):
                summary(text)
                    .transition(.opacity)
            case .empty:
                ContentUnavailableView {
                    Label(Strings.recentActivityEmptyTitle, systemImage: "location.slash")
                } description: {
                    Text(Strings.recentActivityEmptyDescription)
                }
                .transition(.opacity)
            case let .unavailable(reason):
                ContentUnavailableView {
                    Label(Strings.recentActivityUnavailableTitle, systemImage: "sparkles.slash")
                } description: {
                    Text(Strings.recentActivityUnavailableMessage(reason))
                }
                .transition(.opacity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        Strings.recentActivityFailedTitle,
                        systemImage: "exclamationmark.triangle",
                    )
                } description: {
                    Text(message)
                }
                .transition(.opacity)
        }
    }

    private func summary(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIConstants.Spacings.medium) {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Strings.recentActivityFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#if DEBUG
    #Preview("Loaded") {
        RecentActivitySummaryView(
            model: PreviewSupport.recentActivityModel(
                state: .loaded(
                    "You spent the morning in California near San Francisco, then traveled to New York in the early evening, where the most recent readings place you.",
                ),
            ),
        )
    }

    #Preview("Empty") {
        RecentActivitySummaryView(model: PreviewSupport.recentActivityModel(state: .empty))
    }

    #Preview("Unavailable") {
        RecentActivitySummaryView(
            model: PreviewSupport.recentActivityModel(
                state: .unavailable(.appleIntelligenceNotEnabled),
            ),
        )
    }
#endif
