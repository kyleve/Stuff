import Foundation
import StuffCore

/// Catalog-backed, deferred strings for WhereUI.
///
/// Every user-facing string in the module is funneled through here so views
/// stay free of literals. Members return a ``LocalizedString`` (a deferred
/// builder) rather than a resolved `String`, so the catalog lookup happens at
/// the point of display — call `.localized` (or `Text.localized(_:)`) there.
///
/// Each builder performs a literal `String(localized:defaultValue:bundle:.module)`
/// lookup so both Xcode's catalog extraction and the repo's `./localize` script
/// can statically find every key and its English source value. Counts use the
/// catalog's plural variations; years format without a grouping separator so
/// they read "2026", never "2,026".
enum LocalizedStrings {
    // MARK: Tabs

    enum Tabs {
        static var primary: LocalizedString {
            LocalizedString { String(
                localized: "tab.primary",
                defaultValue: "Primary",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var elsewhere: LocalizedString {
            LocalizedString { String(
                localized: "tab.elsewhere",
                defaultValue: "Elsewhere",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var settings: LocalizedString {
            LocalizedString { String(
                localized: "tab.settings",
                defaultValue: "Settings",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Common

    enum Common {
        static var loadErrorTitle: LocalizedString {
            LocalizedString { String(
                localized: "common.loadError.title",
                defaultValue: "Couldn't load your year",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var ok: LocalizedString {
            LocalizedString { String(
                localized: "common.ok",
                defaultValue: "OK",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var done: LocalizedString {
            LocalizedString { String(
                localized: "common.done",
                defaultValue: "Done",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        /// "1 day" / "5 days" — with the count rendered.
        static func dayCount(_ count: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "common.dayCount",
                defaultValue: "\(count) days",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        /// "day" / "days" — the bare unit, when the count is shown separately.
        static func dayUnit(_ count: Int) -> LocalizedString {
            LocalizedString { config in
                count == 1
                    ? String(
                        localized: "common.day",
                        defaultValue: "day",
                        bundle: .module,
                        locale: config?.locale ?? .current,
                    )
                    : String(
                        localized: "common.days",
                        defaultValue: "days",
                        bundle: .module,
                        locale: config?.locale ?? .current,
                    )
            }
        }

        static func regionDaysAccessibility(region: String, days: Int) -> LocalizedString {
            LocalizedString { config in
                String(
                    localized: "common.regionDays.accessibility",
                    defaultValue: "\(region): \(dayCount(days).localized(config))",
                    bundle: .module,
                    locale: config?.locale ?? .current,
                )
            }
        }
    }

    // MARK: Primary

    enum Primary {
        /// The Primary tab's masthead wordmark.
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "primary.title",
                defaultValue: "Where",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var timeline: LocalizedString {
            LocalizedString { String(
                localized: "primary.timeline",
                defaultValue: "Timeline",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var loading: LocalizedString {
            LocalizedString { String(
                localized: "primary.loading",
                defaultValue: "Charting your year…",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyDescription: LocalizedString {
            LocalizedString { String(
                localized: "primary.empty.description",
                defaultValue: "Turn on tracking or add a day in Settings and your top spots will land here.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var elsewhereOnlyTitle: LocalizedString {
            LocalizedString { String(
                localized: "primary.elsewhereOnly.title",
                defaultValue: "Nothing in your headline spots",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        /// Shown when there's tracked data, but none of it lands in a primary
        /// region — points the user at the Elsewhere tab.
        static func elsewhereOnlyDescription(count: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "primary.elsewhereOnly.description",
                defaultValue: "\(count) days logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static func emptyTitle(year: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "primary.empty.title",
                defaultValue: "No travels logged for \(yearText(year))",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Elsewhere

    enum Secondary {
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "secondary.title",
                defaultValue: "Elsewhere",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var loading: LocalizedString {
            LocalizedString { String(
                localized: "secondary.loading",
                defaultValue: "Retracing your steps…",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyTitle: LocalizedString {
            LocalizedString { String(
                localized: "secondary.empty.title",
                defaultValue: "Nowhere else logged",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyDescription: LocalizedString {
            LocalizedString { String(
                localized: "secondary.empty.description",
                defaultValue: "Spend a day outside your top spots — or log a trip in Settings — and it'll appear here.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var captionPassingThrough: LocalizedString {
            LocalizedString { String(
                localized: "secondary.caption.passingThrough",
                defaultValue: "Just passing through",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static func header(year: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "secondary.header",
                defaultValue: "Everywhere else you turned up in \(yearText(year)).",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        // MARK: Elsewhere region detail

        enum Region {
            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "secondary.region.footer",
                    defaultValue: "Tap a day to fix where it counted. Your GPS data stays untouched.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var emptyTitle: LocalizedString {
                LocalizedString { String(
                    localized: "secondary.region.empty.title",
                    defaultValue: "Nothing to fix",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var emptyDescription: LocalizedString {
                LocalizedString { String(
                    localized: "secondary.region.empty.description",
                    defaultValue: "No days counted for this region.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            /// Caption on a day row showing the regions it currently counts for,
            /// e.g. "Counts as California, New York".
            static func current(regions: String) -> LocalizedString {
                LocalizedString { String(
                    localized: "secondary.region.current",
                    defaultValue: "Counts as \(regions)",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            /// Accessibility label for the map of recorded points on the region
            /// drill-in.
            static var mapAccessibility: LocalizedString {
                LocalizedString { String(
                    localized: "secondary.region.map.accessibility",
                    defaultValue: "Map of where you were",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }
    }

    // MARK: Relabel

    enum Relabel {
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "relabel.title",
                defaultValue: "Fix this day",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var regionsHeader: LocalizedString {
            LocalizedString { String(
                localized: "relabel.regions.header",
                defaultValue: "Where were you?",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var regionsFooter: LocalizedString {
            LocalizedString { String(
                localized: "relabel.regions.footer",
                defaultValue: "This replaces what was recorded for this day, overriding GPS. Your raw location data is kept, so you can change it back.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var reset: LocalizedString {
            LocalizedString { String(
                localized: "relabel.reset",
                defaultValue: "Reset to GPS-detected location",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var resetFooter: LocalizedString {
            LocalizedString { String(
                localized: "relabel.reset.footer",
                defaultValue: "Removes any manual correction for this day and restores the regions detected from GPS. Your raw location data is untouched.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Onboarding

    enum Onboarding {
        static var welcomeTitle: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.welcome.title",
                defaultValue: "Where have you been?",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var welcomeDescription: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.welcome.description",
                defaultValue: "Where keeps a private passport of which regions you spend your days in — built for residency and day-count questions.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var automaticTitle: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.automatic.title",
                defaultValue: "It logs itself",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var automaticDescription: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.automatic.description",
                defaultValue: "With background location, Where quietly notes the regions you pass through. You can always add or correct days by hand.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var privacyTitle: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.privacy.title",
                defaultValue: "Private by design",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var privacyDescription: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.privacy.description",
                defaultValue: "Your location stays on your device and in your own iCloud. Turn on background location to start your passport.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var continueButton: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.continue",
                defaultValue: "Continue",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var enableLocation: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.enableLocation",
                defaultValue: "Enable Location",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var notNow: LocalizedString {
            LocalizedString { String(
                localized: "onboarding.notNow",
                defaultValue: "Not Now",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Migration

    enum Migration {
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "migration.title",
                defaultValue: "Updating your data…",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var subtitle: LocalizedString {
            LocalizedString { String(
                localized: "migration.subtitle",
                defaultValue: "This only takes a moment.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Launch

    enum Launch {
        /// Spoken by VoiceOver while the launch splash is on screen (the icon and
        /// radar animation are decorative and hidden from accessibility).
        static var accessibilityLabel: LocalizedString {
            LocalizedString { String(
                localized: "launch.accessibilityLabel",
                defaultValue: "Loading",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Settings

    enum Settings {
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "settings.title",
                defaultValue: "Settings",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        enum PermissionAlert {
            static var title: LocalizedString {
                LocalizedString { String(
                    localized: "settings.permissionAlert.title",
                    defaultValue: "Location access needed",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var message: LocalizedString {
                LocalizedString { String(
                    localized: "settings.permissionAlert.message",
                    defaultValue: "Where needs Always location access to log which region you're in. You can grant it in the Settings app.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var openSettings: LocalizedString {
                LocalizedString { String(
                    localized: "settings.permissionAlert.openSettings",
                    defaultValue: "Open Settings",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var notNow: LocalizedString {
                LocalizedString { String(
                    localized: "settings.permissionAlert.notNow",
                    defaultValue: "Not now",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Location {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.location.header",
                    defaultValue: "Location",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var toggle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.location.toggle",
                    defaultValue: "Track in the background",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var grant: LocalizedString {
                LocalizedString { String(
                    localized: "settings.location.grant",
                    defaultValue: "Grant location access",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.location.footer",
                    defaultValue: "Where watches for visits and big moves to figure out which region you're in. It needs Always access and a little patience.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Status {
            static var tracking: LocalizedString {
                LocalizedString { String(
                    localized: "settings.status.tracking",
                    defaultValue: "Tracking in the background",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var alwaysPaused: LocalizedString {
                LocalizedString { String(
                    localized: "settings.status.alwaysPaused",
                    defaultValue: "Always allowed (paused)",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var whenInUse: LocalizedString {
                LocalizedString { String(
                    localized: "settings.status.whenInUse",
                    defaultValue: "While Using only — needs Always",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var notDetermined: LocalizedString {
                LocalizedString { String(
                    localized: "settings.status.notDetermined",
                    defaultValue: "Location access not set up",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var denied: LocalizedString {
                LocalizedString { String(
                    localized: "settings.status.denied",
                    defaultValue: "Location access denied",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var restricted: LocalizedString {
                LocalizedString { String(
                    localized: "settings.status.restricted",
                    defaultValue: "Location access restricted",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Manual {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.manual.header",
                    defaultValue: "Manual entry",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var link: LocalizedString {
                LocalizedString { String(
                    localized: "settings.manual.link",
                    defaultValue: "Log or override a day",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.manual.footer",
                    defaultValue: "Backfill a trip the GPS missed, or correct a day by hand.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum AppIcon {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.appIcon.header",
                    defaultValue: "Appearance",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var link: LocalizedString {
                LocalizedString { String(
                    localized: "settings.appIcon.link",
                    defaultValue: "App icon",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.appIcon.footer",
                    defaultValue: "Pick the icon Where shows on your Home Screen.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Debug {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.debug.header",
                    defaultValue: "Developer",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var logsLink: LocalizedString {
                LocalizedString { String(
                    localized: "settings.debug.logsLink",
                    defaultValue: "Logs",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.debug.footer",
                    defaultValue: "On-device logs and data tools. Debug builds only.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var logsTitle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.debug.logsTitle",
                    defaultValue: "Logs",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var inspectorLink: LocalizedString {
                LocalizedString { String(
                    localized: "settings.debug.inspectorLink",
                    defaultValue: "SwiftData Inspector",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var inspectorTitle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.debug.inspectorTitle",
                    defaultValue: "SwiftData",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Reminders {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reminders.header",
                    defaultValue: "Reminders",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var toggle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reminders.toggle",
                    defaultValue: "Daily logging reminder",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var time: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reminders.time",
                    defaultValue: "Remind me at",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reminders.footer",
                    defaultValue: "If a day hasn't been logged, we'll nudge you before it ends and badge the app. The reminder clears itself once the day is recorded.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var openSettings: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reminders.openSettings",
                    defaultValue: "Allow notifications",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var deniedFooter: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reminders.deniedFooter",
                    defaultValue: "Notifications are turned off for Where, so reminders and the badge can't appear. Turn them on in Settings.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Summary {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.summary.header",
                    defaultValue: "Daily summary",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var toggle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.summary.toggle",
                    defaultValue: "Daily summary",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var time: LocalizedString {
                LocalizedString { String(
                    localized: "settings.summary.time",
                    defaultValue: "Send at",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.summary.footer",
                    defaultValue: "Get a morning recap of how many days you've logged in each region so far this year.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var deniedFooter: LocalizedString {
                LocalizedString { String(
                    localized: "settings.summary.deniedFooter",
                    defaultValue: "Notifications are turned off for Where, so the daily summary can't appear. Turn them on in Settings.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Data {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.data.header",
                    defaultValue: "Data",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var cancel: LocalizedString {
                LocalizedString { String(
                    localized: "settings.data.cancel",
                    defaultValue: "Cancel",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static func erase(year: Int) -> LocalizedString {
                LocalizedString { String(
                    localized: "settings.data.erase",
                    defaultValue: "Erase \(yearText(year)) data",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static func confirmMessage(year: Int) -> LocalizedString {
                LocalizedString { String(
                    localized: "settings.data.confirmMessage",
                    defaultValue: "This removes every sample, manual day, and piece of evidence in \(yearText(year)). It can't be undone.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static func footer(year: Int) -> LocalizedString {
                LocalizedString { String(
                    localized: "settings.data.footer",
                    defaultValue: "Acts on the year selected on the Primary tab (\(yearText(year))).",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Reset {
            static var erase: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reset.erase",
                    defaultValue: "Erase all data & reset",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var confirm: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reset.confirm",
                    defaultValue: "Erase Everything & Reset",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var message: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reset.message",
                    defaultValue: "This erases every sample, manual day, and piece of evidence on this device and returns you to first-run setup. It can't be undone.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.reset.footer",
                    defaultValue: "Starts over from scratch, as if you'd just installed Where.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }

        enum Backup {
            static var header: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.header",
                    defaultValue: "Backup",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var footer: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.footer",
                    defaultValue: "Export your whole history as a .zip you can email or save to Files, then import it on another device to restore everything.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var export: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.export",
                    defaultValue: "Export data",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            /// Title shown in the system share sheet preview for an exported backup.
            static var shareTitle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.shareTitle",
                    defaultValue: "Where Backup",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var importData: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.import",
                    defaultValue: "Import data",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var importing: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.importing",
                    defaultValue: "Importing…",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var errorTitle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.errorTitle",
                    defaultValue: "Backup failed",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var importStrategyTitle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.importStrategy.title",
                    defaultValue: "Import backup",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var importStrategyMessage: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.importStrategy.message",
                    defaultValue: "Merge keeps everything already on this device and adds the file's records. Replace erases this device first, then restores only what's in the file.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var merge: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.merge",
                    defaultValue: "Merge",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var replace: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.replace",
                    defaultValue: "Replace all",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static var importedTitle: LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.imported.title",
                    defaultValue: "Backup imported",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }

            static func importedMessage(
                samples: Int,
                evidence: Int,
                manualDays: Int,
            ) -> LocalizedString {
                LocalizedString { String(
                    localized: "settings.backup.imported.message",
                    defaultValue: "Imported \(samples) location samples, \(evidence) pieces of evidence, and \(manualDays) manual days.",
                    bundle: .module,
                    locale: $0?.locale ?? .current,
                ) }
            }
        }
    }

    // MARK: App icon picker

    enum AppIcon {
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.title",
                defaultValue: "App Icon",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var current: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.current",
                defaultValue: "Current",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var set: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.set",
                defaultValue: "Set as App Icon",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var appearanceLight: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.appearance.light",
                defaultValue: "Light",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var appearanceDark: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.appearance.dark",
                defaultValue: "Dark",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var appearanceHint: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.appearance.hint",
                defaultValue: "Tap the icon to preview light and dark.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var errorTitle: LocalizedString {
            LocalizedString { String(
                localized: "appIcon.error.title",
                defaultValue: "Couldn't Change Icon",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Manual entry

    enum ManualEntry {
        static var pickerLabel: LocalizedString {
            LocalizedString { String(
                localized: "manual.entry.pickerLabel",
                defaultValue: "Entry",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var modeSingleDay: LocalizedString {
            LocalizedString { String(
                localized: "manual.mode.singleDay",
                defaultValue: "Single day",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var modeRange: LocalizedString {
            LocalizedString { String(
                localized: "manual.mode.range",
                defaultValue: "Date range",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var day: LocalizedString {
            LocalizedString { String(
                localized: "manual.day",
                defaultValue: "Day",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var from: LocalizedString {
            LocalizedString { String(
                localized: "manual.from",
                defaultValue: "From",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var through: LocalizedString {
            LocalizedString { String(
                localized: "manual.through",
                defaultValue: "Through",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var singleDayFooter: LocalizedString {
            LocalizedString { String(
                localized: "manual.singleDay.footer",
                defaultValue: "Time travel: tell Where where you really were.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var regionsHeader: LocalizedString {
            LocalizedString { String(
                localized: "manual.regions.header",
                defaultValue: "Regions",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var regionsFooter: LocalizedString {
            LocalizedString { String(
                localized: "manual.regions.footer",
                defaultValue: "Saving replaces any manual regions you previously set for those days.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var title: LocalizedString {
            LocalizedString { String(
                localized: "manual.title",
                defaultValue: "Log a Day",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var save: LocalizedString {
            LocalizedString { String(
                localized: "manual.save",
                defaultValue: "Save",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var saveErrorTitle: LocalizedString {
            LocalizedString { String(
                localized: "manual.saveError.title",
                defaultValue: "Couldn't save that day",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static func rangeFooter(count: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "manual.range.footer",
                defaultValue: "Backfilling \(count) days.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Timeline

    enum Timeline {
        static var done: LocalizedString {
            LocalizedString { String(
                localized: "timeline.done",
                defaultValue: "Done",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyTitle: LocalizedString {
            LocalizedString { String(
                localized: "timeline.empty.title",
                defaultValue: "No stays yet",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyDescription: LocalizedString {
            LocalizedString { String(
                localized: "timeline.empty.description",
                defaultValue: "Once Where has a run of days in a region, your stays will appear here.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static func title(year: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "timeline.title",
                defaultValue: "Timeline · \(yearText(year))",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static func rowAccessibility(region: String, range: String, days: Int) -> LocalizedString {
            LocalizedString { config in
                String(
                    localized: "timeline.row.accessibility",
                    defaultValue: "\(region), \(range), \(LocalizedStrings.Common.dayCount(days).localized(config))",
                    bundle: .module,
                    locale: config?.locale ?? .current,
                )
            }
        }
    }

    // MARK: Missing days

    enum MissingDays {
        static var title: LocalizedString {
            LocalizedString { String(
                localized: "missingDays.title",
                defaultValue: "Missing days",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var done: LocalizedString {
            LocalizedString { String(
                localized: "missingDays.done",
                defaultValue: "Done",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var header: LocalizedString {
            LocalizedString { String(
                localized: "missingDays.header",
                defaultValue: "Days to backfill",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var footer: LocalizedString {
            LocalizedString { String(
                localized: "missingDays.footer",
                defaultValue: "Tap a stretch to record where you were. Today is included until something logs it.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyTitle: LocalizedString {
            LocalizedString { String(
                localized: "missingDays.empty.title",
                defaultValue: "All caught up",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var emptyDescription: LocalizedString {
            LocalizedString { String(
                localized: "missingDays.empty.description",
                defaultValue: "Every day this year has something logged.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Missing-day banner

    enum MissingBanner {
        static func compact(count: Int) -> LocalizedString {
            LocalizedString { config in
                count == 1
                    ? String(
                        localized: "missing.banner.compact.one",
                        defaultValue: "1 day needs a location",
                        bundle: .module,
                        locale: config?.locale ?? .current,
                    )
                    : String(
                        localized: "missing.banner.compact.other",
                        defaultValue: "\(count) days need a location",
                        bundle: .module,
                        locale: config?.locale ?? .current,
                    )
            }
        }

        static var accessibilityHint: LocalizedString {
            LocalizedString { String(
                localized: "missing.banner.accessibilityHint",
                defaultValue: "Opens the list of days that still need logging.",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }

    // MARK: Widgets

    enum Widget {
        static var todayTitle: LocalizedString {
            LocalizedString { String(
                localized: "widget.today.title",
                defaultValue: "Today",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var todayEmpty: LocalizedString {
            LocalizedString { String(
                localized: "widget.today.empty",
                defaultValue: "Nothing logged yet",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static func yearTitle(year: Int) -> LocalizedString {
            LocalizedString { String(
                localized: "widget.year.title",
                defaultValue: "Days in \(yearText(year))",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }

        static var yearEmpty: LocalizedString {
            LocalizedString { String(
                localized: "widget.year.empty",
                defaultValue: "No days logged",
                bundle: .module,
                locale: $0?.locale ?? .current,
            ) }
        }
    }
}

// MARK: Helpers

/// Year without a grouping separator ("2026", not "2,026").
private func yearText(_ year: Int) -> String {
    year.formatted(.number.grouping(.never))
}
