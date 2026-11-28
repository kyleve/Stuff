import RegionKit
import SwiftUI
import WhereCore

struct CalendarOverviewMonthButton: View {
    let month: CalendarMonth
    let available: Bool
    let report: YearReportModel
    let focusedRegion: Region?
    let presentation: CalendarPresentationState
    let onExpand: (CalendarPresentationState.Target) -> Void

    var body: some View {
        let destination = CalendarPresentationState.Target.month(month.firstCalendarDay)
        Button { onExpand(destination) } label: {
            MonthGridView(
                month: month,
                focusedRegion: focusedRegion,
                report: report,
                compact: true,
                isAvailable: available,
            )
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
            [.overview: [.tile(destination): $0]]
        }
        .accessibilityHint(available ? String(localized: .calendarExpandMonth) :
            String(localized: .calendarMonthUnavailable))
        .modifier(CalendarOverviewFeedback(
            rejected: presentation.rejectedTarget == destination,
            trigger: presentation.rejectionTrigger,
        ))
    }
}

#if DEBUG
    #Preview("Month availability") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
