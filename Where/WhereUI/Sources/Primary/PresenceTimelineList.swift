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

    var body: some View {
        let yearReport = report.report
        let stints = yearReport.map { PresenceTimeline.stints(from: $0) } ?? []

        if stints.isEmpty {
            ContentUnavailableView {
                Label(
                    String(localized: .timelineEmptyTitle),
                    systemImage: "calendar.day.timeline.left",
                )
            } description: {
                Text(String(localized: .timelineEmptyDescription))
            }
        } else {
            let pinsOverview = stylesheet.timeline.overview.pinsToViewport

            ScrollView {
                LazyVStack(spacing: pinsOverview ? 0 : stylesheet.spacing.large) {
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
                                isLast: index == stints.index(before: stints.endIndex),
                            )
                        }
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
