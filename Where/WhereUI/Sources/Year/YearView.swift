import SnapshotKit
import SwiftUI
import WhereCore

/// Your Year tab: four lenses over the same selected-year report — Calendar,
/// Timeline, Breakdown, and Heatmap. The selected lens persists through the
/// injected preferences store; the activity summary stays in the toolbar.
struct YearView: View {
    let report: YearReportModel

    @State private var selection: YearModeSelection
    @State private var showingRecentActivity = false

    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, initialMode: YearViewMode? = nil) {
        self.report = report
        _selection = State(initialValue: YearModeSelection(
            preferences: report.preferences,
            initialMode: initialMode,
        ))
    }

    var body: some View {
        @Bindable var selection = selection

        NavigationStack {
            YearModeContent(report: report, mode: selection.mode)
                // Crossfade between lenses rather than hard-cutting.
                .animation(stylesheet.yearOverview.picker.contentAnimation, value: selection.mode)
                .navigationTitle(selection.mode.title)
                .navigationBarTitleDisplayMode(.inline)
                // Keep the bar background on at all times. The calendar auto-scrolls
                // under the bar (so its scroll-edge material is showing) while the
                // timeline starts at the top; without pinning it, switching between
                // them animates that material in/out — reading as a toolbar fade.
                .toolbarBackground(.visible, for: .navigationBar)
                .safeAreaInset(edge: .bottom, alignment: .center) {
                    YearModePicker(mode: $selection.mode)
                        .padding(.bottom, stylesheet.spacing.xLarge)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingRecentActivity = true
                        } label: {
                            Label(
                                String(localized: .primaryRecentActivity),
                                systemImage: "sparkles",
                            )
                        }
                        .accessibilityIdentifier("where_recent_activity_button")
                    }
                }
        }
        .sheet(isPresented: $showingRecentActivity) {
            RecentActivitySummaryView(report: report)
        }
    }
}

#if DEBUG
    extension YearView: SnapshotProviding {
        /// Timeline rendering is owned by `PresenceTimelineList`'s matrix; the
        /// initializer seam is used by Flyover without duplicating that suite.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Loaded",
                configurations: .screenDefaults,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                YearView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                YearView(report: PreviewSupport.emptyYearReportModel())
            }
        }
    }

    #Preview {
        YearView.snapshotPreviews
    }
#endif

#if DEBUG
    extension YearView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(
            YearView.self,
            routes: [
                .modal(to: RecentActivitySummaryView.flyoverID),
            ],
        ) { id, world in
            .init(
                id: id,
                title: "Your Year",
                navigationContainer: .none,
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "calendar",
                        title: "Calendar",
                        world: world,
                    ) {
                        YearView(report: world.report, initialMode: .calendar)
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "timeline",
                        title: "Timeline",
                        world: world,
                    ) {
                        YearView(report: world.report, initialMode: .timeline)
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "breakdown",
                        title: "Breakdown",
                        world: world,
                    ) {
                        YearView(report: world.report, initialMode: .breakdown)
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "heatmap",
                        title: "Heatmap",
                        world: world,
                    ) {
                        YearView(report: world.report, initialMode: .heatmap)
                    },
                ],
            )
        }
    }
#endif
