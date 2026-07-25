import Foundation
import RegionKit
import WhereCore

/// Catalog-backed dialog copy for the intents — the spoken/written result Siri
/// reads back. Composes this module's generated `LocalizedStringResource`
/// symbols (from `Resources/Localizable.xcstrings`) with runtime values, so a
/// removed or renamed key is a compile error.
///
/// This is only the *runtime* copy. Static App Intents metadata (intent titles,
/// parameter titles, enum/entity display names) can't route through here — the
/// framework requires those to be compile-time-constant literals and localizes
/// them through its own extraction. Region names always come from
/// `Region.localizedName`.
enum IntentStrings {
    // MARK: Days in region

    static func daysInRegion(region: Region, days: Int, year: Int) -> String {
        let name = region.localizedName
        let yearText = yearText(year)
        switch days {
            case 0: return String(localized: .dialogDaysInRegionNone(name, yearText))
            case 1: return String(localized: .dialogDaysInRegionOne(name, yearText))
            default: return String(localized: .dialogDaysInRegionOther(days, name, yearText))
        }
    }

    // MARK: Region on a date

    static func regionsOnDate(_ date: Date, regions: [Region]) -> String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        guard !regions.isEmpty else {
            return String(localized: .dialogRegionOnDateNone(dateText))
        }
        return String(localized: .dialogRegionOnDateSome(dateText, regionList(regions)))
    }

    // MARK: Today

    static func today(regions: [Region]) -> String {
        guard !regions.isEmpty else {
            return String(localized: .dialogTodayNone)
        }
        return String(localized: .dialogTodaySome(regionList(regions)))
    }

    // MARK: Recent activity

    static func recentActivity(
        _ summary: RecentActivitySummary,
        window: RecentActivityWindow,
    ) -> String {
        switch summary {
            case let .summary(text):
                text
            case .empty:
                String(localized: .dialogRecentActivityEmpty(windowPhrase(window)))
        }
    }

    static func recentActivityUnavailable(_ reason: ActivitySummaryUnavailableReason) -> String {
        switch reason {
            case .deviceNotEligible:
                String(localized: .dialogRecentActivityUnavailableDeviceNotEligible)
            case .appleIntelligenceNotEnabled:
                String(localized: .dialogRecentActivityUnavailableAppleIntelligenceNotEnabled)
            case .modelNotReady:
                String(localized: .dialogRecentActivityUnavailableModelNotReady)
            case .unknown:
                String(localized: .dialogRecentActivityUnavailableUnknown)
        }
    }

    // MARK: Logging (action intents)

    /// The note stamped on a manual entry made from an intent. Persisted with
    /// the `ManualEntryAudit`, so a later residency audit shows how the day was
    /// recorded.
    static var manualEntryNote: String {
        String(localized: .auditNoteSiri)
    }

    static func loggedDay(date: Date, regions: [Region]) -> String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        return String(localized: .dialogLoggedDay(regionList(regions), dateText))
    }

    static func loggedTrip(dayCount: Int, regions: [Region]) -> String {
        let list = regionList(regions)
        if dayCount == 1 {
            return String(localized: .dialogLoggedTripOne(list))
        }
        return String(localized: .dialogLoggedTripOther(list, dayCount))
    }

    static func chooseRegions() -> String {
        String(localized: .dialogLoggedChooseRegions)
    }

    static func emptyTripRange() -> String {
        String(localized: .dialogLoggedEmptyRange)
    }

    // MARK: Snippet controls

    /// Title of the day-count snippet's action button, which logs today for the
    /// shown region.
    static var logTodayHere: String {
        String(localized: .snippetLogTodayHere)
    }

    // MARK: Helpers

    /// Region names joined in a localized list, in the catalog's canonical order
    /// so multi-region output is stable ("California, New York, and Canada").
    private static func regionList(_ regions: [Region]) -> String {
        Region.inCanonicalOrder(regions)
            .map(\.localizedName)
            .formatted(.list(type: .and))
    }

    /// A natural-language phrase for a recent-activity window, for the empty
    /// dialog ("Nothing was tracked in the past week.").
    private static func windowPhrase(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day: String(localized: .dialogWindowDay)
            case .week: String(localized: .dialogWindowWeek)
            case .month: String(localized: .dialogWindowMonth)
            case .yearToDate: String(localized: .dialogWindowYearToDate)
        }
    }

    /// Year without a grouping separator ("2026", not "2,026") — matching how
    /// WhereUI renders years.
    private static func yearText(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }
}
