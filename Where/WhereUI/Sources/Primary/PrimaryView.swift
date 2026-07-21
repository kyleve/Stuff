import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    let report: YearReportModel

    @State private var showingTimeline = false
    @State private var showingCalendar = false
    @State private var showingRecentActivity = false
    @State private var showingEvidence = false
    @State private var showingLoggedDays = false
    @State private var calendarFocus: CalendarFocus?

    /// Drives the region cards' tilt-reactive holographic sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    @Environment(\.stylesheet) private var stylesheet

    /// Identifies which region's calendar to present as a sheet. `Region` isn't
    /// `Identifiable`, and `.sheet(item:)` needs identity.
    private struct CalendarFocus: Identifiable {
        let region: Region
        var id: Region {
            region
        }
    }

    var body: some View {
        NavigationStack {
            screen
                .background(elevatedBackground)
                .environment(\.colorScheme, .dark)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                // Hide the bar's material so the glass cards scroll underneath
                // the floating toolbar buttons rather than behind an opaque bar.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingRecentActivity = true
                        } label: {
                            Label(
                                Strings.primaryRecentActivity,
                                systemImage: "sparkles",
                            )
                        }
                        .accessibilityIdentifier("where_recent_activity_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingTimeline = true
                        } label: {
                            Label(
                                Strings.primaryTimeline,
                                systemImage: "calendar.day.timeline.left",
                            )
                        }
                        .accessibilityIdentifier("where_timeline_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCalendar = true
                        } label: {
                            Label(
                                Strings.primaryCalendar,
                                systemImage: "calendar",
                            )
                        }
                        .accessibilityIdentifier("where_calendar_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingEvidence = true
                        } label: {
                            Label(
                                Strings.primaryEvidence,
                                systemImage: "paperclip",
                            )
                        }
                        .accessibilityIdentifier("where_evidence_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingLoggedDays = true
                        } label: {
                            Label(
                                Strings.primaryLoggedDays,
                                systemImage: "calendar.badge.plus",
                            )
                        }
                        .accessibilityIdentifier("where_logged_days_button")
                    }
                }
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .sheet(isPresented: $showingRecentActivity) {
            RecentActivitySummaryView(report: report)
        }
        .sheet(isPresented: $showingTimeline) {
            PresenceTimelineView(report: report)
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarView(report: report)
        }
        .sheet(isPresented: $showingEvidence) {
            EvidenceListView(report: report)
        }
        .sheet(isPresented: $showingLoggedDays) {
            LoggedDaysView(report: report)
        }
        .sheet(item: $calendarFocus) { focus in
            CalendarView(focusedRegion: focus.region, report: report)
        }
    }

    /// A deep, near-black gradient that makes the Primary tab read like a
    /// passport cover, so the glass cards and their foil sheen feel elevated
    /// off the page. Forced dark (see `colorScheme` above) regardless of the
    /// system appearance.
    private var elevatedBackground: LinearGradient {
        LinearGradient(
            colors: [
                stylesheet.palette.primary.backgroundTop,
                stylesheet.palette.primary.backgroundBottom,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                AppIconLoadingView(caption: Strings.primaryLoading)
            case let .failed(error):
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(error.message)
                }
            case .idle, .loaded, .loading:
                if report.ranking.primary.isEmpty {
                    // Distinguish "nothing tracked at all" from "tracked days
                    // exist, but only in non-headline regions" (e.g. all in
                    // `.other`) — otherwise the latter wrongly reads as empty.
                    if report.trackedDayCount == 0 {
                        emptyState
                    } else {
                        elsewhereOnlyState
                    }
                } else {
                    content
                }
        }
    }

    private var content: some View {
        ScrollView {
            GlassEffectContainer(spacing: stylesheet.spacing.xxLarge) {
                VStack(spacing: stylesheet.spacing.xxLarge) {
                    ForEach(report.ranking.primary) { item in
                        Button {
                            calendarFocus = CalendarFocus(region: item.region)
                        } label: {
                            RegionSummaryCard(
                                regionDays: item,
                                interactive: true,
                                yearLength: report.daysInSelectedYear,
                                year: report.selectedYear,
                                tilt: tilt,
                            )
                        }
                        // Plain so the card's interactive Liquid Glass owns the
                        // press feel rather than the button adding its own.
                        .buttonStyle(.plain)
                        .accessibilityHint(Strings.primaryCardCalendarHint)
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("where_root_title")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Strings.primaryEmptyTitle(year: report.selectedYear), systemImage: "map")
        } description: {
            Text(Strings.primaryEmptyDescription)
        }
    }

    private var elsewhereOnlyState: some View {
        ContentUnavailableView {
            Label(Strings.primaryElsewhereOnlyTitle, systemImage: "globe.americas")
        } description: {
            Text(Strings.primaryElsewhereOnlyDescription(count: report.trackedDayCount))
        }
    }
}

#if DEBUG
    extension PrimaryView: SnapshotProviding {
        /// The raised settle floor on `Loaded` outlasts the iOS 26 glass toolbar
        /// material adaptation (seen pre-adaptation once on `Loaded_iPhone`) —
        /// same mechanism as `RootView.LoggedIn`.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Loaded",
                configurations: .screenDefaults,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                PrimaryView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(name: "ElsewhereOnly", configurations: .phoneLightDark) {
                PrimaryView(report: PreviewSupport.elsewhereOnlyYearReportModel())
            }
            whereSnapshot(name: "MissingDays", configurations: .phoneLightDark) {
                PrimaryView(report: PreviewSupport.missingDaysYearReportModel())
            }
        }
    }

    #Preview {
        PrimaryView.snapshotPreviews
    }
#endif
