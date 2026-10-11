import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

#if DEBUG
    import BroadwayCore
    import BroadwayUI
#endif

/// A chronological list of continuous stays (`RegionStint`s) for the selected
/// year — "California, Jan 1 – Feb 3", "New York, Feb 3 – Mar 10", and so on.
/// Hosted as the Timeline segment of the Your Year tab.
struct PresenceTimelineList: View {
    enum Presentation {
        case full
        case excerpt
    }

    let report: YearReportModel
    var presentation: Presentation = .full

    @Environment(\.stylesheet) private var stylesheet
    @State private var planningDestination: PlannedStaysDestination?

    var body: some View {
        let yearReport = report.report
        let stints = yearReport
            .map { PresenceTimeline.stints(from: $0, calendar: report.calendar) } ?? []
        let plannedItems = report.showsEstimatedTimeAndPlanning
            ? PlanningTimelineItem.items(
                planning: report.forecasts.planning,
                year: report.selectedYear,
                today: report.forecasts.today,
            )
            : []

        Group {
            if presentation == .excerpt {
                if yearReport == nil {
                    Text(.settingsExploreHistoryUnavailable).font(.subheadline)
                } else if stints.isEmpty, plannedItems.isEmpty {
                    Text(.settingsExploreHistoryEmpty).font(.subheadline)
                } else {
                    VStack(spacing: 0) {
                        journeyRows(
                            stints: Array(stints.suffix(2)),
                            plannedItems: Array(plannedItems.prefix(2)),
                        )
                    }
                }
            } else if report.report == nil, report.loadState == .loading {
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            } else if case let .failed(error) = report.loadState {
                ContentUnavailableView(
                    String(localized: .commonLoadErrorTitle),
                    systemSymbol: .exclamationmarkIcloud,
                    description: Text(error.message),
                )
            } else if stints.isEmpty, plannedItems.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: .timelineEmptyTitle),
                        systemSymbol: .calendarDayTimelineLeft,
                    )
                } description: {
                    Text(String(localized: .timelineEmptyDescription))
                }
            } else {
                let pinsOverview = stylesheet.timeline.overview.pinsToViewport

                ScrollView {
                    LazyVStack(spacing: stylesheet.spacing.large) {
                        if !pinsOverview {
                            YearRibbon(
                                days: yearReport?.days ?? [],
                                year: report.selectedYear,
                                calendar: report.calendar,
                            )
                        }

                        LazyVStack(spacing: 0) {
                            journeyRows(stints: stints, plannedItems: plannedItems)
                        }

                        if showsForecast {
                            LocationForecastPanel(
                                forecasts: timelineForecasts,
                                microprintRegions: report.ranking.primary.map(\.region),
                                homeRegion: report.forecasts.planning.homeRegion,
                                planningAction: { planningDestination = .list },
                            )
                        }
                    }
                    .padding(.horizontal, stylesheet.spacing.xxLarge)
                    .padding(.top, pinsOverview ? 0 : stylesheet.spacing.large)
                    .padding(.bottom, stylesheet.spacing.large)
                }
                .safeAreaInset(
                    edge: .top,
                    spacing: 0,
                ) {
                    if pinsOverview {
                        YearRibbon(
                            days: yearReport?.days ?? [],
                            year: report.selectedYear,
                            calendar: report.calendar,
                        )
                        .padding(.horizontal, stylesheet.spacing.xxLarge)
                        .padding(.top, stylesheet.spacing.large)
                        .padding(.bottom, stylesheet.spacing.large)
                    }
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .id(report.selectedYear)
            }
        }
        .sheet(item: $planningDestination) { destination in
            PlannedStaysDestinationView(destination: destination, report: report)
        }
        .toolbar {
            if presentation == .full, report.showsEstimatedTimeAndPlanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        String(localized: .plannedStaysTitle),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        planningDestination = .list
                    }
                }
            }
        }
    }

    /// Both presentations share recorded and planned row rendering.
    @ViewBuilder
    private func journeyRows(
        stints: [RegionStint],
        plannedItems: [PlanningTimelineItem],
    ) -> some View {
        ForEach(stints) { stint in
            PresenceJourneyRow(
                stint: stint,
                calendar: report.calendar,
                daysInYear: report.daysInSelectedYear,
                isFirst: stint.id == stints.first?.id,
                isLast: plannedItems.isEmpty && stint.id == stints.last?.id,
                cardPosition: .standalone,
            )
            .fixedSize(horizontal: false, vertical: presentation == .excerpt)
        }
        ForEach(plannedItems) { item in
            let row = PlannedPresenceJourneyRow(
                item: item,
                calendar: report.calendar,
                daysInYear: report.daysInSelectedYear,
                isFirst: stints.isEmpty && item.id == plannedItems.first?.id,
                isLast: item.id == plannedItems.last?.id,
                cardPosition: .standalone,
            )
            .fixedSize(horizontal: false, vertical: presentation == .excerpt)

            if presentation == .full {
                Button {
                    if case let .stay(interval) = item,
                       let stay = report.forecasts.planning.stays
                       .first(where: { $0.id == interval.stayID })
                    {
                        planningDestination = .edit(stay)
                    } else {
                        planningDestination = .list
                    }
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private var showsForecast: Bool {
        report.showsEstimatedTimeAndPlanning && !timelineForecasts.isEmpty
    }

    private var timelineForecasts: [LocationForecast] {
        report.forecasts.leadingForecasts(report: report.report)
    }
}

#if DEBUG
    extension PresenceTimelineList: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(name: "Itinerary", configurations: .fullContentScreenDefaults) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
                    }
                },
                whereSnapshot(
                    name: "WithData",
                    configurations: .fullContentScreenDefaults,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
                    }
                },
                whereSnapshot(name: "InitialBottom", configurations: .screenDefaults) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
                    }
                },
                whereSnapshot(
                    name: "DifferentiateWithoutColor",
                    configurations: .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
                    }
                    .bTraitOverrides { traits, overrides in
                        var accessibility = traits.accessibility
                        accessibility.shouldDifferentiateWithoutColor = true
                        overrides.accessibility = accessibility
                    }
                },
                whereSnapshot(
                    name: "DifferentiateWithoutColorInitialBottom",
                    configurations: .phoneLightDark,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
                    }
                    .bTraitOverrides { traits, overrides in
                        var accessibility = traits.accessibility
                        accessibility.shouldDifferentiateWithoutColor = true
                        overrides.accessibility = accessibility
                    }
                },
                whereSnapshot(
                    name: "PlannedStay",
                    configurations: .fullContentPhoneLightDark
                        + SnapshotConfiguration.combinations(
                            devices: [.iPhoneFullContent],
                            snapshotTypes: [.accessibility],
                        ),
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.plannedStayYearReportModel())
                    }
                },
                whereSnapshot(
                    name: "ShortPlannedStay",
                    configurations: .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.plannedStayYearReportModel(
                            plannedThroughDay: CalendarDay(year: 2026, month: 7, day: 24),
                        ))
                    }
                },
                whereSnapshot(
                    name: "PlannedStayHidden",
                    configurations: .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.plannedStayYearReportModel(
                            showsEstimatedTimeAndPlanning: false,
                        ))
                    }
                },
                whereSnapshot(
                    name: "PlannedStayDifferentRegion",
                    configurations: .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.plannedStayYearReportModel(
                            plannedRegion: .california,
                        ))
                    }
                },
                whereSnapshot(
                    name: "PlannedStayAfterRecordingGap",
                    configurations: .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.plannedStayYearReportModel(
                            recordedThroughDay: CalendarDay(year: 2026, month: 7, day: 12),
                        ))
                    }
                },
            ]
        }
    }

    #Preview {
        PresenceTimelineList.snapshotPreviews
    }
#endif

#if DEBUG
    extension PresenceTimelineList: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            PresenceTimelineList.self,
            title: "Timeline",
        )
    }
#endif
