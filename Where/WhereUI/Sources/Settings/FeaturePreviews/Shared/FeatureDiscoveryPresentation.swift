import Foundation
import RegionKit
import WhereCore

/// Personalizes the feature galleries once a report contains enough recorded
/// days to make the user's own data more useful than canned examples.
struct FeatureDiscoveryPresentation {
    struct SiriExample: Equatable {
        let request: String
        let response: String
    }

    struct SpotlightExample: Equatable {
        let query: String
        let resultTitle: String
        let resultSubtitle: String
    }

    /// Two weeks of recorded days is enough to make counts and widget totals
    /// representative rather than incidental.
    static let minimumLoggedDayCount = 14

    let usesUserData: Bool
    let widgetSnapshot: WidgetSnapshot
    let lockScreenDate: Date
    let spotlightExample: SpotlightExample

    private let siriExamples: [SiriIntentFeature: SiriExample]

    init(
        report: YearReport?,
        selectedYear: Int,
        referenceDate: Date,
        calendar: Calendar,
    ) {
        let referenceDay = CalendarDay(from: referenceDate, in: calendar)
        let relevantDays = report.map { loadedReport in
            loadedReport.year == referenceDay.year
                ? loadedReport.days.filter { $0.day <= referenceDay }
                : loadedReport.days
        } ?? []
        let fallbackDay = referenceDay.year == selectedYear
            ? referenceDay
            : CalendarDay(year: selectedYear, month: 1, day: 1)
        let fallbackDate = Self.date(
            for: fallbackDay,
            clockFrom: referenceDate,
            calendar: calendar,
        )

        guard
            let report,
            report.year == selectedYear,
            relevantDays.count >= Self.minimumLoggedDayCount
        else {
            usesUserData = false
            widgetSnapshot = WidgetSnapshot(
                day: fallbackDay.startOfDay(in: calendar),
                year: selectedYear,
                dayRegions: [],
                totals: [:],
            )
            lockScreenDate = fallbackDate
            spotlightExample = SpotlightExample(
                query: Region.california.localizedName,
                resultTitle: String(localized: .settingsExploreSpotlightResultTitle(
                    Region.california.localizedName,
                )),
                resultSubtitle: String(localized: .settingsExploreSpotlightResultGeneric),
            )
            siriExamples = [:]
            return
        }

        usesUserData = true
        let snapshotDay = referenceDay.year == report.year
            ? referenceDay
            : relevantDays[relevantDays.index(before: relevantDays.endIndex)].day
        let dayRegions = relevantDays.first { $0.day == snapshotDay }?.regions ?? []
        widgetSnapshot = WidgetSnapshot(
            day: snapshotDay.startOfDay(in: calendar),
            year: report.year,
            dayRegions: dayRegions,
            totals: report.totals,
        )
        lockScreenDate = Self.date(
            for: snapshotDay,
            clockFrom: referenceDate,
            calendar: calendar,
        )
        spotlightExample = Self.spotlightExample(report: report)
        siriExamples = Self.siriExamples(
            report: report,
            relevantDays: relevantDays,
            referenceDay: referenceDay,
            calendar: calendar,
        )
    }

    private static func spotlightExample(report: YearReport) -> SpotlightExample {
        guard let region = RegionRanking(report: report).primary.first else {
            return SpotlightExample(
                query: Region.california.localizedName,
                resultTitle: String(localized: .settingsExploreSpotlightResultTitle(
                    Region.california.localizedName,
                )),
                resultSubtitle: String(localized: .settingsExploreSpotlightResultGeneric),
            )
        }
        return SpotlightExample(
            query: region.region.localizedName,
            resultTitle: String(localized: .settingsExploreSpotlightResultTitle(
                region.region.localizedName,
            )),
            resultSubtitle: String(localized: .settingsExploreSpotlightResultPersonalized(
                WhereFormat.dayCount(region.days),
                WhereFormat.yearText(report.year),
            )),
        )
    }

    func siriExample(for item: SiriIntentFeature) -> SiriExample? {
        siriExamples[item]
    }

    private static func siriExamples(
        report: YearReport,
        relevantDays: [DayPresence],
        referenceDay: CalendarDay,
        calendar: Calendar,
    ) -> [SiriIntentFeature: SiriExample] {
        var examples: [SiriIntentFeature: SiriExample] = [:]

        if report.year == referenceDay.year {
            let regions = relevantDays.first { $0.day == referenceDay }?.regions ?? []
            let response = regions.isEmpty
                ? String(localized: .settingsExploreSiriPersonalizedTodayResponseEmpty)
                : String(localized: .settingsExploreSiriPersonalizedTodayResponseRegions(
                    regionList(regions),
                ))
            examples[.todayRegions] = SiriExample(
                request: String(localized: .settingsExploreSiriTodayRequest),
                response: response,
            )
        }

        let ranking = RegionRanking(report: report)
        if let region = ranking.primary.first {
            let year = WhereFormat.yearText(report.year)
            examples[.daysInRegion] = SiriExample(
                request: String(localized: .settingsExploreSiriPersonalizedDaysRequest(
                    region.region.localizedName,
                    year,
                )),
                response: String(localized: .settingsExploreSiriPersonalizedDaysResponse(
                    WhereFormat.dayCount(region.days),
                    region.region.localizedName,
                    year,
                )),
            )
        }

        if let latestDay = relevantDays.last {
            let date = latestDay.startOfDay(in: calendar)
            let dateText = date.formatted(.dateTime.month(.wide).day().year())
            examples[.regionOnDate] = SiriExample(
                request: String(localized: .settingsExploreSiriPersonalizedDateRequest(dateText)),
                response: String(localized: .settingsExploreSiriPersonalizedDateResponse(
                    dateText,
                    regionList(latestDay.regions),
                )),
            )
        }

        return examples
    }

    private static func regionList(_ regions: some Sequence<Region>) -> String {
        Region.inCanonicalOrder(regions)
            .map(\.localizedName)
            .formatted(.list(type: .and))
    }

    /// Combines the report day with the real/pinned clock. Widget snapshots are
    /// start-of-day values, but a fake Lock Screen needs a meaningful time.
    private static func date(
        for day: CalendarDay,
        clockFrom referenceDate: Date,
        calendar: Calendar,
    ) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: referenceDate)
        var components = DateComponents(year: day.year, month: day.month, day: day.day)
        components.hour = clock.hour
        components.minute = clock.minute
        guard let date = calendar.date(from: components) else {
            assertionFailure("Calendar could not resolve feature-discovery date \(day)")
            return day.startOfDay(in: calendar)
        }
        return date
    }
}
