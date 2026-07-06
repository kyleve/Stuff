import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    let report: YearReportModel

    @State private var showingTimeline = false
    @State private var showingCalendar = false
    @State private var showingRecentActivity = false
    @State private var calendarFocus: CalendarFocus?

    /// Drives the passport's tilt-reactive holographic sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

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
            VStack(spacing: 0) {
                PassportMasthead(title: Strings.primaryTitle, tilt: tilt)
                    .padding(.horizontal)
                    .padding(.top, UIConstants.Spacings.small)
                    .padding(.bottom, UIConstants.Spacings.medium)

                screen
            }
            .background(elevatedBackground)
            .environment(\.colorScheme, .dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                    YearSelector(report: report)
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
                Color(red: 0.07, green: 0.08, blue: 0.13),
                Color(red: 0.02, green: 0.02, blue: 0.05),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                ProgressView(Strings.primaryLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            GlassEffectContainer(spacing: UIConstants.Spacings.xxLarge) {
                VStack(spacing: UIConstants.Spacings.xxLarge) {
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

/// The Primary tab's masthead: the app wordmark embossed in gold foil that
/// catches a moving specular glint as the device tilts, like the gilt title on
/// a passport cover. Falls back to a fixed, gentle highlight under Reduce
/// Motion or on hardware without device motion.
private struct PassportMasthead: View {
    let title: String
    var tilt: TiltProvider?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lateral position of the glint, normalized `-1...1`. Pinned to a gentle
    /// off-center value when motion is unavailable or reduced.
    private var glintRoll: Double {
        guard !reduceMotion, let roll = tilt?.roll else { return 0.2 }
        return min(1, max(-1, roll))
    }

    var body: some View {
        let wordmark = Text(verbatim: title.uppercased())
            .font(.system(
                size: UIConstants.Size.mastheadFontSize,
                weight: .heavy,
                design: .serif,
            ))
            .tracking(2)

        return wordmark
            .foregroundStyle(goldFoil)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.95), .clear],
                    startPoint: UnitPoint(x: glintRoll * 0.5 - 0.1, y: 0),
                    endPoint: UnitPoint(x: glintRoll * 0.5 + 0.6, y: 1),
                )
                .blendMode(.plusLighter)
            }
            .mask { wordmark }
            .shadow(
                color: .black.opacity(0.45),
                radius: UIConstants.Spacings.xSmall,
                y: UIConstants.Spacings.xxSmall,
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }

    /// Brushed-gold gradient that reads as embossed gilt on the dark cover.
    private var goldFoil: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.93, blue: 0.7),
                Color(red: 0.86, green: 0.66, blue: 0.32),
                Color(red: 1.0, green: 0.9, blue: 0.66),
                Color(red: 0.72, green: 0.52, blue: 0.24),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }
}

#if DEBUG
    #Preview("Loaded") {
        PrimaryView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Empty") {
        PrimaryView(report: PreviewSupport.emptyYearReportModel())
    }

    #Preview("Missing days") {
        PrimaryView(report: PreviewSupport.missingDaysYearReportModel())
    }

    #Preview("Elsewhere only") {
        PrimaryView(report: PreviewSupport.elsewhereOnlyYearReportModel())
    }
#endif
