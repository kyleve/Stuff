import Foundation

/// Localized, catalog-backed strings for WhereUI.
///
/// Every user-facing string in the module is funneled through here so the
/// views stay free of literals and so lookups resolve against the module's
/// `Resources/Localizable.xcstrings` (`bundle: .module`). Counts use the
/// catalog's plural variations; years are formatted with a grouping-free
/// number style so they read "2026", never "2,026".
enum Strings {
    // MARK: Tabs

    static var tabPrimary: String {
        localized("tab.primary")
    }

    static var tabElsewhere: String {
        localized("tab.elsewhere")
    }

    static var tabSettings: String {
        localized("tab.settings")
    }

    // MARK: Shared

    static var loadErrorTitle: String {
        localized("common.loadError.title")
    }

    /// "1 day" / "5 days" — with the count rendered.
    static func dayCount(_ count: Int) -> String {
        String(localized: "common.dayCount", defaultValue: "\(count) days", bundle: .module)
    }

    /// "day" / "days" — the bare unit, when the count is shown separately.
    static func dayUnit(_ count: Int) -> String {
        count == 1 ? localized("common.day") : localized("common.days")
    }

    static func regionDaysAccessibility(region: String, days: Int) -> String {
        String(
            localized: "common.regionDays.accessibility",
            defaultValue: "\(region): \(dayCount(days))",
            bundle: .module,
        )
    }

    // MARK: Primary

    static var primaryTitle: String {
        localized("primary.title")
    }

    static var primaryTimeline: String {
        localized("primary.timeline")
    }

    static var primaryLoading: String {
        localized("primary.loading")
    }

    static var primaryEmptyDescription: String {
        localized("primary.empty.description")
    }

    static var primaryCaptionHomeBase: String {
        localized("primary.caption.homeBase")
    }

    static var primaryCaptionSecondHome: String {
        localized("primary.caption.secondHome")
    }

    static func primaryEmptyTitle(year: Int) -> String {
        String(
            localized: "primary.empty.title",
            defaultValue: "No travels logged for \(yearText(year))",
            bundle: .module,
        )
    }

    static func primaryHeaderTitle(year: Int) -> String {
        String(
            localized: "primary.header.title",
            defaultValue: "Where have you been in \(yearText(year))?",
            bundle: .module,
        )
    }

    static func primaryHeaderSubtitle(count: Int) -> String {
        String(
            localized: "primary.header.subtitle",
            defaultValue: "\(count) days on the map so far",
            bundle: .module,
        )
    }

    // MARK: Elsewhere

    static var secondaryTitle: String {
        localized("secondary.title")
    }

    static var secondaryLoading: String {
        localized("secondary.loading")
    }

    static var secondaryEmptyTitle: String {
        localized("secondary.empty.title")
    }

    static var secondaryEmptyDescription: String {
        localized("secondary.empty.description")
    }

    static var secondaryCaptionPassingThrough: String {
        localized("secondary.caption.passingThrough")
    }

    static func secondaryHeader(year: Int) -> String {
        String(
            localized: "secondary.header",
            defaultValue: "Everywhere else you turned up in \(yearText(year)).",
            bundle: .module,
        )
    }

    // MARK: Settings

    static var settingsTitle: String {
        localized("settings.title")
    }

    static var settingsPermissionAlertTitle: String {
        localized("settings.permissionAlert.title")
    }

    static var settingsPermissionAlertMessage: String {
        localized("settings.permissionAlert.message")
    }

    static var settingsPermissionAlertOpenSettings: String {
        localized("settings.permissionAlert.openSettings")
    }

    static var settingsPermissionAlertNotNow: String {
        localized("settings.permissionAlert.notNow")
    }

    static var settingsLocationHeader: String {
        localized("settings.location.header")
    }

    static var settingsLocationToggle: String {
        localized("settings.location.toggle")
    }

    static var settingsLocationGrant: String {
        localized("settings.location.grant")
    }

    static var settingsLocationFooter: String {
        localized("settings.location.footer")
    }

    static var settingsManualHeader: String {
        localized("settings.manual.header")
    }

    static var settingsManualLink: String {
        localized("settings.manual.link")
    }

    static var settingsManualFooter: String {
        localized("settings.manual.footer")
    }

    static var settingsDataHeader: String {
        localized("settings.data.header")
    }

    static var settingsDataCancel: String {
        localized("settings.data.cancel")
    }

    static func settingsDataErase(year: Int) -> String {
        String(
            localized: "settings.data.erase",
            defaultValue: "Erase \(yearText(year)) data",
            bundle: .module,
        )
    }

    static func settingsDataConfirmMessage(year: Int) -> String {
        String(
            localized: "settings.data.confirmMessage",
            defaultValue: "This removes every sample, manual day, and piece of evidence in \(yearText(year)). It can't be undone.",
            bundle: .module,
        )
    }

    static func settingsDataFooter(year: Int) -> String {
        String(
            localized: "settings.data.footer",
            defaultValue: "Acts on the year selected on the Primary tab (\(yearText(year))).",
            bundle: .module,
        )
    }

    // MARK: Manual entry

    static var manualEntryPickerLabel: String {
        localized("manual.entry.pickerLabel")
    }

    static var manualModeSingleDay: String {
        localized("manual.mode.singleDay")
    }

    static var manualModeRange: String {
        localized("manual.mode.range")
    }

    static var manualDay: String {
        localized("manual.day")
    }

    static var manualFrom: String {
        localized("manual.from")
    }

    static var manualThrough: String {
        localized("manual.through")
    }

    static var manualSingleDayFooter: String {
        localized("manual.singleDay.footer")
    }

    static var manualRegionsHeader: String {
        localized("manual.regions.header")
    }

    static var manualRegionsFooter: String {
        localized("manual.regions.footer")
    }

    static var manualTitle: String {
        localized("manual.title")
    }

    static var manualSave: String {
        localized("manual.save")
    }

    static func manualRangeFooter(count: Int) -> String {
        String(
            localized: "manual.range.footer",
            defaultValue: "Backfilling \(count) days.",
            bundle: .module,
        )
    }

    // MARK: Timeline

    static var timelineDone: String {
        localized("timeline.done")
    }

    static var timelineEmptyTitle: String {
        localized("timeline.empty.title")
    }

    static var timelineEmptyDescription: String {
        localized("timeline.empty.description")
    }

    static func timelineTitle(year: Int) -> String {
        String(
            localized: "timeline.title",
            defaultValue: "Timeline · \(yearText(year))",
            bundle: .module,
        )
    }

    static func timelineRowAccessibility(region: String, range: String, days: Int) -> String {
        String(
            localized: "timeline.row.accessibility",
            defaultValue: "\(region), \(range), \(dayCount(days))",
            bundle: .module,
        )
    }

    // MARK: Helpers

    private static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    /// Year without a grouping separator ("2026", not "2,026").
    private static func yearText(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }
}
