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
        case linked
        case excerpt
    }

    let report: YearReportModel
    let presentation: Presentation
    private let ownsPlanningPresentation: Bool

    @Environment(\.stylesheet) private var stylesheet
    @State private var history: HistoryNavigationModel

    init(
        report: YearReportModel,
        presentation: Presentation = .full,
        history: HistoryNavigationModel? = nil,
    ) {
        self.report = report
        self.presentation = presentation
        ownsPlanningPresentation = history == nil
        _history = State(initialValue: history ?? HistoryNavigationModel())
    }

    var body: some View {
        @Bindable var navigation = history.timeline
        let yearReport = report.report
        let stints = yearReport
            .map { PresenceTimeline.stints(from: $0, calendar: report.calendar) } ?? []
        let recordedItems = PresenceJourneyItem.items(
            stints: stints,
            flights: report.completedFlights,
            year: report.selectedYear,
            calendar: report.calendar,
        )
        let plannedItems = report.showsEstimatedTimeAndPlanning
            ? PlanningTimelineItem.items(
                planning: report.forecasts.planning,
                year: report.selectedYear,
                today: report.forecasts.today,
            )
            : []
        let rowIDs = recordedItems.map(TimelineNavigationModel.Item.init)
            + plannedItems.map { .planned($0.id) }

        Group {
            if presentation == .excerpt {
                if yearReport == nil {
                    Text(.settingsExploreHistoryUnavailable).font(.subheadline)
                } else if recordedItems.isEmpty, plannedItems.isEmpty {
                    Text(.settingsExploreHistoryEmpty).font(.subheadline)
                } else {
                    VStack(spacing: 0) {
                        journeyRows(
                            recordedItems: Array(recordedItems.suffix(2)),
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
            } else if recordedItems.isEmpty, plannedItems.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: .timelineEmptyTitle),
                        systemSymbol: .calendarDayTimelineLeft,
                    )
                } description: {
                    Text(String(localized: .timelineEmptyDescription))
                }
            } else {
                let pinsOverview = presentation == .full && stylesheet.timeline.overview
                    .pinsToViewport

                VStack(spacing: 0) {
                    if pinsOverview {
                        YearRibbon(
                            days: yearReport?.days ?? [],
                            year: report.selectedYear,
                            calendar: report.calendar,
                        )
                        .padding(.horizontal, stylesheet.spacing.xxLarge)
                        .padding(.vertical, stylesheet.spacing.large)
                    }
                    ScrollView {
                        // Measure this year's overview, stays, and forecast together.
                        // Lazy row estimates can move the overview above the content
                        // origin when a bottom-anchored viewport expands.
                        VStack(spacing: stylesheet.spacing.large) {
                            if presentation == .full, !pinsOverview {
                                YearRibbon(
                                    days: yearReport?.days ?? [],
                                    year: report.selectedYear,
                                    calendar: report.calendar,
                                )
                            }

                            VStack(spacing: 0) {
                                journeyRows(
                                    recordedItems: recordedItems,
                                    plannedItems: plannedItems,
                                )
                            }
                            .scrollTargetLayout()

                            if presentation == .full, showsForecast {
                                LocationForecastPanel(
                                    forecasts: timelineForecasts,
                                    microprintRegions: report.ranking.primary.map(\.region),
                                    homeRegion: report.forecasts.planning.homeRegion,
                                    planningAction: { history.planning.destination = .list },
                                )
                            }
                        }
                        .padding(.horizontal, stylesheet.spacing.xxLarge)
                        .padding(.top, pinsOverview ? 0 : stylesheet.spacing.large)
                        .padding(.bottom, stylesheet.spacing.large)
                    }
                    .scrollPosition($navigation.scrollPosition)
                    .onScrollTargetVisibilityChange(
                        idType: TimelineNavigationModel.Item.self,
                        threshold: 0.01,
                    ) { visible in
                        guard navigation.scrollPosition.isPositionedByUser else { return }
                        navigation.recordVisibleItems(
                            rowIDs.filter { visible.contains($0) },
                            in: report.selectedYear,
                        )
                    }
                    .task(id: report.selectedYear) {
                        navigation.restorePosition(
                            in: report.selectedYear,
                            initialItem: presentation == .linked
                                ? recordedItems.last.map(TimelineNavigationModel.Item.init) : nil,
                        )
                        navigation.reconcile(
                            recordedItems: recordedItems,
                            plannedItems: plannedItems,
                            calendar: report.calendar,
                        )
                    }
                    .onChange(of: recordedItems) {
                        navigation.reconcile(
                            recordedItems: recordedItems,
                            plannedItems: plannedItems,
                            calendar: report.calendar,
                        )
                    }
                    .onChange(of: plannedItems) {
                        navigation.reconcile(
                            recordedItems: recordedItems,
                            plannedItems: plannedItems,
                            calendar: report.calendar,
                        )
                    }
                    .onChange(of: navigation.monthRevealID) {
                        navigation.reconcile(
                            recordedItems: recordedItems,
                            plannedItems: plannedItems,
                            calendar: report.calendar,
                        )
                    }
                    .defaultScrollAnchor(
                        presentation == .linked ? .top : .bottom,
                        for: .initialOffset,
                    )
                    .id(report.selectedYear)
                }
            }
        }
        .modifier(PlanningPresentation(
            report: report,
            navigation: history.planning,
            isEnabled: ownsPlanningPresentation,
        ))
        .toolbar {
            if presentation != .excerpt, report.showsEstimatedTimeAndPlanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        String(localized: .plannedStaysTitle),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        history.planning.destination = .list
                    }
                }
            }
        }
    }

    /// Both presentations share recorded and planned row rendering.
    @ViewBuilder
    private func journeyRows(
        recordedItems: [PresenceJourneyItem],
        plannedItems: [PlanningTimelineItem],
    ) -> some View {
        let lastStint: RegionStint? = if case let .stay(stint) = recordedItems.last { stint }
        else { nil }
        let joinsRecorded = lastStint.map { last in
            plannedItems.first?.continues(last, calendar: report.calendar) == true
        } ?? false
        ForEach(recordedItems) { item in
            Group {
                switch item {
                    case let .stay(stint):
                        let row = PresenceJourneyRow(
                            stint: stint,
                            calendar: report.calendar,
                            daysInYear: report.daysInSelectedYear,
                            isFirst: item.id == recordedItems.first?.id,
                            isLast: plannedItems.isEmpty && item.id == recordedItems.last?.id,
                            cardPosition: joinsRecorded && item.id == recordedItems.last?.id
                                ? .top : .standalone,
                        )
                        if presentation == .excerpt {
                            row
                        } else {
                            Button {
                                history.select(stint: stint, dateCalendar: report.calendar)
                            } label: {
                                row.historySelection(isSelected(
                                    start: CalendarDay(from: stint.start, in: report.calendar),
                                    end: CalendarDay(from: stint.end, in: report.calendar),
                                    region: stint.region,
                                ))
                            }
                            .buttonStyle(.plain)
                        }
                    case let .flight(flight):
                        FlightJourneyRow(
                            flight: flight,
                            calendar: report.calendar,
                            isFirst: item.id == recordedItems.first?.id,
                            isLast: plannedItems.isEmpty && item.id == recordedItems.last?.id,
                        )
                }
            }
            .fixedSize(horizontal: false, vertical: presentation == .excerpt)
            .id(TimelineNavigationModel.Item(item))
        }
        ForEach(plannedItems) { item in
            let row = PlannedPresenceJourneyRow(
                item: item,
                calendar: report.calendar,
                daysInYear: report.daysInSelectedYear,
                isFirst: recordedItems.isEmpty && item.id == plannedItems.first?.id,
                isLast: item.id == plannedItems.last?.id,
                cardPosition: joinsRecorded && item.id == plannedItems.first?
                    .id ? .bottom : .standalone,
            )
            .fixedSize(horizontal: false, vertical: presentation == .excerpt)

            if presentation != .excerpt {
                Button {
                    history.select(plannedItem: item)
                    if presentation == .full { edit(item) }
                } label: {
                    row.historySelection(isSelected(
                        start: item.start,
                        end: item.end,
                        region: item.region,
                    ))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(
                        String(localized: .plannedStaysTitle),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        edit(item)
                    }
                }
                .id(TimelineNavigationModel.Item.planned(item.id))
            } else {
                row
            }
        }
    }

    private func edit(_ item: PlanningTimelineItem) {
        if case let .stay(interval) = item,
           let stay = report.forecasts.planning.stays.first(where: { $0.id == interval.stayID })
        {
            history.planning.destination = .edit(stay)
        } else {
            history.planning.destination = .list
        }
    }

    private func isSelected(start: CalendarDay, end: CalendarDay, region: Region) -> Bool {
        guard let selection = history.selection,
              selection.region == nil || selection.region == region
        else { return false }
        return selection.interval.overlaps(start ... end)
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
                whereSnapshot(
                    name: "BrowseColumn",
                    configurations: [SnapshotConfiguration(device: AdaptiveHistorySnapshotFixture
                            .browseColumn)],
                ) {
                    NavigationStack {
                        PresenceTimelineList(
                            report: PreviewSupport.loadedYearReportModel(),
                            presentation: .linked,
                        )
                    }
                },
                whereSnapshot(name: "Flights", configurations: .fullContentScreenDefaults) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport
                            .flightHistoryYearReportModel())
                    }
                },
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
