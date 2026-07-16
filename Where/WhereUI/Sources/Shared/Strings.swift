import Foundation
import RegionKit
import WhereCore

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

    static var tabResolution: String {
        localized("tab.resolution")
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

    static var commonDone: String {
        localized("common.done")
    }

    static var commonCancel: String {
        String(localized: "common.cancel", defaultValue: "Cancel", bundle: .module)
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

    static var primaryTimeline: String {
        localized("primary.timeline")
    }

    static var primaryRecentActivity: String {
        String(
            localized: "primary.recentActivity",
            defaultValue: "Recent activity",
            bundle: .module,
        )
    }

    /// Accessibility hint on a Primary region card: tapping it opens that
    /// region's calendar, filtered to the days spent there.
    static var primaryCardCalendarHint: String {
        String(
            localized: "primary.card.calendarHint",
            defaultValue: "Opens the calendar of days spent here.",
            bundle: .module,
        )
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

    static func primaryEmptyTitle(year: Int) -> String {
        String(
            localized: "primary.empty.title",
            defaultValue: "No travels logged for \(yearText(year))",
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

    // MARK: Manual-entry audit (read-back)

    static var auditHeader: String {
        String(localized: "audit.header", defaultValue: "Entry record", bundle: .module)
    }

    static var auditRecordedAt: String {
        String(localized: "audit.recordedAt", defaultValue: "Recorded", bundle: .module)
    }

    static var auditNote: String {
        String(localized: "audit.note", defaultValue: "Note", bundle: .module)
    }

    static var auditLocation: String {
        String(localized: "audit.location", defaultValue: "Made at", bundle: .module)
    }

    static var auditLocationUnavailable: String {
        String(
            localized: "audit.location.unavailable",
            defaultValue: "Not captured",
            bundle: .module,
        )
    }

    /// A "37.77490, -122.41940"-style coordinate label. No catalog entry is
    /// needed; the number style is locale-driven, like `driftThresholdLabel`.
    static func auditCoordinate(latitude: Double, longitude: Double) -> String {
        let lat = latitude.formatted(.number.precision(.fractionLength(5)))
        let lon = longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(lat), \(lon)"
    }

    // MARK: Onboarding

    static var onboardingWelcomeTitle: String {
        String(
            localized: "onboarding.welcome.title",
            defaultValue: "Where have you been?",
            bundle: .module,
        )
    }

    static var onboardingWelcomeDescription: String {
        String(
            localized: "onboarding.welcome.description",
            defaultValue: "Where keeps a private passport of which regions you spend your days in — built for residency and day-count questions.",
            bundle: .module,
        )
    }

    static var onboardingAutomaticTitle: String {
        String(
            localized: "onboarding.automatic.title",
            defaultValue: "It logs itself",
            bundle: .module,
        )
    }

    static var onboardingAutomaticDescription: String {
        String(
            localized: "onboarding.automatic.description",
            defaultValue: "With background location, Where quietly notes the regions you pass through. You can always add or correct days by hand.",
            bundle: .module,
        )
    }

    static var onboardingPrivacyTitle: String {
        String(
            localized: "onboarding.privacy.title",
            defaultValue: "Private by design",
            bundle: .module,
        )
    }

    static var onboardingPrivacyDescription: String {
        String(
            localized: "onboarding.privacy.description",
            defaultValue: "Your location stays on your device and in your own iCloud. Turn on background location to start your passport.",
            bundle: .module,
        )
    }

    static var onboardingContinue: String {
        String(localized: "onboarding.continue", defaultValue: "Continue", bundle: .module)
    }

    static var onboardingEnableLocation: String {
        String(
            localized: "onboarding.enableLocation",
            defaultValue: "Enable Location",
            bundle: .module,
        )
    }

    static var onboardingNotNow: String {
        String(localized: "onboarding.notNow", defaultValue: "Not Now", bundle: .module)
    }

    static var onboardingBack: String {
        String(localized: "onboarding.back", defaultValue: "Back", bundle: .module)
    }

    static var onboardingNext: String {
        String(localized: "onboarding.next", defaultValue: "Next", bundle: .module)
    }

    static var onboardingRestoreBackup: String {
        String(
            localized: "onboarding.restoreBackup",
            defaultValue: "Restore from a backup",
            bundle: .module,
        )
    }

    static var onboardingRestoreErrorTitle: String {
        String(
            localized: "onboarding.restoreError.title",
            defaultValue: "Couldn't restore backup",
            bundle: .module,
        )
    }

    static var onboardingRestoring: String {
        String(localized: "onboarding.restoring", defaultValue: "Restoring…", bundle: .module)
    }

    static var onboardingRegionsTitle: String {
        String(
            localized: "onboarding.regions.title",
            defaultValue: "Where do you spend your time?",
            bundle: .module,
        )
    }

    static var onboardingLocationTitle: String {
        String(
            localized: "onboarding.location.title",
            defaultValue: "Turn on location",
            bundle: .module,
        )
    }

    static var onboardingLocationDescription: String {
        String(
            localized: "onboarding.location.description",
            defaultValue: "Where uses background location to log the regions you pass through. You can change this anytime in Settings.",
            bundle: .module,
        )
    }

    // MARK: Region picker

    static var regionPickerTitle: String {
        String(localized: "regionPicker.title", defaultValue: "Your regions", bundle: .module)
    }

    static var regionPickerSubtitle: String {
        String(
            localized: "regionPicker.subtitle",
            defaultValue: "Pick up to 5 regions where you spend your time.",
            bundle: .module,
        )
    }

    static var regionPickerModeMap: String {
        String(localized: "regionPicker.mode.map", defaultValue: "Map", bundle: .module)
    }

    static var regionPickerModeList: String {
        String(localized: "regionPicker.mode.list", defaultValue: "List", bundle: .module)
    }

    /// Accessibility label for the map/list mode switch.
    static var regionPickerModePicker: String {
        String(localized: "regionPicker.mode.picker", defaultValue: "View", bundle: .module)
    }

    static var regionPickerSearchPrompt: String {
        String(
            localized: "regionPicker.search.prompt",
            defaultValue: "Search regions",
            bundle: .module,
        )
    }

    /// "2 of 5 selected".
    static func regionPickerSelectionCount(selected: Int, max: Int) -> String {
        String(
            localized: "regionPicker.selectionCount",
            defaultValue: "\(selected) of \(max) selected",
            bundle: .module,
        )
    }

    /// Shown when the selection is full, so an ignored tap on a new region reads
    /// as "at capacity" rather than "unresponsive".
    static func regionPickerAtCapacity(max: Int) -> String {
        String(
            localized: "regionPicker.atCapacity",
            defaultValue: "That's the maximum of \(max) — deselect one to choose another.",
            bundle: .module,
        )
    }

    static var regionPickerMapAccessibility: String {
        String(
            localized: "regionPicker.map.accessibility",
            defaultValue: "Map for picking your regions",
            bundle: .module,
        )
    }

    static var regionPickerEmptyTitle: String {
        String(
            localized: "regionPicker.empty.title",
            defaultValue: "No matching regions",
            bundle: .module,
        )
    }

    static var regionPickerLoadErrorTitle: String {
        String(
            localized: "regionPicker.loadError.title",
            defaultValue: "Couldn't load the map",
            bundle: .module,
        )
    }

    // MARK: Region customization

    static var regionCustomizeTitle: String {
        String(localized: "regionCustomize.title", defaultValue: "Make it yours", bundle: .module)
    }

    /// "Choose a look for California".
    static func regionCustomizeSubtitle(region: String) -> String {
        String(
            localized: "regionCustomize.subtitle",
            defaultValue: "Choose a look for \(region)",
            bundle: .module,
        )
    }

    static var regionCustomizeColor: String {
        String(localized: "regionCustomize.color", defaultValue: "Color", bundle: .module)
    }

    static var regionCustomizeEmoji: String {
        String(localized: "regionCustomize.emoji", defaultValue: "Emoji", bundle: .module)
    }

    static var regionCustomizeSymbol: String {
        String(localized: "regionCustomize.symbol", defaultValue: "Icon", bundle: .module)
    }

    /// "Region 2 of 5".
    static func regionCustomizeStep(current: Int, total: Int) -> String {
        String(
            localized: "regionCustomize.step",
            defaultValue: "Region \(current) of \(total)",
            bundle: .module,
        )
    }

    static func regionColorAccessibility(_ token: RegionColorToken) -> String {
        String(
            localized: "regionCustomize.color.accessibility",
            defaultValue: "Color \(token.rawValue)",
            bundle: .module,
        )
    }

    // MARK: Region management (Settings)

    static var regionsManageTitle: String {
        String(localized: "regions.manage.title", defaultValue: "Your regions", bundle: .module)
    }

    static var settingsRegionsSection: String {
        String(localized: "settings.regions.section", defaultValue: "Regions", bundle: .module)
    }

    static var settingsRegionsRow: String {
        String(
            localized: "settings.regions.row",
            defaultValue: "Primary regions",
            bundle: .module,
        )
    }

    static var settingsRegionsEmpty: String {
        String(localized: "settings.regions.empty", defaultValue: "None yet", bundle: .module)
    }

    static var commonSave: String {
        String(localized: "common.save", defaultValue: "Save", bundle: .module)
    }

    // MARK: Migration

    static var migrationTitle: String {
        String(
            localized: "migration.title",
            defaultValue: "Updating your data…",
            bundle: .module,
        )
    }

    static var migrationSubtitle: String {
        String(
            localized: "migration.subtitle",
            defaultValue: "This only takes a moment.",
            bundle: .module,
        )
    }

    // MARK: Launch

    /// Spoken by VoiceOver while the launch splash is on screen (the icon and
    /// radar animation are decorative and hidden from accessibility).
    static var launchAccessibilityLabel: String {
        String(
            localized: "launch.accessibilityLabel",
            defaultValue: "Loading",
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

    static var settingsYearLabel: String {
        String(localized: "settings.year.label", defaultValue: "Year", bundle: .module)
    }

    static var settingsYearHeader: String {
        String(localized: "settings.year.header", defaultValue: "Report year", bundle: .module)
    }

    static var settingsYearFooter: String {
        String(
            localized: "settings.year.footer",
            defaultValue: "Choose which year your reports, calendar, and logged days cover.",
            bundle: .module,
        )
    }

    // MARK: Settings app icon

    static var settingsAppIconHeader: String {
        String(localized: "settings.appIcon.header", defaultValue: "Appearance", bundle: .module)
    }

    static var settingsAppIconLink: String {
        String(localized: "settings.appIcon.link", defaultValue: "App icon", bundle: .module)
    }

    static var settingsAppIconFooter: String {
        String(
            localized: "settings.appIcon.footer",
            defaultValue: "Pick the icon Where shows on your Home Screen.",
            bundle: .module,
        )
    }

    // MARK: Developer tools

    static var developerTitle: String {
        localized("developer.title")
    }

    static var developerLogsLink: String {
        localized("developer.logsLink")
    }

    static var developerFooter: String {
        localized("developer.footer")
    }

    static var developerLogsTitle: String {
        localized("developer.logsTitle")
    }

    static var developerInspectorLink: String {
        localized("developer.inspectorLink")
    }

    static var developerInspectorTitle: String {
        localized("developer.inspectorTitle")
    }

    static var developerRegionMapLink: String {
        localized("developer.regionMapLink")
    }

    /// Accessibility label for the floating, collapsed developer button.
    static var developerButtonLabel: String {
        localized("developer.button.label")
    }

    /// Accessibility label for the developer panel's close control.
    static var developerClose: String {
        localized("developer.close")
    }

    /// Accessibility label for growing the developer panel to full screen.
    static var developerExpand: String {
        localized("developer.expand")
    }

    /// Accessibility label for shrinking the developer panel back to a
    /// floating window.
    static var developerCollapse: String {
        localized("developer.collapse")
    }

    // MARK: Region map (developer)

    static var regionMapTitle: String {
        String(localized: "regionMap.title", defaultValue: "Region Map", bundle: .module)
    }

    /// Accessibility label for the picker that switches the drawn geometry.
    static var regionMapKindPicker: String {
        String(localized: "regionMap.kind.picker", defaultValue: "Geometry", bundle: .module)
    }

    static func regionMapKind(_ kind: RegionGeometryKind) -> String {
        switch kind {
            case .attribution:
                String(
                    localized: "regionMap.kind.attribution",
                    defaultValue: "Attribution",
                    bundle: .module,
                )
            case .source:
                String(localized: "regionMap.kind.source", defaultValue: "Source", bundle: .module)
        }
    }

    static func regionMapKindFooter(_ kind: RegionGeometryKind) -> String {
        switch kind {
            case .attribution:
                String(
                    localized: "regionMap.kind.attribution.footer",
                    defaultValue: "The simplified polygons the app uses to attribute coordinates today.",
                    bundle: .module,
                )
            case .source:
                String(
                    localized: "regionMap.kind.source.footer",
                    defaultValue: "Every feature decoded straight from the bundled GeoJSON, at full authored fidelity.",
                    bundle: .module,
                )
        }
    }

    static var regionMapLegendHeader: String {
        String(localized: "regionMap.legend.header", defaultValue: "Features", bundle: .module)
    }

    static var regionMapShowAll: String {
        String(localized: "regionMap.showAll", defaultValue: "Show all", bundle: .module)
    }

    static var regionMapMapAccessibility: String {
        String(
            localized: "regionMap.map.accessibility",
            defaultValue: "Map of region boundaries",
            bundle: .module,
        )
    }

    static var regionMapLoadErrorTitle: String {
        String(
            localized: "regionMap.loadError.title",
            defaultValue: "Couldn't load regions",
            bundle: .module,
        )
    }

    static var regionMapEmptyTitle: String {
        String(localized: "regionMap.empty.title", defaultValue: "No regions", bundle: .module)
    }

    static var regionMapEmptyDescription: String {
        String(
            localized: "regionMap.empty.description",
            defaultValue: "No region geometry was found in the bundle.",
            bundle: .module,
        )
    }

    // MARK: App icon picker

    static var appIconTitle: String {
        String(localized: "appIcon.title", defaultValue: "App Icon", bundle: .module)
    }

    static var appIconCurrent: String {
        String(localized: "appIcon.current", defaultValue: "Current", bundle: .module)
    }

    static var appIconSet: String {
        String(localized: "appIcon.set", defaultValue: "Set as App Icon", bundle: .module)
    }

    static var appIconAppearanceLight: String {
        String(localized: "appIcon.appearance.light", defaultValue: "Light", bundle: .module)
    }

    static var appIconAppearanceDark: String {
        String(localized: "appIcon.appearance.dark", defaultValue: "Dark", bundle: .module)
    }

    static var appIconAppearanceHint: String {
        String(
            localized: "appIcon.appearance.hint",
            defaultValue: "Tap the icon to preview light and dark.",
            bundle: .module,
        )
    }

    static var appIconErrorTitle: String {
        String(
            localized: "appIcon.error.title",
            defaultValue: "Couldn't Change Icon",
            bundle: .module,
        )
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

    static var settingsSummaryHeader: String {
        String(localized: "settings.summary.header", defaultValue: "Daily summary", bundle: .module)
    }

    static var settingsSummaryToggle: String {
        String(localized: "settings.summary.toggle", defaultValue: "Daily summary", bundle: .module)
    }

    static var settingsSummaryTime: String {
        String(localized: "settings.summary.time", defaultValue: "Send at", bundle: .module)
    }

    static var settingsSummaryFooter: String {
        String(
            localized: "settings.summary.footer",
            defaultValue: "Get a morning recap of how many days you've logged in each region so far this year.",
            bundle: .module,
        )
    }

    static var settingsSummaryDeniedFooter: String {
        String(
            localized: "settings.summary.deniedFooter",
            defaultValue: "Notifications are turned off for Where, so the daily summary can't appear. Turn them on in Settings.",
            bundle: .module,
        )
    }

    static var settingsIssueAlertsHeader: String {
        String(
            localized: "settings.issueAlerts.header",
            defaultValue: "Issue alerts",
            bundle: .module,
        )
    }

    static var settingsIssueAlertsToggle: String {
        String(
            localized: "settings.issueAlerts.toggle",
            defaultValue: "Issue alerts",
            bundle: .module,
        )
    }

    static var settingsIssueAlertsFooter: String {
        String(
            localized: "settings.issueAlerts.footer",
            defaultValue: "Badge the app icon and send a reminder when there are data issues waiting in the Resolve tab.",
            bundle: .module,
        )
    }

    static var settingsIssueAlertsDeniedFooter: String {
        String(
            localized: "settings.issueAlerts.deniedFooter",
            defaultValue: "Notifications are turned off for Where, so issue alerts can't appear. Turn them on in Settings.",
            bundle: .module,
        )
    }

    static var settingsTabsHeader: String {
        String(
            localized: "settings.tabs.header",
            defaultValue: "Tabs",
            bundle: .module,
        )
    }

    static var settingsTabsToggle: String {
        String(
            localized: "settings.tabs.toggle",
            defaultValue: "Hide empty tabs",
            bundle: .module,
        )
    }

    static var settingsTabsFooter: String {
        String(
            localized: "settings.tabs.footer",
            defaultValue: "Hide the Elsewhere and Resolve tabs while they have nothing to show. Turn this off to always keep them in the tab bar.",
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

    static var settingsResetErase: String {
        String(
            localized: "settings.reset.erase",
            defaultValue: "Erase all data & reset",
            bundle: .module,
        )
    }

    static var settingsResetConfirm: String {
        String(
            localized: "settings.reset.confirm",
            defaultValue: "Erase Everything & Reset",
            bundle: .module,
        )
    }

    static var settingsResetMessage: String {
        String(
            localized: "settings.reset.message",
            defaultValue: "This erases every sample, manual day, and piece of evidence on this device and returns you to first-run setup. It can't be undone.",
            bundle: .module,
        )
    }

    static var settingsResetFooter: String {
        String(
            localized: "settings.reset.footer",
            defaultValue: "Starts over from scratch, as if you'd just installed Where.",
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

    static var settingsBackupExporting: String {
        localized("settings.backup.exporting")
    }

    /// Label for the share row revealed once a background export has produced a
    /// ready archive file.
    static var settingsBackupShare: String {
        localized("settings.backup.share")
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
        dismissedIssues: Int,
        trackedRegions: Int,
    ) -> String {
        String(
            localized: "settings.backup.imported.message",
            defaultValue: "Imported \(samples) location samples, \(evidence) pieces of evidence, \(manualDays) manual days, \(dismissedIssues) dismissed issues, and \(trackedRegions) tracked regions.",
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

    static var manualNoteHeader: String {
        String(localized: "manual.note.header", defaultValue: "Reason", bundle: .module)
    }

    static var manualNotePlaceholder: String {
        String(
            localized: "manual.note.placeholder",
            defaultValue: "Add a note (optional)",
            bundle: .module,
        )
    }

    static var manualNoteFooter: String {
        String(
            localized: "manual.note.footer",
            defaultValue: "Saved with this entry for auditing — explain why you made this change.",
            bundle: .module,
        )
    }

    static var manualSavingStatus: String {
        String(
            localized: "manual.saving.status",
            defaultValue: "Capturing location…",
            bundle: .module,
        )
    }

    static func manualRangeFooter(count: Int) -> String {
        String(
            localized: "manual.range.footer",
            defaultValue: "Backfilling \(count) days.",
            bundle: .module,
        )
    }

    // MARK: Calendar

    static var primaryCalendar: String {
        String(localized: "primary.calendar", defaultValue: "Calendar", bundle: .module)
    }

    static func calendarTitle(year: Int) -> String {
        String(
            localized: "calendar.title",
            defaultValue: "Calendar · \(yearText(year))",
            bundle: .module,
        )
    }

    /// Title for the calendar when it's focused on a single region, e.g.
    /// "California · 2026".
    static func calendarRegionTitle(region: Region, year: Int) -> String {
        String(
            localized: "calendar.region.title",
            defaultValue: "\(region.localizedName) · \(yearText(year))",
            bundle: .module,
        )
    }

    static var calendarUnavailableDescription: String {
        String(
            localized: "calendar.unavailable.description",
            defaultValue: "Your year data isn't available right now.",
            bundle: .module,
        )
    }

    static func calendarDayAccessibility(
        date: Date,
        regions: [Region],
        needsAttention: Bool,
        hasEvidence: Bool,
    ) -> String {
        let base = calendarDayBase(date: date, regions: regions, needsAttention: needsAttention)
        guard hasEvidence else { return base }
        // Append the attachment cue so VoiceOver announces it after the day's
        // regions/status, e.g. "Monday, March 4, California, has evidence".
        return String(
            localized: "calendar.day.hasEvidence.accessibility",
            defaultValue: "\(base), has evidence",
            bundle: .module,
        )
    }

    private static func calendarDayBase(
        date: Date,
        regions: [Region],
        needsAttention: Bool,
    ) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if needsAttention {
            return String(
                localized: "calendar.day.needsAttention.accessibility",
                defaultValue: "\(day), needs a location",
                bundle: .module,
            )
        }
        if regions.isEmpty {
            return String(
                localized: "calendar.day.empty.accessibility",
                defaultValue: "\(day), nothing logged",
                bundle: .module,
            )
        }
        let names = regions.map(\.localizedName).joined(separator: ", ")
        return String(
            localized: "calendar.day.accessibility",
            defaultValue: "\(day), \(names)",
            bundle: .module,
        )
    }

    // MARK: Logged days

    /// Toolbar label + accessibility for the Primary tab's "logged days" button
    /// that opens the manual-entry management sheet.
    static var primaryLoggedDays: String {
        String(localized: "primary.loggedDays", defaultValue: "Logged days", bundle: .module)
    }

    static func loggedDaysTitle(year: Int) -> String {
        String(
            localized: "loggedDays.title",
            defaultValue: "Logged Days · \(yearText(year))",
            bundle: .module,
        )
    }

    /// Toolbar "+" label for logging a new day by hand.
    static var loggedDaysAdd: String {
        String(localized: "loggedDays.add", defaultValue: "Log a day", bundle: .module)
    }

    /// Navigation title of the logged-day editor sheet.
    static var loggedDaysEditTitle: String {
        String(localized: "loggedDays.edit.title", defaultValue: "Edit day", bundle: .module)
    }

    /// Leading label for the (fixed) date row in the logged-day editor.
    static var loggedDaysEditDate: String {
        String(localized: "loggedDays.edit.date", defaultValue: "Day", bundle: .module)
    }

    /// Destructive button + confirmation title for deleting a logged day.
    static var loggedDaysDelete: String {
        String(localized: "loggedDays.delete", defaultValue: "Delete entry", bundle: .module)
    }

    /// Explains what deleting a logged day does — used as the editor section
    /// footer and the delete confirmation message.
    static var loggedDaysDeleteFooter: String {
        String(
            localized: "loggedDays.delete.footer",
            defaultValue: "Removes this manual entry and restores the day's GPS-detected location.",
            bundle: .module,
        )
    }

    static var loggedDaysEmptyTitle: String {
        String(localized: "loggedDays.empty.title", defaultValue: "No logged days", bundle: .module)
    }

    static var loggedDaysEmptyDescription: String {
        String(
            localized: "loggedDays.empty.description",
            defaultValue: "Backfill a trip the GPS missed, or correct a day by hand — your manual entries for this year show up here.",
            bundle: .module,
        )
    }

    static var loggedDaysFailedTitle: String {
        String(
            localized: "loggedDays.failed.title",
            defaultValue: "Couldn't load logged days",
            bundle: .module,
        )
    }

    /// Row tag for an additive backfill (unions with GPS).
    static var loggedDaysKindLogged: String {
        String(localized: "loggedDays.kind.logged", defaultValue: "Logged", bundle: .module)
    }

    /// Row tag for an authoritative override (replaces GPS).
    static var loggedDaysKindOverridden: String {
        String(
            localized: "loggedDays.kind.overridden",
            defaultValue: "Overridden",
            bundle: .module,
        )
    }

    static var loggedDaysDeleteErrorTitle: String {
        String(
            localized: "loggedDays.deleteError.title",
            defaultValue: "Couldn't delete entry",
            bundle: .module,
        )
    }

    /// Accessibility label for the Logged/Overridden/All segmented filter (hidden
    /// visually by the segmented style, read by VoiceOver).
    static var loggedDaysFilterLabel: String {
        String(localized: "loggedDays.filter.label", defaultValue: "Filter", bundle: .module)
    }

    /// Filter segment showing both logged and overridden entries.
    static var loggedDaysFilterAll: String {
        String(localized: "loggedDays.filter.all", defaultValue: "All", bundle: .module)
    }

    static var loggedDaysNoMatchesTitle: String {
        String(
            localized: "loggedDays.noMatches.title",
            defaultValue: "No matching days",
            bundle: .module,
        )
    }

    static var loggedDaysNoMatchesDescription: String {
        String(
            localized: "loggedDays.noMatches.description",
            defaultValue: "No days match this filter.",
            bundle: .module,
        )
    }

    // MARK: Evidence

    /// Toolbar label + accessibility for the Primary tab's "view all evidence"
    /// button.
    static var primaryEvidence: String {
        String(localized: "primary.evidence", defaultValue: "Evidence", bundle: .module)
    }

    static func evidenceListTitle(year: Int) -> String {
        String(
            localized: "evidence.list.title",
            defaultValue: "Evidence · \(yearText(year))",
            bundle: .module,
        )
    }

    static var evidenceEmptyTitle: String {
        String(localized: "evidence.empty.title", defaultValue: "No evidence yet", bundle: .module)
    }

    static var evidenceEmptyDescription: String {
        String(
            localized: "evidence.empty.description",
            defaultValue: "Attach a boarding pass, receipt, or screenshot to back up where you were. Add one here, or share it into Where from another app.",
            bundle: .module,
        )
    }

    static var evidenceFailedTitle: String {
        String(
            localized: "evidence.failed.title",
            defaultValue: "Couldn't load evidence",
            bundle: .module,
        )
    }

    /// Toolbar "+" label for adding a new piece of evidence in-app.
    static var evidenceAdd: String {
        String(localized: "evidence.add", defaultValue: "Add evidence", bundle: .module)
    }

    /// Human-readable name for an evidence kind, used in the list rows, the
    /// detail header, and the compose form's picker. `.other` shows its
    /// user-supplied label when present, else a generic "Other".
    static func evidenceKind(_ kind: EvidenceKind) -> String {
        switch kind {
            case .planeTicket:
                return String(
                    localized: "evidence.kind.planeTicket",
                    defaultValue: "Plane ticket",
                    bundle: .module,
                )
            case .boardingPass:
                return String(
                    localized: "evidence.kind.boardingPass",
                    defaultValue: "Boarding pass",
                    bundle: .module,
                )
            case .hotelReceipt:
                return String(
                    localized: "evidence.kind.hotelReceipt",
                    defaultValue: "Hotel receipt",
                    bundle: .module,
                )
            case .carRental:
                return String(
                    localized: "evidence.kind.carRental",
                    defaultValue: "Car rental",
                    bundle: .module,
                )
            case .rideshare:
                return String(
                    localized: "evidence.kind.rideshare",
                    defaultValue: "Rideshare",
                    bundle: .module,
                )
            case .photo:
                return String(
                    localized: "evidence.kind.photo",
                    defaultValue: "Photo",
                    bundle: .module,
                )
            case .document:
                return String(
                    localized: "evidence.kind.document",
                    defaultValue: "Document",
                    bundle: .module,
                )
            case .email:
                return String(
                    localized: "evidence.kind.email",
                    defaultValue: "Email",
                    bundle: .module,
                )
            case let .other(label):
                if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return label
                }
                return String(
                    localized: "evidence.kind.other",
                    defaultValue: "Other",
                    bundle: .module,
                )
        }
    }

    static var evidenceKindPickerLabel: String {
        String(localized: "evidence.form.kind", defaultValue: "Kind", bundle: .module)
    }

    static var evidenceOtherLabelPlaceholder: String {
        String(localized: "evidence.form.otherLabel", defaultValue: "Label", bundle: .module)
    }

    static var evidenceDateLabel: String {
        String(localized: "evidence.form.date", defaultValue: "Date", bundle: .module)
    }

    static var evidenceNoteLabel: String {
        String(localized: "evidence.form.note", defaultValue: "Note", bundle: .module)
    }

    static var evidenceNotePlaceholder: String {
        String(
            localized: "evidence.form.notePlaceholder",
            defaultValue: "Add a note (optional)",
            bundle: .module,
        )
    }

    static var evidenceAttachmentHeader: String {
        String(
            localized: "evidence.form.attachmentHeader",
            defaultValue: "Attachment",
            bundle: .module,
        )
    }

    static var evidenceChooseFile: String {
        String(localized: "evidence.form.chooseFile", defaultValue: "Choose file", bundle: .module)
    }

    static var evidenceChoosePhoto: String {
        String(
            localized: "evidence.form.choosePhoto",
            defaultValue: "Choose photo",
            bundle: .module,
        )
    }

    static var evidenceRemoveAttachment: String {
        String(
            localized: "evidence.form.remove",
            defaultValue: "Remove attachment",
            bundle: .module,
        )
    }

    static var evidenceSave: String {
        String(localized: "evidence.form.save", defaultValue: "Save", bundle: .module)
    }

    static var evidenceSaveErrorTitle: String {
        String(
            localized: "evidence.form.saveError.title",
            defaultValue: "Couldn't save evidence",
            bundle: .module,
        )
    }

    static var evidenceDetailNoteHeader: String {
        String(localized: "evidence.detail.noteHeader", defaultValue: "Note", bundle: .module)
    }

    static var evidenceNoPreviewTitle: String {
        String(
            localized: "evidence.detail.noPreview.title",
            defaultValue: "No preview",
            bundle: .module,
        )
    }

    static var evidenceNoPreviewDescription: String {
        String(
            localized: "evidence.detail.noPreview.description",
            defaultValue: "This attachment can't be previewed here.",
            bundle: .module,
        )
    }

    static var evidenceNoAttachment: String {
        String(
            localized: "evidence.detail.noAttachment",
            defaultValue: "No attachment",
            bundle: .module,
        )
    }

    static var evidencePreviewFailed: String {
        String(
            localized: "evidence.detail.previewFailed",
            defaultValue: "Couldn't load this attachment.",
            bundle: .module,
        )
    }

    /// Accessibility summary for a single evidence row: its kind and captured
    /// date, e.g. "Plane ticket, March 4, 2026".
    static func evidenceRowAccessibility(kind: EvidenceKind, date: Date) -> String {
        let day = date.formatted(.dateTime.month(.wide).day().year())
        return String(
            localized: "evidence.row.accessibility",
            defaultValue: "\(evidenceKind(kind)), \(day)",
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

    // MARK: Resolution

    static var resolutionTitle: String {
        String(localized: "resolution.title", defaultValue: "Resolve", bundle: .module)
    }

    static var resolutionEmptyTitle: String {
        String(localized: "resolution.empty.title", defaultValue: "All clear", bundle: .module)
    }

    static var resolutionEmptyDescription: String {
        String(
            localized: "resolution.empty.description",
            defaultValue: "No data issues need your attention right now.",
            bundle: .module,
        )
    }

    static var resolutionDismiss: String {
        String(localized: "resolution.dismiss", defaultValue: "Dismiss", bundle: .module)
    }

    static func resolutionSectionHeader(_ category: DataIssueCategory) -> String {
        switch category {
            case .missingDays:
                String(
                    localized: "resolution.section.missingDays",
                    defaultValue: "Missing days",
                    bundle: .module,
                )
            case .borderDrift:
                String(
                    localized: "resolution.section.borderDrift",
                    defaultValue: "Near the border",
                    bundle: .module,
                )
            case .abruptChange:
                String(
                    localized: "resolution.section.abruptChange",
                    defaultValue: "Sudden moves",
                    bundle: .module,
                )
        }
    }

    static func driftRowSubtitle(region: String, distance: String) -> String {
        String(
            localized: "resolution.drift.subtitle",
            defaultValue: "Looks like \(region), ~\(distance) over the border",
            bundle: .module,
        )
    }

    static func resolutionAbruptRowTitle(earlier: Set<Region>, later: Set<Region>) -> String {
        let earlierNames = earlier.map(\.localizedName).sorted().joined(separator: ", ")
        let laterNames = later.map(\.localizedName).sorted().joined(separator: ", ")
        return String(
            localized: "resolution.abrupt.rowTitle",
            defaultValue: "\(earlierNames) → \(laterNames)",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailTitle: String {
        String(
            localized: "resolution.abrupt.detail.title",
            defaultValue: "Sudden location change",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailExplanation: String {
        String(
            localized: "resolution.abrupt.detail.explanation",
            defaultValue:
            "These back-to-back days don't overlap at all — you were probably traveling and one day wasn't logged in both places.",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailEarlierHeader: String {
        String(
            localized: "resolution.abrupt.detail.earlier",
            defaultValue: "Earlier day",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailLaterHeader: String {
        String(
            localized: "resolution.abrupt.detail.later",
            defaultValue: "Later day",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailRelabelEarlier: String {
        String(
            localized: "resolution.abrupt.detail.relabelEarlier",
            defaultValue: "Mark as a travel day",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailRelabelLater: String {
        String(
            localized: "resolution.abrupt.detail.relabelLater",
            defaultValue: "Mark as a travel day",
            bundle: .module,
        )
    }

    static var resolutionAbruptDetailBothRight: String {
        String(
            localized: "resolution.abrupt.detail.bothRight",
            defaultValue: "These are both right",
            bundle: .module,
        )
    }

    static var settingsResolutionHeader: String {
        String(
            localized: "settings.resolution.header",
            defaultValue: "Data resolution",
            bundle: .module,
        )
    }

    static var settingsResolutionFooter: String {
        String(
            localized: "settings.resolution.footer",
            defaultValue:
            "Days logged just outside a primary region within this distance are flagged as possible GPS drift.",
            bundle: .module,
        )
    }

    /// A localized "10 km"-style label for a drift-threshold preset. Formatted
    /// through `Measurement` so the number and unit symbol localize, while
    /// staying in kilometers (`.asProvided`, no conversion to miles) — the
    /// presets are defined in km. No catalog entry is needed; the formatter is
    /// locale-driven, like the date/number styles elsewhere in this file.
    static func driftThresholdLabel(kilometers: Int) -> String {
        Measurement(value: Double(kilometers), unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    // MARK: Recent activity (24h on-device summary)

    /// The sheet title for the covered window (e.g. "Last 24 hours").
    static func recentActivityTitle(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day:
                String(
                    localized: "recentActivity.title.day",
                    defaultValue: "Last 24 hours",
                    bundle: .module,
                )
            case .week:
                String(
                    localized: "recentActivity.title.week",
                    defaultValue: "Past week",
                    bundle: .module,
                )
            case .month:
                String(
                    localized: "recentActivity.title.month",
                    defaultValue: "Past month",
                    bundle: .module,
                )
            case .yearToDate:
                String(
                    localized: "recentActivity.title.yearToDate",
                    defaultValue: "Year so far",
                    bundle: .module,
                )
        }
    }

    /// Accessibility label for the window segmented control (the visible
    /// segments carry the individual window names).
    static var recentActivityWindowPickerLabel: String {
        String(
            localized: "recentActivity.window.pickerLabel",
            defaultValue: "Summary range",
            bundle: .module,
        )
    }

    /// Short segmented-control label for a window (e.g. "24 Hours", "Week").
    static func recentActivityWindowLabel(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day:
                String(
                    localized: "recentActivity.window.day",
                    defaultValue: "24 Hours",
                    bundle: .module,
                )
            case .week:
                String(
                    localized: "recentActivity.window.week",
                    defaultValue: "Week",
                    bundle: .module,
                )
            case .month:
                String(
                    localized: "recentActivity.window.month",
                    defaultValue: "Month",
                    bundle: .module,
                )
            case .yearToDate:
                String(
                    localized: "recentActivity.window.yearToDate",
                    defaultValue: "Year",
                    bundle: .module,
                )
        }
    }

    /// Privacy-forward footer describing what the covered window summarizes.
    static func recentActivityFooter(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day:
                String(
                    localized: "recentActivity.footer.day",
                    defaultValue: "An on-device summary of where you've been in the last 24 hours. Your location never leaves your device.",
                    bundle: .module,
                )
            case .week:
                String(
                    localized: "recentActivity.footer.week",
                    defaultValue: "An on-device summary of where you've been over the past week. Your location never leaves your device.",
                    bundle: .module,
                )
            case .month:
                String(
                    localized: "recentActivity.footer.month",
                    defaultValue: "An on-device summary of where you've been over the past month. Your location never leaves your device.",
                    bundle: .module,
                )
            case .yearToDate:
                String(
                    localized: "recentActivity.footer.yearToDate",
                    defaultValue: "An on-device summary of where you've been so far this year. Your location never leaves your device.",
                    bundle: .module,
                )
        }
    }

    static var recentActivityLoading: String {
        String(
            localized: "recentActivity.loading",
            defaultValue: "Summarizing…",
            bundle: .module,
        )
    }

    static var recentActivityRefresh: String {
        String(localized: "recentActivity.refresh", defaultValue: "Refresh", bundle: .module)
    }

    static var recentActivityEmptyTitle: String {
        String(
            localized: "recentActivity.empty.title",
            defaultValue: "Nothing tracked",
            bundle: .module,
        )
    }

    /// Empty-state description naming the window that held no locations.
    static func recentActivityEmptyDescription(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day:
                String(
                    localized: "recentActivity.empty.description.day",
                    defaultValue: "No locations were recorded in the last 24 hours.",
                    bundle: .module,
                )
            case .week:
                String(
                    localized: "recentActivity.empty.description.week",
                    defaultValue: "No locations were recorded in the past week.",
                    bundle: .module,
                )
            case .month:
                String(
                    localized: "recentActivity.empty.description.month",
                    defaultValue: "No locations were recorded in the past month.",
                    bundle: .module,
                )
            case .yearToDate:
                String(
                    localized: "recentActivity.empty.description.yearToDate",
                    defaultValue: "No locations were recorded so far this year.",
                    bundle: .module,
                )
        }
    }

    static var recentActivityFailedTitle: String {
        String(
            localized: "recentActivity.failed.title",
            defaultValue: "Couldn't summarize",
            bundle: .module,
        )
    }

    static var recentActivityUnavailableTitle: String {
        String(
            localized: "recentActivity.unavailable.title",
            defaultValue: "Summaries unavailable",
            bundle: .module,
        )
    }

    /// User-facing explanation for why the on-device model can't produce a
    /// summary, keyed off the typed reason so the copy can guide the user.
    static func recentActivityUnavailableMessage(
        _ reason: ActivitySummaryUnavailableReason,
    ) -> String {
        switch reason {
            case .deviceNotEligible:
                String(
                    localized: "recentActivity.unavailable.deviceNotEligible",
                    defaultValue: "This device doesn't support on-device summaries.",
                    bundle: .module,
                )
            case .appleIntelligenceNotEnabled:
                String(
                    localized: "recentActivity.unavailable.appleIntelligenceNotEnabled",
                    defaultValue: "Turn on Apple Intelligence in Settings to generate summaries.",
                    bundle: .module,
                )
            case .modelNotReady:
                String(
                    localized: "recentActivity.unavailable.modelNotReady",
                    defaultValue: "The on-device model is still getting ready. Try again shortly.",
                    bundle: .module,
                )
            case .unknown:
                String(
                    localized: "recentActivity.unavailable.unknown",
                    defaultValue: "On-device summaries aren't available right now.",
                    bundle: .module,
                )
        }
    }

    // MARK: Widgets

    static var widgetTodayTitle: String {
        String(localized: "widget.today.title", defaultValue: "Today", bundle: .module)
    }

    static var widgetTodayEmpty: String {
        String(
            localized: "widget.today.empty",
            defaultValue: "Nothing logged yet",
            bundle: .module,
        )
    }

    static func widgetYearTitle(year: Int) -> String {
        String(
            localized: "widget.year.title",
            defaultValue: "Days in \(yearText(year))",
            bundle: .module,
        )
    }

    static var widgetYearEmpty: String {
        String(
            localized: "widget.year.empty",
            defaultValue: "No days logged",
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
