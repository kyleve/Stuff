import LocalizationKit

/// Catalog-backed strings for WhereCore.
///
/// Swift is the source of truth for keys and English defaults; the sibling
/// `Resources/Localizable.xcstrings` owns plural `variations` and translations.
/// The root `./localize` script reconciles the catalog from this file.
enum LocalizedStrings {
    // MARK: Regions

    enum Region {
        static let california: LocalizedString = .module("region.california", "California")
        static let newYork: LocalizedString = .module("region.newYork", "New York")
        static let canada: LocalizedString = .module("region.canada", "Canada")
        static let europeanUnion: LocalizedString = .module(
            "region.europeanUnion",
            "European Union",
        )
        static let other: LocalizedString = .module("region.other", "Other")
    }

    // MARK: Reminders

    enum Reminder {
        static let notificationTitle: LocalizedString = .module(
            "reminder.notification.title",
            "Log today's location",
        )

        static let notificationBody: LocalizedString = .module(
            "reminder.notification.body",
            "Open Where before the day ends so we don't miss logging today.",
        )
    }

    // MARK: Daily summary

    enum Summary {
        static let notificationTitle: LocalizedString = .module(
            "summary.notification.title",
            "Your year so far",
        )

        static let notificationBodyEmpty: LocalizedString = .module(
            "summary.notification.body.empty",
            "No days logged yet this year.",
        )

        static func dayCount(_ days: Int) -> LocalizedString {
            .module("summary.notification.dayCount", "\(days) days")
        }

        static let regionDays: LocalizedString = .module(
            "summary.notification.regionDays",
            "%1$@ in %2$@",
        )
    }

    // MARK: Backup

    enum Backup {
        static let manifestMissing: LocalizedString = .module(
            "backup.error.manifestMissing",
            "This file isn't a Where backup (no manifest was found).",
        )

        static func unsupportedFormatVersion(_ version: Int) -> LocalizedString {
            .module(
                "backup.error.unsupportedFormatVersion",
                "This backup was created by a newer version of Where (format \(version)) and can't be imported.",
            )
        }
    }
}
