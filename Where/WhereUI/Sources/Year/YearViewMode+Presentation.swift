import WhereCore

extension YearViewMode {
    var title: String {
        switch self {
            case .calendar: String(localized: .primaryCalendar)
            case .timeline: String(localized: .primaryTimeline)
            case .breakdown: String(localized: .yearBreakdownTitle)
            case .heatmap: String(localized: .yearHeatmapTitle)
        }
    }

    var systemImage: String {
        switch self {
            case .calendar: "calendar"
            case .timeline: "calendar.day.timeline.left"
            case .breakdown: "chart.pie.fill"
            case .heatmap: "square.grid.3x3.fill"
        }
    }
}
