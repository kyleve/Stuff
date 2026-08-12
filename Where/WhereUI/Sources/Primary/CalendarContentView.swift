import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A scrollable year calendar: one month grid per month, with colored dots for
/// each region present on a day, and a per-month footer tallying the days spent
/// in each region. Chrome-free (no `NavigationStack`) so the host owns the
/// navigation: the Your Year tab embeds it inline, and the Locations tab pushes
/// it — region-focused, with a title — as the zoom destination of a tapped card.
struct CalendarContentView: View {
    /// When set, the day grid only shows dots for this region (so it reads as
    /// "just the days I spent here"); the per-month footer still lists every
    /// region. `nil` shows every region's dots.
    var focusedRegion: Region?

    let report: YearReportModel

    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @Environment(\.stylesheet) private var stylesheet
    @State private var monthsLoad: Result<[CalendarMonth], Error>?
    @State private var showingPlannedStayEditor = false
    @State private var didRevealCurrentMonth = false

    private static let logger = WhereLog.session(CalendarViewLog.self)

    /// Inputs that invalidate a cached month grid.
    private struct CalendarLoadID: Equatable {
        let report: YearReport
        let missingDayKeys: Set<CalendarDay>
        let evidenceDayKeys: Set<CalendarDay>
        let referenceDay: Date
        let focusedRegion: Region?
    }

    var body: some View {
        Group {
            if let yearReport = report.report {
                Group {
                    switch monthsLoad {
                        case let .success(months):
                            calendarContent(months: months)
                        case let .failure(error):
                            calendarLayoutError(error)
                        case nil:
                            AppIconLoadingView(caption: String(localized: .primaryLoading))
                    }
                }
                .task(id: calendarLoadID(report: yearReport)) {
                    let result = loadCalendarMonths(from: yearReport)
                    guard !Task.isCancelled else { return }
                    monthsLoad = result
                }
            } else if report.loadState == .loading {
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            } else if case let .failed(error) = report.loadState {
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(error.message)
                }
            } else {
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(String(localized: .calendarUnavailableDescription))
                }
                .onAppear {
                    Self.logger {
                        .openedWithoutReport(loadState: String(describing: report.loadState))
                    }
                }
            }
        }
        // Log View Mode: reveal an inspect badge for this calendar's events. A
        // no-op in release.
        .debugLogInspectable(WhereLog.session(CalendarViewLog.self))
        .sheet(isPresented: $showingPlannedStayEditor) {
            if let focusedRegion {
                PlannedStayEditor(region: focusedRegion, model: report.forecasts)
            }
        }
    }

    private func calendarLoadID(report yearReport: YearReport) -> CalendarLoadID {
        CalendarLoadID(
            report: yearReport,
            missingDayKeys: report.missingDayKeys,
            evidenceDayKeys: report.evidenceDayKeys,
            referenceDay: report.calendar.startOfDay(for: report.referenceDate),
            focusedRegion: focusedRegion,
        )
    }

    private func loadCalendarMonths(from yearReport: YearReport) -> Result<[CalendarMonth], Error> {
        Result {
            try yearReport.calendarMonths(
                calendar: report.calendar,
                referenceDate: report.referenceDate,
                missingDates: report.missingDayKeys,
                evidenceDays: report.evidenceDayKeys,
                focusedRegion: focusedRegion,
            )
        }
    }

    private func calendarLayoutError(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(String(localized: .commonLoadErrorTitle), systemSymbol: .exclamationmarkIcloud)
        } description: {
            Text(String(localized: .calendarUnavailableDescription))
        }
        .onAppear {
            Self.logger { .layoutFailed(description: String(describing: error)) }
        }
    }

    private func calendarContent(months: [CalendarMonth]) -> some View {
        let visibleMonths = shownMonths(months)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: stylesheet.calendar.monthSpacing) {
                    ForEach(visibleMonths) { month in
                        VStack(spacing: stylesheet.calendar.monthSpacing) {
                            MonthGridView(
                                month: month,
                                focusedRegion: focusedRegion,
                                dateCalendar: report.calendar,
                                plannedRegion: report.forecasts.plannedRegion(on:),
                            )
                            // In chronological flow, the estimate belongs immediately
                            // after the month whose recorded pace it is projecting from.
                            if month.isCurrentMonth, let focusedForecast {
                                LocationForecastPanel(
                                    forecasts: [focusedForecast],
                                    plannedStay: report.forecasts.activePlannedStay,
                                    editableRegion: report.forecasts.isCurrent(
                                        focusedForecast.region,
                                        report: report.report,
                                    ) ? focusedForecast.region : nil,
                                    editAction: {
                                        showingPlannedStayEditor = true
                                    },
                                )
                            }
                        }
                        .id(month.id)
                    }
                }
                .padding()
            }
            .task {
                // Full-content snapshots expand the scroll view to show every
                // month, so applying a viewport offset during measurement would
                // clip the otherwise production-identical calendar content.
                guard !isCapturingSnapshot,
                      !didRevealCurrentMonth,
                      let currentMonth = visibleMonths.first(where: \.isCurrentMonth)
                else { return }

                // Wait for the lazy stack to install its scroll targets before
                // positioning the current month and the estimate beneath it.
                await Task.yield()
                guard !Task.isCancelled else { return }
                didRevealCurrentMonth = true
                proxy.scrollTo(currentMonth.id, anchor: .bottom)
            }
        }
    }

    private var focusedForecast: LocationForecast? {
        guard let focusedRegion else { return nil }
        return report.forecasts.forecast(for: focusedRegion, report: report.report)
    }

    /// A plan belongs on the selected year's calendar and, when this is a
    /// region-focused calendar, only on that region's destination.
    private var displayedPlannedStay: PlannedStay? {
        guard let year = report.report?.year else { return nil }
        guard let stay = report.forecasts.plannedStay(intersecting: year) else { return nil }
        guard focusedRegion == nil || focusedRegion == stay.region else { return nil }
        return stay
    }

    /// The months to show in chronological order. Future months are omitted
    /// unless a planned stay reaches into them; a past year shows the full year.
    private func shownMonths(_ months: [CalendarMonth]) -> [CalendarMonth] {
        guard
            let currentMonthStart = report.calendar
            .dateInterval(of: .month, for: report.referenceDate)?
            .start
        else {
            return months
        }
        let lastShownMonth = displayedPlannedStay.flatMap { stay in
            report.calendar.date(from: DateComponents(
                year: stay.through.year,
                month: stay.through.month,
                day: 1,
            ))
        }.map { max(currentMonthStart, $0) } ?? currentMonthStart
        return months.filter { $0.startOfMonth <= lastShownMonth }
    }
}

/// One month section: weekday header row, a day grid, and a footer tallying the
/// days spent in each region that month.
private struct MonthGridView: View {
    let month: CalendarMonth
    /// The region the calendar is focused on, if any — emphasized in the footer.
    var focusedRegion: Region?
    let dateCalendar: Calendar
    let plannedRegion: (CalendarDay) -> Region?

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
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

    var body: some View {
        VStack(alignment: .leading, spacing: calendar.month.sectionSpacing) {
            Text(month.startOfMonth.formatted(.dateTime.month(.wide)))
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: calendar.month.gridSpacing),
                    count: month.weekdayCount,
                ),
                spacing: calendar.month.gridSpacing,
            ) {
                ForEach(month.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0 ..< month.leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(minHeight: calendar.day.minHeight)
                }

                ForEach(Array(month.days.enumerated()), id: \.element.id) { index, day in
                    DayCell(day: day, band: bandGeometry(at: index))
                }
            }

            if !month.regionTotals.isEmpty {
                MonthFooter(totals: month.regionTotals, focusedRegion: focusedRegion)
            }
        }
        .padding(calendar.month.padding)
        .foregroundStyle(card.foreground)
        .background {
            // Past months use the plain card; the current one gets the accent
            // card (bluer wash, text, and heavier border).
            cardShape
                .fill(card.fill)
                .overlay {
                    cardShape.strokeBorder(card.border, lineWidth: card.borderWidth)
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
        let isPlanned = plannedRegion(on: day) != nil
        let column = (month.leadingBlankCount + index) % month.weekdayCount
        let isRowStart = column == 0
        let isRowEnd = column == month.weekdayCount - 1
        let joinsLeft = index > 0
            && Set(displayedRegions(for: days[index - 1])) == regionSet
            && (plannedRegion(on: days[index - 1]) != nil) == isPlanned
        let joinsRight = index < days.count - 1
            && Set(displayedRegions(for: days[index + 1])) == regionSet
            && (plannedRegion(on: days[index + 1]) != nil) == isPlanned

        let band = calendar.regionBand
        let halfGap = calendar.month.gridSpacing / 2
        return DayBandGeometry(
            regions: regions,
            isPlanned: isPlanned,
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
        var regions = Set(day.regions)
        if let region = plannedRegion(on: day) {
            regions.insert(region)
        }
        return Region.inCanonicalOrder(regions)
    }

    private func plannedRegion(on day: CalendarDayCell) -> Region? {
        let key = CalendarDay(from: day.date, in: dateCalendar)
        guard let region = plannedRegion(key) else { return nil }
        guard focusedRegion == nil || focusedRegion == region else { return nil }
        return region
    }
}

/// How to draw a day's slice of the region "stay" pill: which corners round
/// (the run's ends) and how far to bleed into the grid gaps so a run reads as
/// one connected shape. Empty `regions` means no pill.
private struct DayBandGeometry {
    var regions: [Region]
    var isPlanned: Bool
    var column: Int
    var leadingRadius: CGFloat
    var trailingRadius: CGFloat
    var extendLeading: CGFloat
    var extendTrailing: CGFloat

    static let none = DayBandGeometry(
        regions: [],
        isPlanned: false,
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
        return HStack(spacing: calendar.month.footerRowSpacing) {
            Circle()
                .fill(regionStyles.style(for: tally.region).tint)
                .frame(
                    width: calendar.dotSize,
                    height: calendar.dotSize,
                )
            Text(tally.region.localizedName)
                .font(.subheadline)
                .fontWeight(isFocused ? .semibold : .regular)
            Spacer(minLength: 0)
            Text(WhereFormat.dayCount(tally.days))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(focusedRegion == nil || isFocused ? 1 : calendar.month.unfocusedRowOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            WhereFormat.regionDaysAccessibility(
                region: tally.region.localizedName,
                days: tally.days,
            ),
        )
    }
}

/// One day in the month grid: the day number, region-presence dots beneath it,
/// and a subtle region-tinted "stay" pill behind it that connects to adjacent
/// days in the same run so a stretch in one place reads as a single shape.
private struct DayCell: View {
    let day: CalendarDayCell
    /// The stay-pill slice for this day (computed by the enclosing month).
    let band: DayBandGeometry

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.day.numberDotSpacing) {
            Text("\(day.dayOfMonth)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(dayNumberColor)
                .frame(width: calendar.day.numberSize, height: calendar.day.numberSize)
                .background {
                    if day.isToday {
                        Circle()
                            .fill(calendar.day.todayMarker)
                    } else if day.needsAttention {
                        Circle()
                            .fill(calendar.day.unresolvedMarker)
                    }
                }
                // A day carrying an attachment gets a small paperclip badge in
                // the top-trailing corner, on a filled disc so it stays legible
                // over the accent "today" fill and the region dots below.
                .overlay(alignment: .topTrailing) {
                    if day.hasEvidence {
                        Image(systemSymbol: .paperclip)
                            .font(.system(size: calendar.day.evidenceBadge.iconSize, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(calendar.day.evidenceBadge.padding)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(
                                x: calendar.day.evidenceBadge.offset.width,
                                y: calendar.day.evidenceBadge.offset.height,
                            )
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
        .accessibilityLabel(
            WhereFormat.calendarDayAccessibility(
                date: day.date,
                regions: band.regions,
                needsAttention: day.needsAttention,
                hasEvidence: day.hasEvidence,
                isPlanned: band.isPlanned,
            ),
        )
    }

    /// Region-presence dots beneath the day number (one per region the day
    /// counts for), each with a subtle background-colored rim. On a multi-region
    /// day the dots overlap into a cluster, the rims keeping them distinct.
    /// Empty days keep the row height so the grid baseline is even.
    private var dots: some View {
        let isCluster = band.regions.count > 1
        return HStack(spacing: isCluster ? -calendar.day.dotOverlap : calendar.day.contentSpacing) {
            ForEach(band.regions, id: \.self) { region in
                Circle()
                    .fill(regionStyles.style(for: region).tint)
                    .frame(width: calendar.day.dotSize, height: calendar.day.dotSize)
                    .overlay {
                        Circle().stroke(
                            Color(.systemBackground),
                            lineWidth: calendar.day.dotStrokeWidth,
                        )
                    }
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
            .primary
        }
    }
}

#if DEBUG
    extension CalendarContentView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithData", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.loadedYearReportModel())
                }
            }
            whereSnapshot(name: "Empty", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.emptyYearReportModel())
                }
            }
            whereSnapshot(name: "MissingDays", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.missingDaysYearReportModel())
                }
            }
            // The Locations tab's zoom destination: one region's days only.
            whereSnapshot(name: "Focused", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(
                        focusedRegion: .california,
                        report: PreviewSupport.loadedYearReportModel(),
                    )
                }
            }
            whereSnapshot(name: "FocusedPlannedStay", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(
                        focusedRegion: .newYork,
                        report: PreviewSupport.plannedStayYearReportModel(),
                    )
                }
            }
        }
    }

    #Preview {
        CalendarContentView.snapshotPreviews
    }
#endif

#if DEBUG
    extension CalendarContentView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            CalendarContentView.self,
            title: "Region Calendar",
        )

        static let yearFlyoverData = WhereFlyoverData.snapshots(
            CalendarContentView.self,
            id: WhereFlyoverScreenID(CalendarContentView.self, in: YearView.self),
            title: "Calendar",
        )
    }
#endif
