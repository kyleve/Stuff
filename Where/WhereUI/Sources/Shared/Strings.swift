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

    static var commonOK: String {
        localized("common.ok")
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

    static var primaryElsewhereOnlyTitle: String {
        localized("primary.elsewhereOnly.title")
    }

    /// Shown when there's tracked data, but none of it lands in a primary
    /// region — points the user at the Elsewhere tab.
    static func primaryElsewhereOnlyDescription(count: Int) -> String {
        String(
            localized: "primary.elsewhereOnly.description",
            defaultValue: "\(count) days logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
            bundle: .module,
        )
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

    static var settingsStatusTracking: String {
        localized("settings.status.tracking")
    }

    static var settingsStatusAlwaysPaused: String {
        localized("settings.status.alwaysPaused")
    }

    static var settingsStatusWhenInUse: String {
        localized("settings.status.whenInUse")
    }

    static var settingsStatusNotDetermined: String {
        localized("settings.status.notDetermined")
    }

    static var settingsStatusDenied: String {
        localized("settings.status.denied")
    }

    static var settingsStatusRestricted: String {
        localized("settings.status.restricted")
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

    static var manualSaveErrorTitle: String {
        localized("manual.saveError.title")
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

    // MARK: Missing days

    static var missingDaysTitle: String {
        String(localized: "missingDays.title", defaultValue: "Missing days", bundle: .module)
    }

    static var missingDaysDone: String {
        String(localized: "missingDays.done", defaultValue: "Done", bundle: .module)
    }

    static var missingDaysHeader: String {
        String(localized: "missingDays.header", defaultValue: "Days to backfill", bundle: .module)
    }

    static var missingDaysFooter: String {
        String(
            localized: "missingDays.footer",
            defaultValue: "Tap a stretch to record where you were. Today is included until something logs it.",
            bundle: .module,
        )
    }

    static var missingDaysEmptyTitle: String {
        String(localized: "missingDays.empty.title", defaultValue: "All caught up", bundle: .module)
    }

    static var missingDaysEmptyDescription: String {
        String(
            localized: "missingDays.empty.description",
            defaultValue: "Every day this year has something logged.",
            bundle: .module,
        )
    }

    // MARK: Missing-day banner

    static var missingBannerTitle: String {
        String(
            localized: "missing.banner.title",
            defaultValue: "Missing days this year",
            bundle: .module,
        )
    }

    static func missingBannerSubtitle(count: Int) -> String {
        if count == 1 {
            String(
                localized: "missing.banner.subtitle.one",
                defaultValue: "1 day still needs a location. Tap to fill it in.",
                bundle: .module,
            )
        } else {
            String(
                localized: "missing.banner.subtitle.other",
                defaultValue: "\(count) days still need a location. Tap to fill them in.",
                bundle: .module,
            )
        }
    }

    static var missingBannerAccessibilityHint: String {
        String(
            localized: "missing.banner.accessibilityHint",
            defaultValue: "Opens the list of days that still need logging.",
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
