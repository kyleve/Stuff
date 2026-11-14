import BroadwayUI
import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Explicit month browsing controls for the Locations tabletop calendar.
struct MonthNavigationControls: View {
    let report: YearReportModel
    @Binding var monthReveal: CalendarMonthReveal?
    @BScrollPosition<
        CalendarPresentationState.Target,
        CalendarContentView.ScrollContext
    > private var position: ScrollPosition
    init(
        report: YearReportModel,
        monthReveal: Binding<CalendarMonthReveal?>,
        region: Region? = nil,
        scrollRole: CalendarContentView.ScrollRole = .year,
    ) {
        self.report = report
        _monthReveal = monthReveal
        _position = BScrollPosition(
            CalendarContentView.self,
            role: scrollRole,
            context: { CalendarContentView.ScrollContext(region: region, year: report.selectedYear)
            },
            idType: CalendarPresentationState.Target.self,
        )
    }

    @Environment(\.stylesheet) private var stylesheet

    private var month: CalendarDay {
        if let day = monthReveal?.month ?? position
            .viewID(type: CalendarPresentationState.Target.self)?.month
        {
            return CalendarDay(year: day.year, month: day.month, day: 1)
        }
        let today = CalendarDay(from: report.referenceDate, in: report.calendar)
        return CalendarDay(
            year: report.selectedYear,
            month: today.year == report.selectedYear ? today.month : 12,
            day: 1,
        )
    }

    var body: some View {
        HStack {
            Button(String(localized: .adaptiveMonthPrevious), systemSymbol: .chevronBackward) {
                select(month.month - 1)
            }
            .disabled(month.month == 1)
            .labelStyle(.iconOnly)
            Spacer(minLength: stylesheet.spacing.small)
            Menu {
                ForEach(1 ... 12, id: \.self) { candidate in
                    Button(title(for: candidate)) { select(candidate) }
                }
            } label: {
                Text(title(for: month.month))
                    .font(.headline)
            }
            .accessibilityLabel(String(localized: .adaptiveMonthPicker))
            .accessibilityValue(title(for: month.month))
            Spacer(minLength: stylesheet.spacing.small)
            Button(String(localized: .adaptiveMonthNext), systemSymbol: .chevronForward) {
                select(month.month + 1)
            }
            .disabled(month.month == 12)
            .labelStyle(.iconOnly)
        }
        .padding(stylesheet.spacing.medium)
        .background(.bar)
    }

    private func title(for month: Int) -> String {
        CalendarDay(year: report.selectedYear, month: month, day: 1)
            .startOfDay(in: report.calendar).formatted(Date.FormatStyle(
                calendar: report.calendar,
                timeZone: report.calendar.timeZone,
            ).month(.wide).year())
    }

    private func select(_ month: Int) {
        monthReveal = CalendarMonthReveal(
            month: CalendarDay(year: report.selectedYear, month: month, day: 1),
        )
    }
}

#if DEBUG
    #Preview {
        MonthNavigationControls(
            report: PreviewSupport.loadedYearReportModel(),
            monthReveal: .constant(nil),
        )
        .whereBroadwayRoot()
    }
#endif
