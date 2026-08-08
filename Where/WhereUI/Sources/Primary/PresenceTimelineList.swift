import SnapshotKit
import SwiftUI
import WhereCore

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
            ScrollView {
                LazyVStack(spacing: stylesheet.spacing.large) {
                    YearRibbon(
                        days: yearReport?.days ?? [],
                        year: report.selectedYear,
                        calendar: report.calendar,
                    )

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
                .padding(.vertical, stylesheet.spacing.large)
            }
        }
    }
}

#if DEBUG
    extension PresenceTimelineList: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithData", configurations: .screenDefaults) {
                NavigationStack {
                    PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
                }
            }
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
