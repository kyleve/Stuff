import Foundation
import RegionKit
import WhereCore

/// Catalog-backed dialog copy for the intents — the spoken/written result Siri
/// reads back. Mirrors WhereUI's `Strings`: every value is a `String` resolved
/// from this module's `Resources/Localizable.xcstrings` (`bundle: .module`)
/// with an inline English `defaultValue`.
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
            case 0:
                return String(
                    localized: "dialog.daysInRegion.none",
                    defaultValue: "You have no days logged in \(name) so far in \(yearText).",
                    bundle: .module,
                )
            case 1:
                return String(
                    localized: "dialog.daysInRegion.one",
                    defaultValue: "You have 1 day in \(name) so far in \(yearText).",
                    bundle: .module,
                )
            default:
                return String(
                    localized: "dialog.daysInRegion.other",
                    defaultValue: "You have \(days) days in \(name) so far in \(yearText).",
                    bundle: .module,
                )
        }
    }

    // MARK: Region on a date

    static func regionsOnDate(_ date: Date, regions: [Region]) -> String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        guard !regions.isEmpty else {
            return String(
                localized: "dialog.regionOnDate.none",
                defaultValue: "Nothing is logged for \(dateText).",
                bundle: .module,
            )
        }
        return String(
            localized: "dialog.regionOnDate.some",
            defaultValue: "On \(dateText) you were in \(regionList(regions)).",
            bundle: .module,
        )
    }

    // MARK: Today

    static func today(regions: [Region]) -> String {
        guard !regions.isEmpty else {
            return String(
                localized: "dialog.today.none",
                defaultValue: "Nothing is logged for today yet.",
                bundle: .module,
            )
        }
        return String(
            localized: "dialog.today.some",
            defaultValue: "Today you've been in \(regionList(regions)).",
            bundle: .module,
        )
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
                String(
                    localized: "dialog.recentActivity.empty",
                    defaultValue: "Nothing was tracked in \(windowPhrase(window)).",
                    bundle: .module,
                )
        }
    }

    static func recentActivityUnavailable(_ reason: ActivitySummaryUnavailableReason) -> String {
        switch reason {
            case .deviceNotEligible:
                String(
                    localized: "dialog.recentActivity.unavailable.deviceNotEligible",
                    defaultValue: "This device doesn't support on-device summaries.",
                    bundle: .module,
                )
            case .appleIntelligenceNotEnabled:
                String(
                    localized: "dialog.recentActivity.unavailable.appleIntelligenceNotEnabled",
                    defaultValue: "Turn on Apple Intelligence in Settings to summarize where you've been.",
                    bundle: .module,
                )
            case .modelNotReady:
                String(
                    localized: "dialog.recentActivity.unavailable.modelNotReady",
                    defaultValue: "The on-device model is still getting ready. Try again shortly.",
                    bundle: .module,
                )
            case .unknown:
                String(
                    localized: "dialog.recentActivity.unavailable.unknown",
                    defaultValue: "On-device summaries aren't available right now.",
                    bundle: .module,
                )
        }
    }

    // MARK: Logging (action intents)

    /// The note stamped on a manual entry made from an intent. Persisted with
    /// the `ManualEntryAudit`, so a later residency audit shows how the day was
    /// recorded.
    static var manualEntryNote: String {
        String(localized: "audit.note.siri", defaultValue: "Logged with Siri", bundle: .module)
    }

    static func loggedDay(date: Date, regions: [Region]) -> String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        return String(
            localized: "dialog.logged.day",
            defaultValue: "Logged \(regionList(regions)) for \(dateText).",
            bundle: .module,
        )
    }

    static func loggedTrip(dayCount: Int, regions: [Region]) -> String {
        let list = regionList(regions)
        if dayCount == 1 {
            return String(
                localized: "dialog.logged.trip.one",
                defaultValue: "Logged \(list) for 1 day.",
                bundle: .module,
            )
        }
        return String(
            localized: "dialog.logged.trip.other",
            defaultValue: "Logged \(list) for \(dayCount) days.",
            bundle: .module,
        )
    }

    static func chooseRegions() -> String {
        String(
            localized: "dialog.logged.chooseRegions",
            defaultValue: "Tell me which regions to log.",
            bundle: .module,
        )
    }

    static func emptyTripRange() -> String {
        String(
            localized: "dialog.logged.emptyRange",
            defaultValue: "That date range doesn't include any days.",
            bundle: .module,
        )
    }

    // MARK: Snippet controls

    /// Title of the day-count snippet's action button, which logs today for the
    /// shown region.
    static var logTodayHere: String {
        String(localized: "snippet.logTodayHere", defaultValue: "Log today here", bundle: .module)
    }

    // MARK: Helpers

    /// Region names joined in a localized list, in `Region.allCases` order so
    /// multi-region output is stable ("California, New York, and Canada").
    private static func regionList(_ regions: [Region]) -> String {
        Region.allCases
            .filter(regions.contains)
            .map(\.localizedName)
            .formatted(.list(type: .and))
    }

    /// A natural-language phrase for a recent-activity window, for the empty
    /// dialog ("Nothing was tracked in the past week.").
    private static func windowPhrase(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day:
                String(
                    localized: "dialog.window.day",
                    defaultValue: "the last 24 hours",
                    bundle: .module,
                )
            case .week:
                String(
                    localized: "dialog.window.week",
                    defaultValue: "the past week",
                    bundle: .module,
                )
            case .month:
                String(
                    localized: "dialog.window.month",
                    defaultValue: "the past month",
                    bundle: .module,
                )
            case .yearToDate:
                String(
                    localized: "dialog.window.yearToDate",
                    defaultValue: "the year so far",
                    bundle: .module,
                )
        }
    }

    /// Year without a grouping separator ("2026", not "2,026") — matching how
    /// WhereUI renders years.
    private static func yearText(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }
}
