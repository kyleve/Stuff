import PeriscopeCore
import SFSafeSymbols
import SnapshotKit
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
    @Environment(\.stylesheet) private var stylesheet

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
                .navigationTitle(WhereFormat.recentActivityTitle(model.window))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .commonDone)) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { await model.load() }
                        } label: {
                            Label(
                                String(localized: .recentActivityRefresh),
                                systemSymbol: .arrowClockwise,
                            )
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
        // Log View Mode: reveal an inspect badge for recent-activity summary
        // events. A no-op in release.
        .debugLogInspectable(WhereLog.recentActivity(RecentActivityModelLog.self))
    }

    /// Segmented control for the summary window, pinned under the navigation
    /// bar. Bound straight to the observable `window`; the `.onChange` above
    /// turns a change into a reload. Disabled while a summary is generating so
    /// selections can't race an in-flight load.
    private var windowPicker: some View {
        Picker(String(localized: .recentActivityWindowPickerLabel), selection: $model.window) {
            ForEach(RecentActivityWindow.allCases, id: \.self) { window in
                Text(WhereFormat.recentActivityWindowLabel(window)).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.loadState == .loading)
        .padding(.horizontal)
        .padding(.vertical, stylesheet.spacing.medium)
        .background(.bar)
    }

    /// Each state fades into the next (see `.animation` in `body`) rather than
    /// hard-cutting — a crossfade suits swapping between a spinner, prose, and a
    /// `ContentUnavailableView`.
    @ViewBuilder
    private var content: some View {
        switch model.loadState {
            case .idle, .loading:
                AppIconLoadingView(caption: String(localized: .recentActivityLoading))
                    .transition(.opacity)
            case let .loaded(text):
                summary(text)
                    .transition(.opacity)
            case .empty:
                ContentUnavailableView {
                    Label(
                        String(localized: .recentActivityEmptyTitle),
                        systemSymbol: .locationSlash,
                    )
                } description: {
                    Text(WhereFormat.recentActivityEmptyDescription(model.window))
                }
                .transition(.opacity)
            case let .unavailable(reason):
                ContentUnavailableView {
                    Label(
                        String(localized: .recentActivityUnavailableTitle),
                        systemSymbol: .sparkles,
                    )
                } description: {
                    Text(WhereFormat.recentActivityUnavailableMessage(reason))
                }
                .transition(.opacity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        String(localized: .recentActivityFailedTitle),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                } description: {
                    Text(message)
                }
                .transition(.opacity)
        }
    }

    private func summary(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                TypewriterText(text: text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(WhereFormat.recentActivityFooter(model.window))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#if DEBUG
    extension RecentActivitySummaryView: SnapshotProviding {
        /// Capture the full settled scroll content; fixed viewport coverage is
        /// reserved for non-scrolling subjects.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .fullContentScreenDefaults) {
                RecentActivitySummaryView(
                    model: PreviewSupport.recentActivityModel(
                        state: .loaded("You were in California, then New York."),
                    ),
                )
            }
            whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                RecentActivitySummaryView(model: PreviewSupport.recentActivityModel(state: .empty))
            }
            whereSnapshot(name: "Unavailable", configurations: .phoneLightDark) {
                RecentActivitySummaryView(
                    model: PreviewSupport.recentActivityModel(
                        state: .unavailable(.appleIntelligenceNotEnabled),
                    ),
                )
            }
            whereSnapshot(name: "Failed", configurations: .phoneLightDark) {
                RecentActivitySummaryView(
                    model: PreviewSupport
                        .recentActivityModel(state: .failed("Something went wrong.")),
                )
            }
        }
    }

    #Preview {
        RecentActivitySummaryView.snapshotPreviews
    }
#endif

#if DEBUG
    extension RecentActivitySummaryView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecentActivitySummaryView.self,
            title: "Recent Activity",
        )
    }
#endif
