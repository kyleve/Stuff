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

    /// The Primary tab's masthead wordmark.
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

    // MARK: Passport bio page

    /// The bio-data page's subtitle line, e.g. "Document of Presence · 2026".
    static func passportSubtitle(year: Int) -> String {
        String(
            localized: "passport.subtitle",
            defaultValue: "Document of Presence · \(yearText(year))",
            bundle: .module,
        )
    }

    static var passportFieldYear: String {
        String(localized: "passport.field.year", defaultValue: "Year", bundle: .module)
    }

    static var passportFieldDaysLogged: String {
        String(
            localized: "passport.field.daysLogged",
            defaultValue: "Days logged",
            bundle: .module,
        )
    }

    static var passportFieldRegions: String {
        String(localized: "passport.field.regions", defaultValue: "Regions", bundle: .module)
    }

    static var passportFieldCoverage: String {
        String(localized: "passport.field.coverage", defaultValue: "Coverage", bundle: .module)
    }

    /// The booklet page footer, e.g. "P. 02 / 03".
    static func passportPageFooter(page: Int, count: Int) -> String {
        let pageText = String(format: "%02d", page)
        let countText = String(format: "%02d", count)
        return String(
            localized: "passport.page.footer",
            defaultValue: "P. \(pageText) / \(countText)",
            bundle: .module,
        )
    }

    /// Spoken counterpart of the page footer, e.g. "Page 2 of 3".
    static func passportPageAccessibility(page: Int, count: Int) -> String {
        String(
            localized: "passport.page.accessibility",
            defaultValue: "Page \(page) of \(count)",
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

    // MARK: Elsewhere region detail

    static var secondaryRegionFooter: String {
        String(
            localized: "secondary.region.footer",
            defaultValue: "Tap a day to fix where it counted. Your GPS data stays untouched.",
            bundle: .module,
        )
    }

    static var secondaryRegionEmptyTitle: String {
        String(
            localized: "secondary.region.empty.title",
            defaultValue: "Nothing to fix",
            bundle: .module,
        )
    }

    static var secondaryRegionEmptyDescription: String {
        String(
            localized: "secondary.region.empty.description",
            defaultValue: "No days counted for this region.",
            bundle: .module,
        )
    }

    /// Caption on a day row showing the regions it currently counts for, e.g.
    /// "Counts as California, New York".
    static func secondaryRegionCurrent(regions: String) -> String {
        String(
            localized: "secondary.region.current",
            defaultValue: "Counts as \(regions)",
            bundle: .module,
        )
    }

    /// Accessibility label for the map of recorded points on the region
    /// drill-in.
    static var secondaryRegionMapAccessibility: String {
        String(
            localized: "secondary.region.map.accessibility",
            defaultValue: "Map of where you were",
            bundle: .module,
        )
    }

    // MARK: Relabel

    static var relabelTitle: String {
        String(localized: "relabel.title", defaultValue: "Fix this day", bundle: .module)
    }

    static var relabelRegionsHeader: String {
        String(
            localized: "relabel.regions.header",
            defaultValue: "Where were you?",
            bundle: .module,
        )
    }

    static var relabelRegionsFooter: String {
        String(
            localized: "relabel.regions.footer",
            defaultValue: "This replaces what was recorded for this day, overriding GPS. Your raw location data is kept, so you can change it back.",
            bundle: .module,
        )
    }

    static var relabelReset: String {
        String(
            localized: "relabel.reset",
            defaultValue: "Reset to GPS-detected location",
            bundle: .module,
        )
    }

    static var relabelResetFooter: String {
        String(
            localized: "relabel.reset.footer",
            defaultValue: "Removes any manual correction for this day and restores the regions detected from GPS. Your raw location data is untouched.",
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

    static var settingsRemindersHeader: String {
        String(localized: "settings.reminders.header", defaultValue: "Reminders", bundle: .module)
    }

    static var settingsRemindersToggle: String {
        String(
            localized: "settings.reminders.toggle",
            defaultValue: "Daily logging reminder",
            bundle: .module,
        )
    }

    static var settingsReminderTime: String {
        String(localized: "settings.reminders.time", defaultValue: "Remind me at", bundle: .module)
    }

    static var settingsRemindersFooter: String {
        String(
            localized: "settings.reminders.footer",
            defaultValue: "If a day hasn't been logged, we'll nudge you before it ends and badge the app. The reminder clears itself once the day is recorded.",
            bundle: .module,
        )
    }

    static var settingsRemindersOpenSettings: String {
        String(
            localized: "settings.reminders.openSettings",
            defaultValue: "Allow notifications",
            bundle: .module,
        )
    }

    static var settingsRemindersDeniedFooter: String {
        String(
            localized: "settings.reminders.deniedFooter",
            defaultValue: "Notifications are turned off for Where, so reminders and the badge can't appear. Turn them on in Settings.",
            bundle: .module,
        )
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

    // MARK: Settings backup

    static var settingsBackupHeader: String {
        localized("settings.backup.header")
    }

    static var settingsBackupFooter: String {
        localized("settings.backup.footer")
    }

    static var settingsBackupExport: String {
        localized("settings.backup.export")
    }

    /// Title shown in the system share sheet preview for an exported backup.
    static var settingsBackupShareTitle: String {
        localized("settings.backup.shareTitle")
    }

    static var settingsBackupImport: String {
        localized("settings.backup.import")
    }

    static var settingsBackupImporting: String {
        localized("settings.backup.importing")
    }

    static var settingsBackupErrorTitle: String {
        localized("settings.backup.errorTitle")
    }

    static var settingsBackupImportStrategyTitle: String {
        localized("settings.backup.importStrategy.title")
    }

    static var settingsBackupImportStrategyMessage: String {
        localized("settings.backup.importStrategy.message")
    }

    static var settingsBackupMerge: String {
        localized("settings.backup.merge")
    }

    static var settingsBackupReplace: String {
        localized("settings.backup.replace")
    }

    static var settingsBackupImportedTitle: String {
        localized("settings.backup.imported.title")
    }

    static func settingsBackupImportedMessage(
        samples: Int,
        evidence: Int,
        manualDays: Int,
    ) -> String {
        String(
            localized: "settings.backup.imported.message",
            defaultValue: "Imported \(samples) location samples, \(evidence) pieces of evidence, and \(manualDays) manual days.",
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

    static func missingBannerCompact(count: Int) -> String {
        if count == 1 {
            String(
                localized: "missing.banner.compact.one",
                defaultValue: "1 day needs a location",
                bundle: .module,
            )
        } else {
            String(
                localized: "missing.banner.compact.other",
                defaultValue: "\(count) days need a location",
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
