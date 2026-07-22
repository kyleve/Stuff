import SwiftUI
import WhereCore

/// Your Year tab: the selected year's calendar and timeline for the same data,
/// toggled by a segmented control, with the on-device activity summary in the
/// toolbar. The segment choice is remembered across launches by
/// ``SegmentedTabContainer``.
struct YearView: View {
    let report: YearReportModel

    @State private var showingRecentActivity = false

    var body: some View {
        NavigationStack {
            SegmentedTabContainer(
                storageKey: .year,
                initialSelection: YearSegment.calendar,
                pickerLabel: Strings.yearSegmentPickerLabel,
            ) { segment, _ in
                switch segment {
                    case .calendar:
                        CalendarContentView(report: report)
                    case .timeline:
                        PresenceTimelineList(report: report)
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingRecentActivity = true
                    } label: {
                        Label(Strings.primaryRecentActivity, systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("where_recent_activity_button")
                }
            }
        }
        .sheet(isPresented: $showingRecentActivity) {
            RecentActivitySummaryView(report: report)
        }
    }

    /// Plain "Your Year" for the current year; suffixed with the year when
    /// viewing a past one, so the year in view is never ambiguous.
    private var navigationTitle: String {
        report.selectedYear == WhereModel.currentYear
            ? Strings.tabYear
            : Strings.tabYearTitle(forYear: report.selectedYear)
    }
}

/// The Your Year tab's two views of the same year.
enum YearSegment: String, CaseIterable, SegmentedItem {
    case calendar
    case timeline

    var title: String {
        switch self {
            case .calendar: Strings.primaryCalendar
            case .timeline: Strings.primaryTimeline
        }
    }
}

#if DEBUG
    #Preview("Loaded") {
        YearView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Empty") {
        YearView(report: PreviewSupport.emptyYearReportModel())
    }
#endif
