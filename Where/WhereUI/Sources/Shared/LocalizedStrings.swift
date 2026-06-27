import Foundation
import StuffCore

/// Catalog-backed, deferred strings for WhereUI.
///
/// Every user-facing string in the module is funneled through here so views
/// stay free of literals. Members return a ``LocalizedString`` (a deferred
/// builder) rather than a resolved `String`, so the catalog lookup happens at
/// the point of display — call `.localized` (or `Text.localized(_:)`) there.
///
/// Simple members use the ``LocalizedString/module(_:_:)`` factory, which is a
/// `key` plus its English default (`.module` and the locale are baked in). The
/// key is a `StaticString` literal so both Xcode's catalog extraction and the
/// repo's `./localize` script can read it statically. Members that compose other
/// strings or branch on a count drop to the `LocalizedString { … }` closure.
/// Counts use the catalog's plural variations; years format without a grouping
/// separator so they read "2026", never "2,026".
enum LocalizedStrings {
    // MARK: Tabs

    enum Tabs {
        static var primary: LocalizedString {
            .module("tab.primary", "Primary")
        }

        static var elsewhere: LocalizedString {
            .module("tab.elsewhere", "Elsewhere")
        }

        static var settings: LocalizedString {
            .module("tab.settings", "Settings")
        }
    }

    // MARK: Common

    enum Common {
        static var loadErrorTitle: LocalizedString {
            .module("common.loadError.title", "Couldn't load your year")
        }

        static var ok: LocalizedString {
            .module("common.ok", "OK")
        }

        static var done: LocalizedString {
            .module("common.done", "Done")
        }

        /// "1 day" / "5 days" — with the count rendered.
        static func dayCount(_ count: Int) -> LocalizedString {
            .module("common.dayCount", "\(count) days")
        }

        /// "day" / "days" — the bare unit, when the count is shown separately.
        static func dayUnit(_ count: Int) -> LocalizedString {
            count == 1 ? .module("common.day", "day") : .module("common.days", "days")
        }

        static func regionDaysAccessibility(region: String, days: Int) -> LocalizedString {
            .module("common.regionDays.accessibility") {
                "\(region): \(dayCount(days).localized($0))"
            }
        }
    }

    // MARK: Primary

    enum Primary {
        /// The Primary tab's masthead wordmark.
        static var title: LocalizedString {
            .module("primary.title", "Where")
        }

        static var timeline: LocalizedString {
            .module("primary.timeline", "Timeline")
        }

        static var loading: LocalizedString {
            .module("primary.loading", "Charting your year…")
        }

        static var emptyDescription: LocalizedString {
            .module(
                "primary.empty.description",
                "Turn on tracking or add a day in Settings and your top spots will land here.",
            )
        }

        static var elsewhereOnlyTitle: LocalizedString {
            .module("primary.elsewhereOnly.title", "Nothing in your headline spots")
        }

        /// Shown when there's tracked data, but none of it lands in a primary
        /// region — points the user at the Elsewhere tab.
        static func elsewhereOnlyDescription(count: Int) -> LocalizedString {
            .module(
                "primary.elsewhereOnly.description",
                "\(count) days logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
            )
        }

        static func emptyTitle(year: Int) -> LocalizedString {
            .module("primary.empty.title", "No travels logged for \(yearText(year))")
        }
    }

    // MARK: Elsewhere

    enum Secondary {
        static var title: LocalizedString {
            .module("secondary.title", "Elsewhere")
        }

        static var loading: LocalizedString {
            .module("secondary.loading", "Retracing your steps…")
        }

        static var emptyTitle: LocalizedString {
            .module(
                "secondary.empty.title",
                "Nowhere else logged",
            )
        }

        static var emptyDescription: LocalizedString {
            .module(
                "secondary.empty.description",
                "Spend a day outside your top spots — or log a trip in Settings — and it'll appear here.",
            )
        }

        static var captionPassingThrough: LocalizedString {
            .module("secondary.caption.passingThrough", "Just passing through")
        }

        static func header(year: Int) -> LocalizedString {
            .module("secondary.header", "Everywhere else you turned up in \(yearText(year)).")
        }

        // MARK: Elsewhere region detail

        enum Region {
            static var footer: LocalizedString {
                .module(
                    "secondary.region.footer",
                    "Tap a day to fix where it counted. Your GPS data stays untouched.",
                )
            }

            static var emptyTitle: LocalizedString {
                .module("secondary.region.empty.title", "Nothing to fix")
            }

            static var emptyDescription: LocalizedString {
                .module("secondary.region.empty.description", "No days counted for this region.")
            }

            /// Caption on a day row showing the regions it currently counts for,
            /// e.g. "Counts as California, New York".
            static func current(regions: String) -> LocalizedString {
                .module("secondary.region.current", "Counts as \(regions)")
            }

            /// Accessibility label for the map of recorded points on the region
            /// drill-in.
            static var mapAccessibility: LocalizedString {
                .module("secondary.region.map.accessibility", "Map of where you were")
            }
        }
    }

    // MARK: Relabel

    enum Relabel {
        static var title: LocalizedString {
            .module("relabel.title", "Fix this day")
        }

        static var regionsHeader: LocalizedString {
            .module(
                "relabel.regions.header",
                "Where were you?",
            )
        }

        static var regionsFooter: LocalizedString {
            .module(
                "relabel.regions.footer",
                "This replaces what was recorded for this day, overriding GPS. Your raw location data is kept, so you can change it back.",
            )
        }

        static var reset: LocalizedString {
            .module("relabel.reset", "Reset to GPS-detected location")
        }

        static var resetFooter: LocalizedString {
            .module(
                "relabel.reset.footer",
                "Removes any manual correction for this day and restores the regions detected from GPS. Your raw location data is untouched.",
            )
        }
    }

    // MARK: Onboarding

    enum Onboarding {
        static var welcomeTitle: LocalizedString {
            .module("onboarding.welcome.title", "Where have you been?")
        }

        static var welcomeDescription: LocalizedString {
            .module(
                "onboarding.welcome.description",
                "Where keeps a private passport of which regions you spend your days in — built for residency and day-count questions.",
            )
        }

        static var automaticTitle: LocalizedString {
            .module("onboarding.automatic.title", "It logs itself")
        }

        static var automaticDescription: LocalizedString {
            .module(
                "onboarding.automatic.description",
                "With background location, Where quietly notes the regions you pass through. You can always add or correct days by hand.",
            )
        }

        static var privacyTitle: LocalizedString {
            .module("onboarding.privacy.title", "Private by design")
        }

        static var privacyDescription: LocalizedString {
            .module(
                "onboarding.privacy.description",
                "Your location stays on your device and in your own iCloud. Turn on background location to start your passport.",
            )
        }

        static var continueButton: LocalizedString {
            .module("onboarding.continue", "Continue")
        }

        static var enableLocation: LocalizedString {
            .module(
                "onboarding.enableLocation",
                "Enable Location",
            )
        }

        static var notNow: LocalizedString {
            .module("onboarding.notNow", "Not Now")
        }
    }

    // MARK: Migration

    enum Migration {
        static var title: LocalizedString {
            .module("migration.title", "Updating your data…")
        }

        static var subtitle: LocalizedString {
            .module(
                "migration.subtitle",
                "This only takes a moment.",
            )
        }
    }

    // MARK: Launch

    enum Launch {
        /// Spoken by VoiceOver while the launch splash is on screen (the icon and
        /// radar animation are decorative and hidden from accessibility).
        static var accessibilityLabel: LocalizedString {
            .module("launch.accessibilityLabel", "Loading")
        }
    }

    // MARK: Settings

    enum Settings {
        static var title: LocalizedString {
            .module("settings.title", "Settings")
        }

        enum PermissionAlert {
            static var title: LocalizedString {
                .module("settings.permissionAlert.title", "Location access needed")
            }

            static var message: LocalizedString {
                .module(
                    "settings.permissionAlert.message",
                    "Where needs Always location access to log which region you're in. You can grant it in the Settings app.",
                )
            }

            static var openSettings: LocalizedString {
                .module("settings.permissionAlert.openSettings", "Open Settings")
            }

            static var notNow: LocalizedString {
                .module("settings.permissionAlert.notNow", "Not now")
            }
        }

        enum Location {
            static var header: LocalizedString {
                .module("settings.location.header", "Location")
            }

            static var toggle: LocalizedString {
                .module("settings.location.toggle", "Track in the background")
            }

            static var grant: LocalizedString {
                .module("settings.location.grant", "Grant location access")
            }

            static var footer: LocalizedString {
                .module(
                    "settings.location.footer",
                    "Where watches for visits and big moves to figure out which region you're in. It needs Always access and a little patience.",
                )
            }
        }

        enum Status {
            static var tracking: LocalizedString {
                .module("settings.status.tracking", "Tracking in the background")
            }

            static var alwaysPaused: LocalizedString {
                .module("settings.status.alwaysPaused", "Always allowed (paused)")
            }

            static var whenInUse: LocalizedString {
                .module("settings.status.whenInUse", "While Using only — needs Always")
            }

            static var notDetermined: LocalizedString {
                .module("settings.status.notDetermined", "Location access not set up")
            }

            static var denied: LocalizedString {
                .module("settings.status.denied", "Location access denied")
            }

            static var restricted: LocalizedString {
                .module("settings.status.restricted", "Location access restricted")
            }
        }

        enum Manual {
            static var header: LocalizedString {
                .module("settings.manual.header", "Manual entry")
            }

            static var link: LocalizedString {
                .module(
                    "settings.manual.link",
                    "Log or override a day",
                )
            }

            static var footer: LocalizedString {
                .module(
                    "settings.manual.footer",
                    "Backfill a trip the GPS missed, or correct a day by hand.",
                )
            }
        }

        enum AppIcon {
            static var header: LocalizedString {
                .module("settings.appIcon.header", "Appearance")
            }

            static var link: LocalizedString {
                .module("settings.appIcon.link", "App icon")
            }

            static var footer: LocalizedString {
                .module("settings.appIcon.footer", "Pick the icon Where shows on your Home Screen.")
            }
        }

        enum Debug {
            static var header: LocalizedString {
                .module("settings.debug.header", "Developer")
            }

            static var logsLink: LocalizedString {
                .module("settings.debug.logsLink", "Logs")
            }

            static var footer: LocalizedString {
                .module(
                    "settings.debug.footer",
                    "On-device logs and data tools. Debug builds only.",
                )
            }

            static var logsTitle: LocalizedString {
                .module("settings.debug.logsTitle", "Logs")
            }

            static var inspectorLink: LocalizedString {
                .module("settings.debug.inspectorLink", "SwiftData Inspector")
            }

            static var inspectorTitle: LocalizedString {
                .module("settings.debug.inspectorTitle", "SwiftData")
            }
        }

        enum Reminders {
            static var header: LocalizedString {
                .module("settings.reminders.header", "Reminders")
            }

            static var toggle: LocalizedString {
                .module("settings.reminders.toggle", "Daily logging reminder")
            }

            static var time: LocalizedString {
                .module("settings.reminders.time", "Remind me at")
            }

            static var footer: LocalizedString {
                .module(
                    "settings.reminders.footer",
                    "If a day hasn't been logged, we'll nudge you before it ends and badge the app. The reminder clears itself once the day is recorded.",
                )
            }

            static var openSettings: LocalizedString {
                .module("settings.reminders.openSettings", "Allow notifications")
            }

            static var deniedFooter: LocalizedString {
                .module(
                    "settings.reminders.deniedFooter",
                    "Notifications are turned off for Where, so reminders and the badge can't appear. Turn them on in Settings.",
                )
            }
        }

        enum Summary {
            static var header: LocalizedString {
                .module("settings.summary.header", "Daily summary")
            }

            static var toggle: LocalizedString {
                .module("settings.summary.toggle", "Daily summary")
            }

            static var time: LocalizedString {
                .module("settings.summary.time", "Send at")
            }

            static var footer: LocalizedString {
                .module(
                    "settings.summary.footer",
                    "Get a morning recap of how many days you've logged in each region so far this year.",
                )
            }

            static var deniedFooter: LocalizedString {
                .module(
                    "settings.summary.deniedFooter",
                    "Notifications are turned off for Where, so the daily summary can't appear. Turn them on in Settings.",
                )
            }
        }

        enum Data {
            static var header: LocalizedString {
                .module("settings.data.header", "Data")
            }

            static var cancel: LocalizedString {
                .module("settings.data.cancel", "Cancel")
            }

            static func erase(year: Int) -> LocalizedString {
                .module("settings.data.erase", "Erase \(yearText(year)) data")
            }

            static func confirmMessage(year: Int) -> LocalizedString {
                .module(
                    "settings.data.confirmMessage",
                    "This removes every sample, manual day, and piece of evidence in \(yearText(year)). It can't be undone.",
                )
            }

            static func footer(year: Int) -> LocalizedString {
                .module(
                    "settings.data.footer",
                    "Acts on the year selected on the Primary tab (\(yearText(year))).",
                )
            }
        }

        enum Reset {
            static var erase: LocalizedString {
                .module(
                    "settings.reset.erase",
                    "Erase all data & reset",
                )
            }

            static var confirm: LocalizedString {
                .module("settings.reset.confirm", "Erase Everything & Reset")
            }

            static var message: LocalizedString {
                .module(
                    "settings.reset.message",
                    "This erases every sample, manual day, and piece of evidence on this device and returns you to first-run setup. It can't be undone.",
                )
            }

            static var footer: LocalizedString {
                .module(
                    "settings.reset.footer",
                    "Starts over from scratch, as if you'd just installed Where.",
                )
            }
        }

        enum Backup {
            static var header: LocalizedString {
                .module("settings.backup.header", "Backup")
            }

            static var footer: LocalizedString {
                .module(
                    "settings.backup.footer",
                    "Export your whole history as a .zip you can email or save to Files, then import it on another device to restore everything.",
                )
            }

            static var export: LocalizedString {
                .module("settings.backup.export", "Export data")
            }

            /// Title shown in the system share sheet preview for an exported backup.
            static var shareTitle: LocalizedString {
                .module(
                    "settings.backup.shareTitle",
                    "Where Backup",
                )
            }

            static var importData: LocalizedString {
                .module("settings.backup.import", "Import data")
            }

            static var importing: LocalizedString {
                .module(
                    "settings.backup.importing",
                    "Importing…",
                )
            }

            static var errorTitle: LocalizedString {
                .module(
                    "settings.backup.errorTitle",
                    "Backup failed",
                )
            }

            static var importStrategyTitle: LocalizedString {
                .module("settings.backup.importStrategy.title", "Import backup")
            }

            static var importStrategyMessage: LocalizedString {
                .module(
                    "settings.backup.importStrategy.message",
                    "Merge keeps everything already on this device and adds the file's records. Replace erases this device first, then restores only what's in the file.",
                )
            }

            static var merge: LocalizedString {
                .module("settings.backup.merge", "Merge")
            }

            static var replace: LocalizedString {
                .module("settings.backup.replace", "Replace all")
            }

            static var importedTitle: LocalizedString {
                .module("settings.backup.imported.title", "Backup imported")
            }

            static func importedMessage(
                samples: Int,
                evidence: Int,
                manualDays: Int,
            ) -> LocalizedString {
                .module(
                    "settings.backup.imported.message",
                    "Imported \(samples) location samples, \(evidence) pieces of evidence, and \(manualDays) manual days.",
                )
            }
        }
    }

    // MARK: App icon picker

    enum AppIcon {
        static var title: LocalizedString {
            .module("appIcon.title", "App Icon")
        }

        static var current: LocalizedString {
            .module("appIcon.current", "Current")
        }

        static var set: LocalizedString {
            .module("appIcon.set", "Set as App Icon")
        }

        static var appearanceLight: LocalizedString {
            .module("appIcon.appearance.light", "Light")
        }

        static var appearanceDark: LocalizedString {
            .module("appIcon.appearance.dark", "Dark")
        }

        static var appearanceHint: LocalizedString {
            .module("appIcon.appearance.hint", "Tap the icon to preview light and dark.")
        }

        static var errorTitle: LocalizedString {
            .module(
                "appIcon.error.title",
                "Couldn't Change Icon",
            )
        }
    }

    // MARK: Manual entry

    enum ManualEntry {
        static var pickerLabel: LocalizedString {
            .module("manual.entry.pickerLabel", "Entry")
        }

        static var modeSingleDay: LocalizedString {
            .module("manual.mode.singleDay", "Single day")
        }

        static var modeRange: LocalizedString {
            .module("manual.mode.range", "Date range")
        }

        static var day: LocalizedString {
            .module("manual.day", "Day")
        }

        static var from: LocalizedString {
            .module("manual.from", "From")
        }

        static var through: LocalizedString {
            .module("manual.through", "Through")
        }

        static var singleDayFooter: LocalizedString {
            .module("manual.singleDay.footer", "Time travel: tell Where where you really were.")
        }

        static var regionsHeader: LocalizedString {
            .module("manual.regions.header", "Regions")
        }

        static var regionsFooter: LocalizedString {
            .module(
                "manual.regions.footer",
                "Saving replaces any manual regions you previously set for those days.",
            )
        }

        static var title: LocalizedString {
            .module("manual.title", "Log a Day")
        }

        static var save: LocalizedString {
            .module("manual.save", "Save")
        }

        static var saveErrorTitle: LocalizedString {
            .module("manual.saveError.title", "Couldn't save that day")
        }

        static func rangeFooter(count: Int) -> LocalizedString {
            .module("manual.range.footer", "Backfilling \(count) days.")
        }
    }

    // MARK: Timeline

    enum Timeline {
        static var done: LocalizedString {
            .module("timeline.done", "Done")
        }

        static var emptyTitle: LocalizedString {
            .module("timeline.empty.title", "No stays yet")
        }

        static var emptyDescription: LocalizedString {
            .module(
                "timeline.empty.description",
                "Once Where has a run of days in a region, your stays will appear here.",
            )
        }

        static func title(year: Int) -> LocalizedString {
            .module("timeline.title", "Timeline · \(yearText(year))")
        }

        static func rowAccessibility(region: String, range: String, days: Int) -> LocalizedString {
            .module("timeline.row.accessibility") {
                "\(region), \(range), \(LocalizedStrings.Common.dayCount(days).localized($0))"
            }
        }
    }

    // MARK: Missing days

    enum MissingDays {
        static var title: LocalizedString {
            .module("missingDays.title", "Missing days")
        }

        static var done: LocalizedString {
            .module("missingDays.done", "Done")
        }

        static var header: LocalizedString {
            .module("missingDays.header", "Days to backfill")
        }

        static var footer: LocalizedString {
            .module(
                "missingDays.footer",
                "Tap a stretch to record where you were. Today is included until something logs it.",
            )
        }

        static var emptyTitle: LocalizedString {
            .module("missingDays.empty.title", "All caught up")
        }

        static var emptyDescription: LocalizedString {
            .module("missingDays.empty.description", "Every day this year has something logged.")
        }
    }

    // MARK: Missing-day banner

    enum MissingBanner {
        static func compact(count: Int) -> LocalizedString {
            count == 1
                ? .module("missing.banner.compact.one", "1 day needs a location")
                : .module("missing.banner.compact.other", "\(count) days need a location")
        }

        static var accessibilityHint: LocalizedString {
            .module(
                "missing.banner.accessibilityHint",
                "Opens the list of days that still need logging.",
            )
        }
    }

    // MARK: Widgets

    enum Widget {
        static var todayTitle: LocalizedString {
            .module("widget.today.title", "Today")
        }

        static var todayEmpty: LocalizedString {
            .module("widget.today.empty", "Nothing logged yet")
        }

        static func yearTitle(year: Int) -> LocalizedString {
            .module("widget.year.title", "Days in \(yearText(year))")
        }

        static var yearEmpty: LocalizedString {
            .module("widget.year.empty", "No days logged")
        }
    }
}

// MARK: Helpers

/// Year without a grouping separator ("2026", not "2,026").
private func yearText(_ year: Int) -> String {
    year.formatted(.number.grouping(.never))
}
