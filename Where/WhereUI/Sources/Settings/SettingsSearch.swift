import SwiftUI

/// The eight top-level Settings groups. Each drills into its own sub-screen; the
/// top-level list and `SettingsRoute` route on these, and the
/// `navigationDestination` switch (in `SettingsView`) builds a screen for every
/// case with no `default:`, so adding a case is a compile error until wired.
enum SettingsDestination: Hashable, CaseIterable {
    case location
    case regions
    case alerts
    case appearance
    case year
    case backup
    case data

    /// The localized title shown on the top-level drill-in row and as the parent
    /// group label under a search result.
    var rowTitle: String {
        switch self {
            case .location: Strings.settingsLocationHeader
            case .regions: Strings.settingsRegionsSection
            case .alerts: Strings.settingsAlertsGroup
            case .appearance: Strings.settingsAppearanceGroup
            case .year: Strings.settingsYearHeader
            case .backup: Strings.settingsBackupHeader
            case .data: Strings.settingsDataHeader
        }
    }

    /// The SF Symbol shown as the row's leading icon.
    var systemImage: String {
        switch self {
            case .location: "location.fill"
            case .regions: "map.fill"
            case .alerts: "bell.badge"
            case .appearance: "paintbrush.fill"
            case .year: "calendar"
            case .backup: "externaldrive.fill"
            case .data: "trash.fill"
        }
    }

    /// The fill color of the row's iOS-style icon chip. Lives here (like
    /// `systemImage`) rather than in the stylesheet, which deliberately holds no
    /// accent/adaptive colors.
    var iconColor: Color {
        switch self {
            case .location: .blue
            case .regions: .green
            case .alerts: .red
            case .appearance: .purple
            case .year: .orange
            case .backup: .teal
            case .data: .gray
        }
    }

    /// Whether the group opens as a modal **sheet** (an editor/commit flow with
    /// explicit Cancel/Save) rather than a pushed sub-screen. Regions is the one
    /// top-level committing editor; the rest are plain drill-in settings.
    var isSheet: Bool {
        switch self {
            case .regions: true
            case .location, .alerts, .appearance, .year, .backup, .data: false
        }
    }
}

/// The visual grouping of the top-level settings list into separated blocks
/// (headerless, matching the iOS Settings app). Every ``SettingsDestination``
/// belongs to exactly one block — `SettingsSearchTests` guards full, unique
/// coverage — and the block order is the on-screen order.
enum SettingsListSection: CaseIterable {
    case tracking
    case notifications
    case display
    case data

    var destinations: [SettingsDestination] {
        switch self {
            case .tracking: [.location, .regions]
            case .notifications: [.alerts]
            case .display: [.appearance, .year]
            case .data: [.backup, .data]
        }
    }
}

/// A per-screen setting identity. Conformers are small, screen-local enums (e.g.
/// `LocationSettingsView.Item`) that also carry their own localized search text,
/// so the search index is *derived* from the cases and can't drift from them.
protocol SettingsItem: Hashable, CaseIterable {
    /// The setting's localized name, matched by search and shown in results.
    var title: String { get }
    /// Extra localized synonyms so a search finds the setting by related words.
    var keywords: [String] { get }
}

extension SettingsItem {
    /// Splits a comma-separated localized keyword string (one catalog entry per
    /// setting) into trimmed, non-empty tokens.
    func splitKeywords(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// A type-erased focus token you can *only* build from a ``SettingsItem`` — a
/// stray `AnyHashable` (a `String`, an unrelated enum) can't be routed as a
/// focus target. `AnyHashable` equality includes the concrete type, so tokens
/// from different screens' `Item` enums never collide, so no central id registry
/// is needed.
struct SettingsFocus: Hashable {
    fileprivate let erased: AnyHashable

    init(_ item: some SettingsItem) {
        erased = AnyHashable(item)
    }
}

/// One searchable setting, paired with the screen that owns it. Produced by a
/// ``SettingsSection`` from its `Item` cases; the catalog flattens every
/// section's results into the single searchable index.
struct SettingsSearchResult: Identifiable {
    let destination: SettingsDestination
    let focus: SettingsFocus
    let title: String
    let keywords: [String]

    var id: SettingsFocus {
        focus
    }

    /// Case-insensitive match on the title or any keyword.
    func matches(_ query: String) -> Bool {
        if title.localizedCaseInsensitiveContains(query) { return true }
        return keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// A settings sub-screen that contributes to search. It declares its screen-local
/// `Item` type and destination; `searchResults` is derived by default from
/// `Item.allCases`, so every case is registered without a hand-maintained list.
///
/// `@MainActor` because the conformers are SwiftUI `View`s (main-actor isolated);
/// the catalog is read from the main actor (the Settings screen, tests) too.
@MainActor
protocol SettingsSection {
    associatedtype Item: SettingsItem
    static var destination: SettingsDestination { get }
    static var searchResults: [SettingsSearchResult] { get }
}

extension SettingsSection {
    static var searchResults: [SettingsSearchResult] {
        Item.allCases.map { item in
            SettingsSearchResult(
                destination: destination,
                focus: SettingsFocus(item),
                title: item.title,
                keywords: item.keywords,
            )
        }
    }
}

/// The single, small registration point: the participating sub-screens, whose
/// results are concatenated into one index. Item ownership stays decentralized
/// (each screen declares its own `Item` + derives its own `searchResults`); this
/// only lists the screens.
///
/// The results are concatenated per concrete screen rather than iterated over a
/// `[any SettingsSection.Type]`: dispatching a static protocol requirement (or a
/// `\.searchResults` key path) through an existential metatype tickles a SILGen
/// crash in the current toolchain. Naming each screen once here is the same
/// registration surface without the miscompile.
@MainActor
enum SettingsCatalog {
    /// Every searchable setting across all screens.
    static let results: [SettingsSearchResult] =
        LocationSettingsView.searchResults
            + RegionsSettingsView.searchResults
            + AlertsSettingsView.searchResults
            + AppearanceSettingsView.searchResults
            + VisibleYearSettingsView.searchResults
            + BackupSettingsView.searchResults
            + DataSettingsView.searchResults

    /// The results matching a (trimmed, non-empty) query.
    static func results(matching query: String) -> [SettingsSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return results.filter { $0.matches(trimmed) }
    }
}

/// The navigation value pushed for a Settings drill-in. Two inits keep it
/// type-safe: a group row builds one from a bare ``SettingsDestination`` (no
/// focus); a search result builds one from a ``SettingsSearchResult`` (which
/// pairs the destination and focus from one owning screen). There is no
/// memberwise init, so a mismatched "destination + foreign item" can't be spelt.
struct SettingsRoute: Hashable {
    let destination: SettingsDestination
    let focus: SettingsFocus?

    init(_ destination: SettingsDestination) {
        self.destination = destination
        focus = nil
    }

    init(_ result: SettingsSearchResult) {
        destination = result.destination
        focus = result.focus
    }
}
