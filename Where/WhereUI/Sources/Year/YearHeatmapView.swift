import SnapshotKit
import SwiftUI
import WhereCore

/// A GitHub-style whole-year grid: one row per month and aligned day-of-month
/// columns, with tap/drag inspection that stays on the same screen.
struct YearHeatmapView: View {
    let overview: YearOverview
    let calendar: Calendar

    @State private var selectedDayID: CalendarDay?

    @Environment(\.stylesheet) private var stylesheet

    init(
        overview: YearOverview,
        calendar: Calendar,
        initialSelection: CalendarDay? = nil,
    ) {
        self.overview = overview
        self.calendar = calendar
        _selectedDayID = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: stylesheet.spacing.xxLarge) {
                YearHeatmapChart(
                    overview: overview,
                    calendar: calendar,
                    selectedDayID: $selectedDayID,
                )

                if let selectedDay {
                    YearHeatmapSelectionCard(day: selectedDay, calendar: calendar)
                        .transition(.opacity)
                }

                YearHeatmapLegend(overview: overview)
            }
            .padding()
        }
        .animation(stylesheet.yearOverview.picker.contentAnimation, value: selectedDayID)
        .onChange(of: overview.year) { _, _ in selectedDayID = nil }
    }

    private var selectedDay: YearOverview.Day? {
        guard let selectedDayID else { return nil }
        return overview.day(month: selectedDayID.month, dayOfMonth: selectedDayID.day)
    }
}

#if DEBUG
    extension YearHeatmapView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .screenDefaults) {
                let model = PreviewSupport.loadedYearReportModel()
                NavigationStack {
                    YearHeatmapView(
                        overview: PreviewSupport.loadedYearOverview(),
                        calendar: model.calendar,
                    )
                    .navigationTitle(String(localized: .yearHeatmapTitle))
                }
            }
            whereSnapshot(name: "Selected", configurations: .phoneLightDark) {
                let model = PreviewSupport.missingDaysYearReportModel()
                NavigationStack {
                    YearHeatmapView(
                        overview: PreviewSupport.missingDaysYearOverview(),
                        calendar: model.calendar,
                        initialSelection: CalendarDay(year: 2026, month: 1, day: 4),
                    )
                    .navigationTitle(String(localized: .yearHeatmapTitle))
                }
            }
            whereSnapshot(name: "MultiRegion", configurations: .phoneLightDark) {
                let model = PreviewSupport.missingDaysYearReportModel()
                NavigationStack {
                    YearHeatmapView(
                        overview: PreviewSupport.multiRegionYearOverview(),
                        calendar: model.calendar,
                        initialSelection: CalendarDay(year: 2026, month: 1, day: 2),
                    )
                    .navigationTitle(String(localized: .yearHeatmapTitle))
                }
            }
        }
    }

    #Preview {
        YearHeatmapView.snapshotPreviews
    }
#endif

#if DEBUG
    extension YearHeatmapView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            YearHeatmapView.self,
            title: "Heatmap",
        )
    }
#endif
