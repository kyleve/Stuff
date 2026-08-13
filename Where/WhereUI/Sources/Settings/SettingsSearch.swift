import SFSafeSymbols
import SwiftUI

/// The top-level Settings groups. Each drills into its own sub-screen; the
/// top-level list and `SettingsRoute` route on these, and the
/// `navigationDestination` switch (in `SettingsView`) builds a screen for every
/// case with no `default:`, so adding a case is a compile error until wired.
enum SettingsDestination: Hashable, CaseIterable {
    case attachments
    case loggedDays
    case devices
    case regions
    case alerts
    case appearance
    case year
    case siri
    case widgets
    case shareEvidence
    case estimatedTime
    case insightsAccuracy
    case personalization
    case data
    case about

    /// The localized title shown on the top-level drill-in row and as the parent
    /// group label under a search result.
    var rowTitle: String {
        switch self {
            case .attachments: String(localized: .settingsAttachmentsRow)
            case .loggedDays: String(localized: .settingsLoggedDaysRow)
            case .devices: String(localized: .settingsDevicesTitle)
            case .regions: String(localized: .settingsRegionsSection)
            case .alerts: String(localized: .settingsAlertsGroup)
            case .appearance: String(localized: .settingsAppearanceGroup)
            case .year: String(localized: .settingsYearHeader)
            case .siri: String(localized: .settingsExploreSiriRow)
            case .widgets: String(localized: .settingsExploreWidgetsRow)
            case .shareEvidence: String(localized: .settingsExploreEvidenceRow)
            case .estimatedTime: String(localized: .settingsExploreEstimatedTimeRow)
            case .insightsAccuracy: String(localized: .settingsExploreInsightsRow)
            case .personalization: String(localized: .settingsExplorePersonalizationRow)
            case .data: String(localized: .settingsDataHeader)
            case .about: String(localized: .settingsAboutHeader)
        }
    }

    /// The SF Symbol shown as the row's leading icon.
    var systemSymbol: SFSymbol {
        switch self {
            case .attachments: .paperclip
            case .loggedDays: .calendarBadgePlus
            case .devices: .iphoneAndArrowForward
            case .regions: .mapFill
            case .alerts: .bellBadge
            case .appearance: .paintbrushFill
            case .year: .calendar
            case .siri: .waveform
            case .widgets: .widgetSmall
            case .shareEvidence: .squareAndArrowDownFill
            case .estimatedTime: .chartLineUptrendXyaxis
            case .insightsAccuracy: .sparkles
            case .personalization: .paintpaletteFill
            case .data: .externaldriveFill
            case .about: .info
        }
    }

    /// The fill color of the row's iOS-style icon chip. Lives here (like
    /// `systemSymbol`) rather than in the stylesheet, which deliberately holds no
    /// accent/adaptive colors.
    var iconColor: Color {
        switch self {
            case .attachments: .indigo
            case .loggedDays: .mint
            case .devices: .blue
            case .regions: .green
            case .alerts: .red
            case .appearance: .purple
            case .year: .orange
            case .siri: .pink
            case .widgets: .cyan
            case .shareEvidence: .indigo
            case .estimatedTime: .blue
            case .insightsAccuracy: .orange
            case .personalization: .purple
            case .data: .teal
            case .about: .brown
        }
    }

    /// Whether the group is offered while the app is running on demo data.
    ///
    /// The two that aren't would each reach past the demo and touch the device:
    /// **data** backs up, restores, erases, and resets, while **appearance**
    /// includes setting an alternate app icon, which outlives the process. A
    /// demo leaves no trace, so it doesn't offer the ways to leave one.
    var isAvailableInDemoMode: Bool {
        switch self {
            case .data, .appearance: false
            case .attachments, .loggedDays, .devices, .regions, .alerts, .year, .siri, .widgets,
                 .shareEvidence, .estimatedTime, .insightsAccuracy, .personalization, .about:
                true
        }
    }

    /// Whether the group opens as a modal **sheet** (an editor/commit flow with
    /// explicit Cancel/Save) rather than a pushed sub-screen. Regions is the one
    /// top-level committing editor; the rest are plain drill-in settings.
    var isSheet: Bool {
        switch self {
            case .regions: true
            case .attachments, .loggedDays, .devices, .alerts, .appearance, .year, .siri, .widgets,
                 .shareEvidence, .estimatedTime, .insightsAccuracy, .personalization, .data, .about:
                false
        }
    }
}

/// The visual grouping of the top-level settings list into separated blocks
/// (headerless, matching the iOS Settings app). Every ``SettingsDestination``
/// belongs to exactly one block — `SettingsSearchTests` guards full, unique
/// coverage — and the block order is the on-screen order.
enum SettingsListSection: CaseIterable {
    case userData
    case tracking
    case notifications
    case display
    case exploreFeatures
    case storage
    /// Last on purpose: About is reference material, so it sits below everything
    /// actionable, where iOS Settings puts its own.
    case about

    var destinations: [SettingsDestination] {
        switch self {
            case .userData: [.attachments, .loggedDays, .regions]
            case .tracking: [.devices]
            case .notifications: [.alerts]
            case .display: [.appearance, .year]
            case .exploreFeatures:
                [
                    .siri,
                    .widgets,
                    .shareEvidence,
                    .estimatedTime,
                    .insightsAccuracy,
                    .personalization,
                ]
            case .storage: [.data]
            case .about: [.about]
        }
    }

    var headerTitle: String? {
        switch self {
            case .exploreFeatures: String(localized: .settingsExploreHeader)
            case .userData, .tracking, .notifications, .display, .storage, .about: nil
        }
    }
}

/// A per-screen setting identity. Conformers are small, screen-local enums (e.g.
/// `DevicesSettingsView.Item`) that also carry their own localized search text,
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
        if title.localizedStandardContains(query) { return true }
        return keywords.contains { $0.localizedStandardContains(query) }
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
        EvidenceListView.searchResults
            + LoggedDaysView.searchResults
            + DevicesSettingsView.searchResults
            + RegionsSettingsView.searchResults
            + AlertsSettingsView.searchResults
            + AppearanceSettingsView.searchResults
            + VisibleYearSettingsView.searchResults
            + SiriFeaturesView.searchResults
            + WidgetFeaturesView.searchResults
            + ShareEvidenceFeaturesView.searchResults
            + EstimatedTimeFeaturesView.searchResults
            + InsightsAccuracyFeaturesView.searchResults
            + PersonalizationFeaturesView.searchResults
            + DataSettingsView.searchResults
            + AboutSettingsView.searchResults

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
