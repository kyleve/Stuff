import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

struct CalendarMonthPlanningRows: View {
    let summary: PlanningRegionSummary
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.calendar.month.footerSpacing) {
            if summary.plannedDays.upper > 0 {
                CalendarMonthPlanningRow(
                    region: summary.region,
                    days: summary.plannedDays,
                    kind: summary.plannedDays.isExact
                        ? .planningCalendarPlanned : .planningCalendarPossible,
                    symbol: summary.plannedDays.isExact ? .lineDiagonal : .circleDashed,
                )
            }
            if summary.homeDays.upper > 0 {
                CalendarMonthPlanningRow(
                    region: summary.region,
                    days: summary.homeDays,
                    kind: .planningCalendarHome,
                    symbol: .house,
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct CalendarMonthPlanningRow: View {
    let region: Region
    let days: DayBounds
    let kind: LocalizedStringResource
    let symbol: SFSymbol
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let title = String(localized: .planningCalendarMonthSummary(
            region.localizedName,
            String(localized: kind),
        ))
        if stylesheet.calendar.month.stacksFooter {
            VStack(alignment: .leading, spacing: stylesheet.calendar.month.footerSpacing) {
                Label(title, systemSymbol: symbol)
                    .fixedSize(horizontal: false, vertical: true)
                Text(WhereFormat.dayCount(days))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent {
                Text(WhereFormat.dayCount(days))
            } label: {
                Label(title, systemSymbol: symbol)
            }
        }
    }
}

#if DEBUG
    #Preview("Planned and assumed days") {
        CalendarMonthSnapshot(report: PreviewSupport.itineraryYearReportModel(), monthNumber: 10)
            .whereBroadwayRoot()
    }
#endif
