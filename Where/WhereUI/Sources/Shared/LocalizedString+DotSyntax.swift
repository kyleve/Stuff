import StuffCore

/// Leading-dot access to ``LocalizedStrings`` wherever a `LocalizedString` is
/// expected (e.g. `Text(localized: .primary.emptyDescription)`,
/// `.navigationTitle(.settings.title)`).
///
/// Each accessor returns the metatype of the matching `LocalizedStrings` nested
/// enum, so the existing `static let` / `static func` members chain straight off
/// it — there's no second copy of any string, and the `./localize` script still
/// reads the one set of `.module(...)` literals in `LocalizedStrings.swift`.
///
/// This only fires where the contextual type is `LocalizedString`. Plain `String`
/// sites (`Button`, `Label`, interpolation, …) keep using
/// `LocalizedStrings.<Category>.<member>.localized`.
extension LocalizedString {
    static var tabs: LocalizedStrings.Tabs.Type {
        LocalizedStrings.Tabs.self
    }

    static var common: LocalizedStrings.Common.Type {
        LocalizedStrings.Common.self
    }

    static var primary: LocalizedStrings.Primary.Type {
        LocalizedStrings.Primary.self
    }

    static var secondary: LocalizedStrings.Secondary.Type {
        LocalizedStrings.Secondary.self
    }

    static var relabel: LocalizedStrings.Relabel.Type {
        LocalizedStrings.Relabel.self
    }

    static var onboarding: LocalizedStrings.Onboarding.Type {
        LocalizedStrings.Onboarding.self
    }

    static var migration: LocalizedStrings.Migration.Type {
        LocalizedStrings.Migration.self
    }

    static var launch: LocalizedStrings.Launch.Type {
        LocalizedStrings.Launch.self
    }

    static var settings: LocalizedStrings.Settings.Type {
        LocalizedStrings.Settings.self
    }

    static var appIcon: LocalizedStrings.AppIcon.Type {
        LocalizedStrings.AppIcon.self
    }

    static var manualEntry: LocalizedStrings.ManualEntry.Type {
        LocalizedStrings.ManualEntry.self
    }

    static var timeline: LocalizedStrings.Timeline.Type {
        LocalizedStrings.Timeline.self
    }

    static var missingDays: LocalizedStrings.MissingDays.Type {
        LocalizedStrings.MissingDays.self
    }

    static var missingBanner: LocalizedStrings.MissingBanner
        .Type
    {
        LocalizedStrings.MissingBanner.self
    }

    static var widget: LocalizedStrings.Widget.Type {
        LocalizedStrings.Widget.self
    }
}

/// Nested categories: reached as `.secondary.region.…` / `.settings.location.…`.
extension LocalizedStrings.Secondary {
    static var region: Region.Type {
        Region.self
    }
}

extension LocalizedStrings.Settings {
    static var permissionAlert: PermissionAlert.Type {
        PermissionAlert.self
    }

    static var location: Location.Type {
        Location.self
    }

    static var status: Status.Type {
        Status.self
    }

    static var manual: Manual.Type {
        Manual.self
    }

    static var appIcon: AppIcon.Type {
        AppIcon.self
    }

    static var debug: Debug.Type {
        Debug.self
    }

    static var reminders: Reminders.Type {
        Reminders.self
    }

    static var summary: Summary.Type {
        Summary.self
    }

    static var data: Data.Type {
        Data.self
    }

    static var reset: Reset.Type {
        Reset.self
    }

    static var backup: Backup.Type {
        Backup.self
    }
}
