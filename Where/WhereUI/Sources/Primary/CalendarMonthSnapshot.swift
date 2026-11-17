#if DEBUG
    import RegionKit
    import SwiftUI
    import WhereCore

    /// A complete month from the same report and renderer as the scrollable calendar.
    struct CalendarMonthSnapshot: View {
        let report: YearReportModel
        let focusedRegion: Region?
        private let month: CalendarMonth

        init(report: YearReportModel, monthNumber: Int, focusedRegion: Region? = nil) {
            self.report = report
            self.focusedRegion = focusedRegion
            guard let yearReport = report.report else {
                preconditionFailure("Month snapshots require a loaded report")
            }
            do {
                let months = try CalendarModel(report: report, persistenceKey: nil)
                    .months(from: yearReport, focusedRegion: focusedRegion).get()
                guard let month = months.first(where: { $0.month == monthNumber }) else {
                    preconditionFailure("Month \(monthNumber) is missing from the fixture")
                }
                self.month = month
            } catch {
                preconditionFailure("Invalid calendar fixture: \(error)")
            }
        }

        var body: some View {
            MonthGridView(month: month, focusedRegion: focusedRegion, report: report)
                .padding()
                .whereContentRoot()
                .background(Color(.systemBackground))
        }
    }

    #Preview {
        CalendarMonthSnapshot(report: PreviewSupport.loadedYearReportModel(), monthNumber: 5)
            .whereBroadwayRoot()
    }
#endif
