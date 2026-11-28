import BroadwayUI
import SwiftUI
import WhereCore

struct PresenceTimelineScroll: View {
    let report: YearReportModel
    let items: [PresenceTimelineRows.Item]
    let forecasts: [LocationForecast]
    let awaitsForecast: Bool
    @Binding var position: ScrollPosition
    let openPlanning: (PlannedStaysDestination) -> Void
    let positionTimeline: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let pinsOverview = stylesheet.timeline.overview
            .pinsToViewport

        VStack(spacing: 0) {
            if pinsOverview {
                YearRibbon(
                    days: report.report?.days ?? [],
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
                    if !pinsOverview {
                        YearRibbon(
                            days: report.report?.days ?? [],
                            year: report.selectedYear,
                            calendar: report.calendar,
                        )
                    }

                    VStack(spacing: 0) {
                        PresenceTimelineRows(
                            items: items,
                            report: report,
                            forecasts: forecasts,
                            openPlanning: openPlanning,
                        )
                    }
                    .scrollTargetLayout()
                }
                .padding(.horizontal, stylesheet.spacing.xxLarge)
                .padding(
                    .top,
                    pinsOverview ? 0 : stylesheet.spacing.large,
                )
                .padding(.bottom, items.last == .estimate ? 0 : stylesheet.spacing.large)
                .whereContentRoot()
            }
            .scrollPosition($position)
            .task(id: TimelineLayoutID(
                year: report.selectedYear,
                items: items,
                awaitsForecast: awaitsForecast,
            )) {
                guard !Task.isCancelled, !awaitsForecast else { return }
                positionTimeline()
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .id(report.selectedYear)
        }
    }

    private struct TimelineLayoutID: Equatable {
        let year: Int
        let items: [PresenceTimelineRows.Item]
        let awaitsForecast: Bool
    }
}

#if DEBUG
    #Preview("Timeline") {
        PresenceTimelineList(report: PreviewSupport.itineraryYearReportModel())
            .whereBroadwayRoot()
    }
#endif
