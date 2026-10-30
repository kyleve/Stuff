import RegionKit
import SFSafeSymbols
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
    @Environment(\.whereComponentStylesheet) private var components

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
            monthHeading; dayGrid; monthSummary
        }
        .padding(calendar.month.padding)
        .foregroundStyle(card.foreground)
        .whereThemePanel(
            .calendarMonth,
            in: cardShape,
            tint: components[.calendarMonth].foreground ?? .primary,
        ) {
            if components[.calendarMonth].surface == nil,
               components[.calendarMonth].background == nil { cardShape.fill(card.fill) }
        }
        .overlay { cardShape.strokeBorder(card.border, lineWidth: card.borderWidth) }
        .contentShape(cardShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monthAccessibility.label)
        .accessibilityValue(monthAccessibility.value)
    }

    private var monthHeading: some View {
        Text(monthName)
            .font(compact ? .system(size: calendar.overview.titleFontSize, weight: .semibold) :
                (components[.calendarMonth].heading ?? .title.weight(.semibold)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isAvailable ? card.foreground : calendar.overview
                .unavailableForeground)
    }

    private var monthSummary: some View {
        Group {
            if !compact, !month.regionTotals.isEmpty {
                MonthFooter(totals: month.regionTotals, focusedRegion: focusedRegion)
            }
            ForEach(
                (compact ? [] : planningSummary)
                    .filter { focusedRegion == nil || $0.region == focusedRegion },
                id: \.region,
            ) { summary in
                VStack(alignment: .leading, spacing: calendar.month.footerSpacing) {
                    if summary.plannedDays.upper > 0 {
                        planningSummaryRow(
                            region: summary.region,
                            days: summary.plannedDays,
                            kind: summary.plannedDays.isExact
                                ? .planningCalendarPlanned : .planningCalendarPossible,
                            symbol: summary.plannedDays.isExact ? .lineDiagonal : .circleDashed,
                        )
                    }
                    if summary.homeDays.upper > 0 {
                        planningSummaryRow(
                            region: summary.region,
                            days: summary.homeDays,
                            kind: .planningCalendarHome,
                            symbol: .house,
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.whereSecondary)
            }
        }
    }

    /// A month has at most six weeks. Eager rows keep its intrinsic height exact
    /// while a zoom destination is offscreen or covered by the transition overlay.
    private var dayGrid: some View {
        let weekCount = compact ? 6 :
            (month.leadingBlankCount + month.days.count + month.weekdayCount - 1) / month
            .weekdayCount
        return Grid(
            horizontalSpacing: calendar.month.gridSpacing,
            verticalSpacing: calendar.month.gridSpacing,
        ) {
            GridRow {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: calendar.month.weekdayFontSize))
                        .lineLimit(1)
                        .foregroundStyle(.whereSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0 ..< weekCount, id: \.self) { week in
                GridRow {
                    ForEach(0 ..< month.weekdayCount, id: \.self) { weekday in
                        let index = week * month.weekdayCount + weekday - month.leadingBlankCount
                        if month.days.indices.contains(index) {
                            DayCell(
                                day: month.days[index],
                                band: bandGeometry(at: index),
                                dateCalendar: dateCalendar,
                                compact: compact,
                                isAvailable: isAvailable,
                            )

                        } else {
                            Color.clear
                                .frame(height: calendar.day.minHeight)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planningSummaryRow(
        region: Region,
        days: DayBounds,
        kind: LocalizedStringResource,
        symbol: SFSymbol,
    ) -> some View {
        let title = String(localized: .planningCalendarMonthSummary(
            region.localizedName,
            String(localized: kind),
        ))
        if calendar.month.stacksFooter {
            VStack(alignment: .leading, spacing: calendar.month.footerSpacing) {
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
        if let home = presence.homeAssumption { regions.insert(home.region) }
        if let focusedRegion { regions = regions.intersection([focusedRegion]) }
        return Dictionary(uniqueKeysWithValues: regions.compactMap { region in
            presence.membership(in: region).map { (region, $0) }
        })
    }
}

/// How to draw a day's slice of the region "stay" pill: which corners round
/// (the run's ends) and how far to bleed into the grid gaps so a run reads as
/// one connected shape. Empty `regions` means no pill.
struct DayBandGeometry {
    var regions: [Region]
    var memberships: [Region: PlanningDayPresence.Membership]
    var isPlanned: Bool {
        !memberships.isEmpty
    }

    var hasPossible: Bool {
        memberships.values.contains { membership in
            switch membership {
                case .planned(.possible), .homeAssumed(.possible): true
                case .planned(.certain), .homeAssumed(.certain): false
            }
        }
    }

    var column: Int
    var leadingRadius: CGFloat
    var trailingRadius: CGFloat
    var extendLeading: CGFloat
    var extendTrailing: CGFloat

    static let none = DayBandGeometry(
        regions: [],
        memberships: [:],
        column: 0,
        leadingRadius: 0,
        trailingRadius: 0,
        extendLeading: 0,
        extendTrailing: 0,
    )
}

/// The per-month footer: one row per region present that month, showing its dot
/// color and how many days were spent there. The focused region (if any) is
/// emphasized so it stands out from the surrounding context rows.
private struct MonthFooter: View {
    let totals: [RegionDayTally]
    var focusedRegion: Region?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.month.footerSpacing) {
            Divider()
                .padding(.bottom, calendar.month.footerDividerSpacing)
            ForEach(totals) { tally in
                row(for: tally)
            }
        }
    }

    private func row(for tally: RegionDayTally) -> some View {
        let isFocused = tally.region == focusedRegion
        let layout = calendar.month.stacksFooter
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: calendar.month.footerRowSpacing))
            : AnyLayout(HStackLayout(spacing: calendar.month.footerRowSpacing))
        return layout {
            HStack(spacing: calendar.month.footerRowSpacing) {
                Circle()
                    .fill(regionStyles.style(for: tally.region).tint)
                    .frame(
                        width: calendar.dotSize,
                        height: calendar.dotSize,
                    )
                Text(tally.region.localizedName)
                    .font(.subheadline)
                    .fontWeight(isFocused ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !calendar.month.stacksFooter {
                Spacer(minLength: 0)
            }
            Text(WhereFormat.dayCount(tally.days))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.whereSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(focusedRegion == nil || isFocused ? 1 : calendar.month.unfocusedRowOpacity)
    }
}

/// One day in the month grid: the day number, region-presence dots beneath it,
/// and a subtle region-tinted "stay" pill behind it that connects to adjacent
/// days in the same run so a stretch in one place reads as a single shape.
struct DayCell: View {
    let day: CalendarDayCell
    /// The stay-pill slice for this day (computed by the enclosing month).
    let band: DayBandGeometry
    let dateCalendar: Calendar
    var compact = false
    var isAvailable = true

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        compact ? stylesheet.calendar.compact : stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.day.numberDotSpacing) {
            Text("\(day.dayOfMonth)")
                .font(.system(size: calendar.day.numberFontSize))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(dayNumberColor)
                .frame(
                    width: compact ? nil : calendar.day.numberSize,
                    height: calendar.day.numberSize,
                )
                .background {
                    if day.isToday {
                        Circle()
                            .fill(calendar.day.todayMarker)
                    } else if day.needsAttention {
                        Circle()
                            .fill(calendar.day.unresolvedMarker)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !compact, day.hasEvidence || day.hasFlight {
                        HStack(spacing: calendar.day.badge.iconSpacing) {
                            if day.hasEvidence {
                                badgeIcon(.paperclip)
                            }
                            if day.hasFlight {
                                badgeIcon(.airplane)
                            }
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(calendar.day.badge.padding)
                        .background(Capsule().fill(Color(.systemBackground)))
                        // Keep the first icon at the corner; additional icons
                        // extend to the right without covering the day number.
                        .offset(badgeOffset)
                    }
                }

            dots
        }
        // Pad the content, then back it with the pill so the pill hugs the
        // content with a little vertical breathing room (rather than butting
        // into the dots); the outer frame is the tap target.
        .frame(maxWidth: .infinity)
        .padding(.vertical, calendar.regionBand.verticalInset)
        .background { stayPill }
        .frame(minHeight: calendar.day.minHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(Date.FormatStyle(
            date: .complete,
            time: .omitted,
            calendar: dateCalendar,
            timeZone: dateCalendar.timeZone,
        )))
        .accessibilityValue(accessibilitySummary)
    }

    private var badgeOffset: CGSize {
        let extraWidth = day.hasEvidence && day.hasFlight
            ? calendar.day.badge.iconSize + calendar.day.badge.iconSpacing
            : 0
        return CGSize(
            width: calendar.day.badge.offset.width + extraWidth,
            height: calendar.day.badge.offset.height,
        )
    }

    private func badgeIcon(_ symbol: SFSymbol) -> some View {
        Image(systemSymbol: symbol)
            .font(.system(size: calendar.day.badge.iconSize, weight: .bold))
            .frame(width: calendar.day.badge.iconSize, height: calendar.day.badge.iconSize)
    }

    private var accessibilitySummary: String {
        var values = band.regions.map { region in
            guard let membership = band.memberships[region] else { return region.localizedName }
            return String(localized: .planningCalendarMonthSummary(
                region.localizedName,
                WhereFormat.planningMembership(membership),
            ))
        }
        if day.hasEvidence { values.append(String(localized: .calendarAttachmentAccessibility)) }
        if day.hasFlight { values.append(String(localized: .historyFlight)) }
        return values.joined(separator: "; ")
    }

    /// Region-presence dots beneath the day number (one per region the day
    /// counts for), each with a subtle background-colored rim. On a multi-region
    /// day the dots overlap into a cluster, the rims keeping them distinct.
    /// Empty days keep the row height so the grid baseline is even.
    private var dots: some View {
        let isCluster = band.regions.count > 1
        return HStack(spacing: isCluster ? -calendar.day.dotOverlap : calendar.day.contentSpacing) {
            ForEach(band.regions, id: \.self) { region in
                Group {
                    switch band.memberships[region] {
                        case .homeAssumed:
                            Image(systemSymbol: .houseFill)
                                .resizable()
                                .scaledToFit()
                        case .planned(.possible):
                            Circle().strokeBorder(lineWidth: calendar.day.dotStrokeWidth)
                        case .planned(.certain), nil:
                            Circle()
                    }
                }
                .foregroundStyle(regionStyles.style(for: region).tint)
                .frame(width: calendar.day.dotSize, height: calendar.day.dotSize)
            }
        }
        .frame(height: calendar.day.dotSize)
    }

    /// The subtle region-tinted pill spanning this day's slice of a stay run —
    /// tinted per region (a soft blend on multi-region days), its corners
    /// rounded per `band`, inset vertically, and bled `extend…` points into the
    /// grid gaps so same-run neighbours join into one shape. A `GeometryReader`
    /// gives the exact cell size to size and offset the overflow precisely.
    @ViewBuilder
    private var stayPill: some View {
        if !band.regions.isEmpty {
            GeometryReader { proxy in
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: band.leadingRadius,
                    bottomLeadingRadius: band.leadingRadius,
                    bottomTrailingRadius: band.trailingRadius,
                    topTrailingRadius: band.trailingRadius,
                )
                ZStack {
                    shape
                        .fill(pillFill)
                        .opacity(
                            band.isPlanned
                                ? calendar.regionBand.planned.fillOpacity
                                : calendar.regionBand.opacity,
                        )
                    if band.isPlanned {
                        PlannedStayHatch(
                            color: band.regions
                                .first
                                .map { regionStyles.style(for: $0).tint } ?? .accentColor,
                            spacing: calendar.regionBand.planned.hatchSpacing,
                            lineWidth: calendar.regionBand.planned.hatchLineWidth,
                            gridOriginX: CGFloat(band.column)
                                * (proxy.size.width + calendar.month.gridSpacing)
                                - band.extendLeading,
                        )
                        .opacity(calendar.regionBand.planned.hatchOpacity)
                        .clipShape(shape)
                    }
                    if band.hasPossible {
                        shape.strokeBorder(
                            band.regions.first
                                .map { regionStyles.style(for: $0).tint } ?? .accentColor,
                            style: StrokeStyle(
                                lineWidth: calendar.regionBand.planned.hatchLineWidth,
                                dash: [calendar.regionBand.planned.hatchSpacing],
                            ),
                        )
                    }
                }
                .frame(
                    width: proxy.size.width + band.extendLeading + band.extendTrailing,
                    height: proxy.size.height,
                )
                .offset(x: -band.extendLeading)
            }
        }
    }

    /// The pill's tint: one region reads as a solid wash; a multi-region day
    /// (rare — a travel day) softly blends its regions left-to-right.
    private var pillFill: LinearGradient {
        LinearGradient(
            colors: band.regions.map { regionStyles.style(for: $0).tint },
            startPoint: .leading,
            endPoint: .trailing,
        )
    }

    private var dayNumberColor: Color {
        if day.isToday {
            calendar.day.todayNumberColor
        } else if day.needsAttention {
            calendar.day.unresolvedNumberColor
        } else {
            isAvailable ? .primary : calendar.overview.unavailableForeground
        }
    }
}

#if DEBUG
    #Preview {
        CalendarContentView(report: PreviewSupport.loadedYearReportModel()).whereBroadwayRoot()
    }
#endif
