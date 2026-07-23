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

    /// Drives the region cards' tilt-reactive holographic sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    /// Pairs a tapped card with its pushed calendar so the navigation uses a
    /// matched-geometry zoom (the card expands into the calendar) rather than a
    /// plain slide.
    @Namespace private var calendarTransition

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        NavigationStack {
            screen
                .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showingResolution) {
            ResolutionView(report: report)
        }
        // Log View Mode: reveal an inspect badge for the year-report events
        // backing this screen. A no-op in release.
        .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
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
        // `.defaultScrollAnchor(.center)` vertically centers a short list (one or
        // two cards) rather than pinning it to the top, while a longer list still
        // scrolls from the top.
        ScrollView {
            GlassEffectContainer(spacing: stylesheet.spacing.xxLarge) {
                VStack(spacing: stylesheet.spacing.xxLarge) {
                    ForEach(report.ranking.primary) { item in
                        NavigationLink {
                            calendarDestination(item.region)
                        } label: {
                            RegionSummaryCard(
                                regionDays: item,
                                interactive: true,
                                yearLength: report.daysInSelectedYear,
                                year: report.selectedYear,
                                tilt: tilt,
                            )
                        }
                        // Plain so the card's interactive Liquid Glass owns
                        // the press feel rather than the button adding its own.
                        .buttonStyle(.plain)
                        // The card is the zoom source: tapping it expands the
                        // card into the pushed calendar (matched geometry). The
                        // configuration re-states the card's rounded shape and
                        // its glow/lift shadows so the transition interpolates
                        // them — without it, the zoom clips the source to a bare
                        // rectangle and the card's soft shadow pops on/off.
                        .matchedTransitionSource(
                            id: item.region,
                            in: calendarTransition,
                        ) { source in
                            let card = stylesheet.card.regular
                            let tint = regionStyles.style(for: item.region).tint
                            return source
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: card.cornerRadius,
                                        style: .continuous,
                                    ),
                                )
                                .shadow(
                                    color: tint.opacity(card.glow.opacity),
                                    radius: card.glow.radius,
                                )
                                .shadow(
                                    color: tint.opacity(card.lift.opacity),
                                    radius: card.lift.radius,
                                    y: card.lift.offsetY,
                                )
                        }
                        .accessibilityHint(Strings.primaryCardCalendarHint)
                    }

                    // Fold Elsewhere in at the bottom — only when there's
                    // something in it — as an entry card into the full list.
                    if !report.ranking.secondary.isEmpty {
                        NavigationLink {
                            ElsewhereView(report: report)
                        } label: {
                            ElsewhereSummaryCard(regionCount: report.ranking.secondary.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("where_root_title")
    }

    /// The region's calendar, pushed as a nested view. It's the zoom
    /// destination: the tapped card expands into it via matched geometry, and the
    /// stack's back gesture collapses it again.
    private func calendarDestination(_ region: Region) -> some View {
        CalendarContentView(focusedRegion: region, report: report)
            .navigationTitle(Strings.calendarRegionTitle(region: region, year: report.selectedYear))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTransition(.zoom(sourceID: region, in: calendarTransition))
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
        } actions: {
            // Everything tracked is Elsewhere, so surface the list directly —
            // there's no Elsewhere tab to send them to anymore.
            if !report.ranking.secondary.isEmpty {
                NavigationLink(Strings.primaryElsewhereOnlyOpen) {
                    ElsewhereView(report: report)
                }
                .buttonStyle(.borderedProminent)
            }
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
