import SwiftUI
import WhereCore

/// A sheet showing an on-device, AI-generated summary of a selectable look-back
/// window of tracked locations (24 hours, a week, a month, or the year so far).
/// Presented from the Primary tab. A segmented control at the top picks the
/// window; each `RecentActivityModel.LoadState` renders distinctly — a real
/// summary (streamed in with a typewriter reveal), an empty window, an
/// unavailable model (with guidance), or a failure — and a refresh regenerates.
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
                .safeAreaInset(edge: .top) { windowPicker }
                .animation(.smooth, value: model.loadState)
                .navigationTitle(Strings.recentActivityTitle(model.window))
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
                // Regenerate for the newly picked window. The picker is disabled
                // while loading (see `windowPicker`), so this can't fire a second
                // load over an in-flight one.
                .onChange(of: model.window) {
                    Task { await model.load() }
                }
        }
    }

    /// Segmented control for the summary window, pinned under the navigation
    /// bar. Bound straight to the observable `window`; the `.onChange` above
    /// turns a change into a reload. Disabled while a summary is generating so
    /// selections can't race an in-flight load.
    private var windowPicker: some View {
        Picker(Strings.recentActivityWindowPickerLabel, selection: $model.window) {
            ForEach(RecentActivityWindow.allCases, id: \.self) { window in
                Text(Strings.recentActivityWindowLabel(window)).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.loadState == .loading)
        .padding(.horizontal)
        .padding(.vertical, UIConstants.Spacings.medium)
        .background(.bar)
    }

    /// Each state fades into the next (see `.animation` in `body`) rather than
    /// hard-cutting — a crossfade suits swapping between a spinner, prose, and a
    /// `ContentUnavailableView`.
    @ViewBuilder
    private var content: some View {
        switch model.loadState {
            case .idle, .loading:
                AppIconLoadingView(caption: Strings.recentActivityLoading)
                    .transition(.opacity)
            case let .loaded(text):
                summary(text)
                    .transition(.opacity)
            case .empty:
                ContentUnavailableView {
                    Label(Strings.recentActivityEmptyTitle, systemImage: "location.slash")
                } description: {
                    Text(Strings.recentActivityEmptyDescription(model.window))
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
                TypewriterText(text: text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Strings.recentActivityFooter(model.window))
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

    #Preview("Loading") {
        RecentActivitySummaryView(model: PreviewSupport.recentActivityModel(state: .loading))
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
