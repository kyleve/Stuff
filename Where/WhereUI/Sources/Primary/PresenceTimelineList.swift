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
        case estimate

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
        let today = report.forecasts.today
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
                today: today,
            )
            : []
        let forecasts = presentation == .full && report.showsEstimatedTimeAndPlanning
            ? report.forecasts.leadingForecasts(report: yearReport) : []
        let items = PresenceTimelineRows.Item.ordered(
            recorded: recordedItems,
            planned: plannedItems,
            estimateDay: forecasts.isEmpty ? nil : today,
            calendar: report.calendar,
        )
        let awaitsForecast = report.showsEstimatedTimeAndPlanning && report.selectedYear == today
            .year
            && !report.forecasts.hasLoaded && report.forecasts.loadFailure == nil

        Group {
            if presentation == .excerpt {
                if yearReport == nil {
                    Text(.settingsExploreHistoryUnavailable).font(.subheadline)
                } else if recordedItems.isEmpty, plannedItems.isEmpty {
                    Text(.settingsExploreHistoryEmpty).font(.subheadline)
                } else {
                    VStack(spacing: 0) {
                        PresenceTimelineRows(
                            items: recordedItems.suffix(2).map(PresenceTimelineRows.Item.recorded)
                                + plannedItems.prefix(2).map(PresenceTimelineRows.Item.planned),
                            report: report,
                            forecasts: [],
                            openPlanning: nil,
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
                        .whereContentRoot()
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
                                PresenceTimelineRows(
                                    items: items,
                                    report: report,
                                    forecasts: forecasts,
                                    openPlanning: { planningDestination.wrappedValue = $0 },
                                )
                            }
                            .scrollTargetLayout()
                        }
                        .padding(.horizontal, stylesheet.spacing.xxLarge)
                        .padding(
                            .top,
                            pinsOverview ? 0 : stylesheet.spacing.large,
                        )
                        .padding(.bottom, stylesheet.spacing.large)
                        .whereContentRoot()
                    }
                    .scrollPosition($position)
                    .task(id: TimelineLayoutID(
                        year: report.selectedYear,
                        items: items,
                        awaitsForecast: awaitsForecast,
                    )) {
                        guard !Task.isCancelled, !awaitsForecast else { return }
                        positionTimeline(items: items, hasEstimate: !forecasts.isEmpty)
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
        let items: [PresenceTimelineRows.Item]
        let awaitsForecast: Bool
    }

    private func positionTimeline(items: [PresenceTimelineRows.Item], hasEstimate: Bool) {
        if hasEstimate {
            _position.initialize(id: .estimate, anchor: .bottom)
        } else {
            _position.initialize(edge: .bottom)
        }

        if let target = position.viewID(type: RowID.self),
           !items.contains(where: { $0.id == target })
        {
            if hasEstimate {
                _position.scrollTo(id: .estimate, anchor: .bottom)
            } else {
                _position.scrollTo(edge: .bottom)
            }
        }
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
