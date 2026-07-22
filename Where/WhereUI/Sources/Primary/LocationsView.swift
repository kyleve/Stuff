import PeriscopeCore
import RegionKit
import SwiftUI
import WhereCore

/// Locations tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards, with the Elsewhere summary folded in
/// at the bottom (only when there are secondary regions) and a Resolve button
/// that appears — badged — only while there are data issues to fix.
struct LocationsView: View {
    let report: YearReportModel

    @State private var showingResolution = false
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
                    // Resolve is a toolbar action here rather than its own tab:
                    // it appears (badged with the count) only while there are
                    // data issues to fix, and opens the resolution list.
                    if report.dataIssueCount > 0 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingResolution = true
                            } label: {
                                ResolveToolbarLabel(count: report.dataIssueCount)
                            }
                            .accessibilityIdentifier("where_resolution_button")
                        }
                    }
                }
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .sheet(item: $calendarFocus) { focus in
            CalendarView(focusedRegion: focus.region, report: report)
        }
        .sheet(isPresented: $showingResolution) {
            ResolutionView(report: report)
        }
        // Log View Mode: reveal an inspect badge for the year-report events
        // backing this screen. A no-op in release.
        .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
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

                    // Fold Elsewhere in at the bottom — only when there's
                    // something in it — as an entry card into the full list.
                    if !report.ranking.secondary.isEmpty {
                        NavigationLink {
                            ElsewhereView(report: report)
                        } label: {
                            ElsewhereSummaryCard(
                                regionCount: report.ranking.secondary.count,
                                dayCount: report.ranking.secondary.reduce(0) { $0 + $1.days },
                            )
                        }
                        .buttonStyle(.plain)
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

/// The Locations toolbar's Resolve affordance: the checklist icon with a count
/// badge. Rendered only while there are issues (the toolbar item is gated on
/// the count), so it always carries a positive `count`.
private struct ResolveToolbarLabel: View {
    let count: Int

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Image(systemName: "checklist")
            .overlay(alignment: .topTrailing) {
                Text(count, format: .number)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, stylesheet.spacing.xSmall)
                    .padding(.vertical, stylesheet.spacing.xxSmall)
                    .background(.red, in: Capsule())
                    .offset(x: stylesheet.spacing.small, y: -stylesheet.spacing.small)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(Strings.tabResolution)
            .accessibilityValue(Text(count, format: .number))
    }
}

#if DEBUG
    #Preview("Loaded") {
        LocationsView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Empty") {
        LocationsView(report: PreviewSupport.emptyYearReportModel())
    }

    #Preview("Missing days") {
        LocationsView(report: PreviewSupport.missingDaysYearReportModel())
    }

    #Preview("Elsewhere only") {
        LocationsView(report: PreviewSupport.elsewhereOnlyYearReportModel())
    }
#endif
