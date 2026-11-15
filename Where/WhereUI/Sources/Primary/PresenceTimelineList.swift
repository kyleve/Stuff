import BroadwayUI
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

#if DEBUG
    import BroadwayCore
#endif

/// A chronological list of continuous stays (`RegionStint`s) for the selected
/// year — "California, Jan 1 – Feb 3", "New York, Feb 3 – Mar 10", and so on.
/// Hosted as the Timeline segment of the Your Year tab.
struct PresenceTimelineList: View {
    enum Presentation {
        case full
        case excerpt
    }

    enum RowID: Hashable {
        case recorded(RegionStint.ID)
        case flight(FlightAssessment.ID)
        case planned(PlanningTimelineItem.ID)

        init(_ item: PresenceJourneyItem) {
            self = switch item {
                case let .stay(stint): .recorded(stint.id)
                case let .flight(flight): .flight(flight.id)
            }
        }
    }

    let report: YearReportModel
    let presentation: Presentation
    private let suppliedPlanningDestination: Binding<PlannedStaysDestination?>?
    @State private var localPlanningDestination: PlannedStaysDestination?
    @BScrollPosition<RowID, Int> private var position: ScrollPosition
    enum ScrollRole: Hashable { case timeline }
    private var planningDestination: Binding<PlannedStaysDestination?> {
        suppliedPlanningDestination ?? $localPlanningDestination
    }

    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        presentation: Presentation = .full,
        planningDestination: Binding<PlannedStaysDestination?>? = nil,
    ) {
        self.report = report
        self.presentation = presentation
        suppliedPlanningDestination = planningDestination
        _position = BScrollPosition(
            Self.self,
            role: ScrollRole.timeline,
            context: { report.selectedYear },
            idType: RowID.self,
        )
    }

    var body: some View {
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
        let rowIDs = recordedItems.map(RowID.init)
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
                                    planningAction: { planningDestination.wrappedValue = .list },
                                )
                            }
                        }
                        .padding(.horizontal, stylesheet.spacing.xxLarge)
                        .padding(
                            .top,
                            pinsOverview ? 0 : stylesheet.spacing.large,
                        )
                        .padding(.bottom, stylesheet.spacing.large)
                    }
                    .scrollPosition($position)
                    .task(id: TimelineLayoutID(
                        year: report.selectedYear,
                        recordedItems: recordedItems,
                        plannedItems: plannedItems,
                    )) {
                        guard !Task.isCancelled else { return }
                        _position.initialize(edge: .bottom)
                        if let target = position.viewID(type: RowID.self),
                           !rowIDs.contains(target)
                        {
                            _position.scrollTo(edge: .bottom)
                        }
                    }
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .id(report.selectedYear)
                }
            }
        }
        .modifier(PlanningPresentation(
            report: report,
            destination: planningDestination,
            isEnabled: suppliedPlanningDestination == nil,
        ))
        .toolbar {
            if presentation != .excerpt, report.showsEstimatedTimeAndPlanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        String(localized: .plannedStaysTitle),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        planningDestination.wrappedValue = .list
                    }
                }
            }
        }
    }

    private struct TimelineLayoutID: Equatable {
        let year: Int
        let recordedItems: [PresenceJourneyItem]
        let plannedItems: [PlanningTimelineItem]
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
                        row
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
            .id(RowID(item))
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
                    edit(item)
                } label: {
                    row
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
                .id(RowID.planned(item.id))
            } else {
                row
            }
        }
    }

    private func edit(_ item: PlanningTimelineItem) {
        if case let .stay(interval) = item,
           let stay = report.forecasts.planning.stays.first(where: { $0.id == interval.stayID })
        {
            planningDestination.wrappedValue = .edit(stay)
        } else {
            planningDestination.wrappedValue = .list
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
            // WithData and Flights own full layout coverage; uncertainty keeps focused
            // accessibility checks.
            [
                whereSnapshot(
                    name: "InterruptedStay",
                    configurations: .fullContentPhoneLightDark,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport
                            .interruptedStayYearReportModel())
                    }
                },
                whereSnapshot(name: "Flights", configurations: .fullContentScreenRepresentative) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport
                            .flightHistoryYearReportModel())
                    }
                },
                whereSnapshot(
                    name: "UncertainArrival",
                    configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport
                            .flightYearReportModel(state: .uncertainArrival))
                    }
                },
                whereSnapshot(name: "Itinerary", configurations: .fullContentPhoneLightDark) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
                    }
                },
                whereSnapshot(
                    name: "WithData",
                    configurations: .fullContentScreenRepresentative,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
                    }
                },
                whereSnapshot(name: "InitialBottom", configurations: .phoneLightDark) {
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
                    configurations: .fullContentPhoneLightDarkWithAnnotations,
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
