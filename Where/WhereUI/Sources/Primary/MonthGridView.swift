import RegionKit
import SwiftUI
import WhereCore

/// One month section: weekday header row, a day grid, and a footer tallying the
/// days spent in each region that month.
struct MonthGridView: View {
    let month: CalendarMonth
    /// The region the calendar is focused on, if any — emphasized in the footer.
    var focusedRegion: Region?
    let dateCalendar: Calendar
    let plannedPresence: (CalendarDay) -> PlanningDayPresence?
    let planningSummary: [PlanningRegionSummary]
    var compact = false
    var isAvailable = true

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        compact ? stylesheet.calendar.compact : stylesheet.calendar
    }

    /// Resolve the month variant once so its background and inherited text
    /// treatment cannot drift apart.
    private var card: WhereStylesheet.CalendarStyle.MonthStyle.Card {
        month.isCurrentMonth ? calendar.month.current : calendar.month.plain
    }

    /// Shared by the fill and border so every month uses the same continuous
    /// corner geometry.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: calendar.month.cornerRadius, style: .continuous)
    }

    private var weekdaySymbols: [String] {
        guard compact else { return month.weekdaySymbols }
        let symbols = dateCalendar.veryShortStandaloneWeekdaySymbols
        let offset = dateCalendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthName: String {
        month.startOfMonth.formatted(.dateTime.month(.wide))
    }

    private var accessibility: CalendarMonthAccessibility {
        CalendarMonthAccessibility(
            month: month,
            calendar: dateCalendar,
            memberships: memberships(for:),
            planningSummary: planningSummary
                .filter { focusedRegion == nil || $0.region == focusedRegion },
        )
    }

    var body: some View {
        let monthAccessibility = accessibility

        VStack(alignment: .leading, spacing: calendar.month.sectionSpacing) {
            CalendarMonthHeading(
                name: monthName,
                compact: compact,
                isAvailable: isAvailable,
                foreground: card.foreground,
                overview: calendar.overview,
            )
            CalendarDayGrid(
                month: month,
                weekdaySymbols: weekdaySymbols,
                dateCalendar: dateCalendar,
                compact: compact,
                isAvailable: isAvailable,
                spacing: calendar.month.gridSpacing,
                weekdayFontSize: calendar.month.weekdayFontSize,
                dayHeight: calendar.day.minHeight,
                bandGeometry: bandGeometry(at:),
            )
            CalendarMonthSummary(
                totals: month.regionTotals,
                planningSummary: planningSummary,
                focusedRegion: focusedRegion,
                compact: compact,
            )
        }
        .padding(calendar.month.padding)
        .foregroundStyle(card.foreground)
        .background {
            // Transparent month cards share the screen background. The current
            // month stands out through its accent text and heavier border.
            CalendarMonthCardBackground(shape: cardShape, card: card)
        }
        .contentShape(cardShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monthAccessibility.label)
        .accessibilityValue(monthAccessibility.value)
    }

    /// The stay-pill geometry for the day at `index`: a run is contiguous days
    /// with the identical region set, so its true ends round fully while a run
    /// spilling across a week boundary rounds subtly (and same-row neighbours
    /// extend half the grid gap so the pill reads as one connected shape).
    private func bandGeometry(at index: Int) -> DayBandGeometry {
        let days = month.days
        let day = days[index]
        let regions = displayedRegions(for: day)
        guard !regions.isEmpty else { return .none }

        let regionSet = Set(regions)
        let projected = memberships(for: day)
        let column = (month.leadingBlankCount + index) % month.weekdayCount
        let isRowStart = column == 0
        let isRowEnd = column == month.weekdayCount - 1
        let joinsLeft = index > 0
            && Set(displayedRegions(for: days[index - 1])) == regionSet
            && memberships(for: days[index - 1]) == projected
        let joinsRight = index < days.count - 1
            && Set(displayedRegions(for: days[index + 1])) == regionSet
            && memberships(for: days[index + 1]) == projected

        let band = calendar.regionBand
        let halfGap = calendar.month.gridSpacing / 2
        return DayBandGeometry(
            regions: regions,
            memberships: projected,
            column: column,
            leadingRadius: joinsLeft ? (isRowStart ? band.continuationRadius : 0) : band
                .cornerRadius,
            trailingRadius: joinsRight ? (isRowEnd ? band.continuationRadius : 0) : band
                .cornerRadius,
            extendLeading: joinsLeft && !isRowStart ? halfGap : 0,
            extendTrailing: joinsRight && !isRowEnd ? halfGap : 0,
        )
    }

    private func displayedRegions(for day: CalendarDayCell) -> [Region] {
        Region.inCanonicalOrder(Set(day.regions).union(memberships(for: day).keys))
    }

    private func memberships(for day: CalendarDayCell) -> [Region: PlanningDayPresence.Membership] {
        let key = CalendarDay(from: day.date, in: dateCalendar)
        guard let presence = plannedPresence(key) else { return [:] }
        var regions = presence.possibleRegions
        if let home = presence.homeAssumption {
            regions.insert(home.region)
        }
        if let focusedRegion {
            regions = regions.intersection([focusedRegion])
        }
        return Dictionary(uniqueKeysWithValues: regions.compactMap { region in
            presence.membership(in: region).map { (region, $0) }
        })
    }
}

extension MonthGridView {
    /// Keep report-driven planning and focus identical in full calendars and month subjects.
    init(
        month: CalendarMonth,
        focusedRegion: Region?,
        report: YearReportModel,
        compact: Bool = false,
        isAvailable: Bool = true,
    ) {
        self.init(
            month: month,
            focusedRegion: focusedRegion,
            dateCalendar: report.calendar,
            plannedPresence: { day in
                guard report.showsEstimatedTimeAndPlanning else { return nil }
                return report.forecasts.plannedPresence(on: day)
            },
            planningSummary: report.showsEstimatedTimeAndPlanning
                ? report.forecasts.plannedRegionSummaries(in: month) : [],
            compact: compact,
            isAvailable: isAvailable,
        )
    }
}

private struct CalendarMonthHeading: View {
    let name: String
    let compact: Bool
    let isAvailable: Bool
    let foreground: Color
    let overview: WhereStylesheet.CalendarStyle.Overview

    var body: some View {
        Text(name)
            .font(compact ? .system(size: overview.titleFontSize, weight: .semibold) :
                .title.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isAvailable ? foreground : overview.unavailableForeground)
    }
}

private struct CalendarMonthCardBackground: View {
    let shape: RoundedRectangle
    let card: WhereStylesheet.CalendarStyle.MonthStyle.Card

    var body: some View {
        shape
            .fill(card.fill)
            .overlay {
                shape.strokeBorder(card.border, lineWidth: card.borderWidth)
            }
    }
}

private struct CalendarMonthSummary: View {
    let totals: [RegionDayTally]
    let planningSummary: [PlanningRegionSummary]
    let focusedRegion: Region?
    let compact: Bool

    var body: some View {
        if !compact, !totals.isEmpty {
            MonthFooter(totals: totals, focusedRegion: focusedRegion)
        }
        ForEach(
            (compact ? [] : planningSummary)
                .filter { focusedRegion == nil || $0.region == focusedRegion },
            id: \.region,
        ) { summary in
            CalendarMonthPlanningRows(summary: summary)
        }
    }
}

/// The per-month footer: one row per region present that month, showing its dot
/// color and how many days were spent there. The focused region (if any) is
/// emphasized so it stands out from the surrounding context rows.
private struct MonthFooter: View {
    let totals: [RegionDayTally]
    var focusedRegion: Region?

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.month.footerSpacing) {
            Divider()
                .padding(.bottom, calendar.month.footerDividerSpacing)
            ForEach(totals) { tally in
                CalendarMonthTallyRow(tally: tally, focusedRegion: focusedRegion)
            }
        }
    }
}

private struct CalendarMonthTallyRow: View {
    let tally: RegionDayTally
    let focusedRegion: Region?
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let isFocused = tally.region == focusedRegion
        let layout = calendar.month.stacksFooter
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: calendar.month.footerRowSpacing))
            : AnyLayout(HStackLayout(spacing: calendar.month.footerRowSpacing))
        layout {
            CalendarMonthTallyLabel(region: tally.region, isFocused: isFocused)
            if !calendar.month.stacksFooter {
                Spacer(minLength: 0)
            }
            Text(WhereFormat.dayCount(tally.days))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(focusedRegion == nil || isFocused ? 1 : calendar.month.unfocusedRowOpacity)
    }

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }
}

private struct CalendarMonthTallyLabel: View {
    let region: Region
    let isFocused: Bool
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        HStack(spacing: calendar.month.footerRowSpacing) {
            Circle()
                .fill(regionStyles.style(for: region).tint)
                .frame(width: calendar.dotSize, height: calendar.dotSize)
            Text(region.localizedName)
                .font(.subheadline)
                .fontWeight(isFocused ? .semibold : .regular)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }
}

#if DEBUG
    #Preview {
        CalendarContentView(report: PreviewSupport.loadedYearReportModel()).whereBroadwayRoot()
    }
#endif
