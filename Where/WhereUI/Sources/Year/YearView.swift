import SwiftUI
import WhereCore

/// Your Year tab: the selected year's calendar and timeline for the same data,
/// switched by a segmented control in the toolbar (sitting in the Liquid Glass
/// bar), with the on-device activity summary alongside it.
struct YearView: View {
    let report: YearReportModel

    @State private var mode: Mode = .calendar
    @State private var showingRecentActivity = false

    /// The two views of the selected year the toolbar control switches between.
    private enum Mode: Hashable {
        case calendar
        case timeline
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                    case .calendar:
                        CalendarContentView(report: report)
                    case .timeline:
                        PresenceTimelineList(report: report)
                }
            }
            // Crossfade between the two views rather than hard-cutting.
            .animation(.default, value: mode)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(Strings.yearSegmentPickerLabel, selection: $mode) {
                        Text(Strings.primaryCalendar).tag(Mode.calendar)
                        Text(Strings.primaryTimeline).tag(Mode.timeline)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("where_year_segmented_control")
                }
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
}

#if DEBUG
    #Preview("Loaded") {
        YearView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Empty") {
        YearView(report: PreviewSupport.emptyYearReportModel())
    }
#endif
