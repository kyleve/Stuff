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
    let report: YearReportModel

    @Environment(\.stylesheet) private var stylesheet
    @State private var plannedStayEditorTarget: PlannedStayEditorTarget?

    private struct PlannedStayEditorTarget: Identifiable {
        let region: Region

        var id: Region {
            region
        }
    }

    var body: some View {
        let yearReport = report.report
        let stints = yearReport.map { PresenceTimeline.stints(from: $0) } ?? []
        let plannedInterval = report.showsEstimatedTimeAndPlanning
            ? report.forecasts.plannedInterval(intersecting: report.selectedYear)
            : nil
        let joinsPlannedStay = if let plannedInterval, let currentStint = stints.last {
            plannedInterval.region == currentStint.region
                && CalendarDay(from: currentStint.end, in: report.calendar).adding(days: 1)
                == plannedInterval.start
        } else {
            false
        }

        Group {
            if stints.isEmpty, plannedInterval == nil {
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
                            ForEach(stints.enumerated(), id: \.element.id) { index, stint in
                                PresenceJourneyRow(
                                    stint: stint,
                                    calendar: report.calendar,
                                    daysInYear: report.daysInSelectedYear,
                                    isFirst: index == stints.startIndex,
                                    isLast: plannedInterval == nil
                                        && index == stints.index(before: stints.endIndex),
                                    cardPosition: joinsPlannedStay
                                        && index == stints.index(before: stints.endIndex)
                                        ? .top
                                        : .standalone,
                                )
                            }

                            if let plannedInterval {
                                PlannedPresenceJourneyRow(
                                    interval: plannedInterval,
                                    calendar: report.calendar,
                                    daysInYear: report.daysInSelectedYear,
                                    isFirst: stints.isEmpty,
                                    cardPosition: joinsPlannedStay ? .bottom : .standalone,
                                )
                            }
                        }

                        if showsForecast {
                            LocationForecastPanel(
                                forecasts: timelineForecasts,
                                microprintRegions: report.ranking.primary.map(\.region),
                                plannedStay: report.forecasts.activePlannedStay,
                                editableRegions: report.ranking.primary.map(\.region),
                                editAction: { region in
                                    plannedStayEditorTarget =
                                        PlannedStayEditorTarget(region: region)
                                },
                                clearAction: report.forecasts.clear,
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
        .sheet(item: $plannedStayEditorTarget) { target in
            PlannedStayEditor(
                region: target.region,
                model: report.forecasts,
                driftThreshold: report.driftThreshold,
            )
        }
    }

    private var showsForecast: Bool {
        report.showsEstimatedTimeAndPlanning && !timelineForecasts.isEmpty
    }

    private var timelineForecasts: [LocationForecast] {
        report.ranking.primary.compactMap {
            report.forecasts.forecast(for: $0.region, report: report.report)
        }
    }
}

#if DEBUG
    extension PresenceTimelineList: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
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
