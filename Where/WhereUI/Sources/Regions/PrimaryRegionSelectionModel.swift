import Foundation
import Observation
import RegionKit
import WhereCore

/// The view-scoped model behind the primary-region picker + customization flow,
/// shared by onboarding and Settings. Holds the ordered selection (capped at
/// ``maxSelection``), each region's in-progress ``RegionAppearance`` draft, and
/// the commit that syncs the choice to the store through a `WhereServices`
/// collaborator.
///
/// The order of ``selectedRegions`` is the pick order — it drives the
/// customization step sequence and the stored `PrimaryRegion.order`.
@MainActor
@Observable
public final class PrimaryRegionSelectionModel {
    /// The most primary regions a user can pick.
    public static let maxSelection = 5

    /// The regions offered, in catalog order.
    public let available: [Region]

    struct Browse {
        let usedThisYear: [Region]
        let countryGroups: [CountryGroup]
    }

    /// Countries include all remaining regions. A year shortcut is visible while its country is
    /// closed.
    func browse(expandedCountries: Set<RegionCatalog.Node.ID?>) -> Browse {
        let highlighted = selectedNewestFirst
        let remaining = available.filter { !highlighted.contains($0) }
        let groups = CountryGroup.groups(for: remaining)
        let expanded = groups.filter { expandedCountries.contains($0.id) }.flatMap(\.regions)
        let shortcutRegions = (usedThisYear ?? []).subtracting(expanded)
        let shortcuts = remaining.filter { $0 != .other && shortcutRegions.contains($0) }
        return Browse(usedThisYear: shortcuts, countryGroups: groups)
    }

    struct CountryGroup: Identifiable {
        let country: RegionCatalog.Node?
        var regions: [Region]
        var id: RegionCatalog.Node.ID? {
            country?.id
        }

        fileprivate static func groups(for regions: [Region]) -> [Self] {
            let catalog = RegionCatalog.shared
            var groups: [Self] = []
            for region in regions {
                let parent = catalog.node(for: region).flatMap(catalog.parent(of:))
                let country = parent?.kind == .country ? parent : nil
                if let index = groups.firstIndex(where: { $0.id == country?.id }) {
                    groups[index].regions.append(region)
                } else {
                    groups.append(Self(country: country, regions: [region]))
                }
            }
            return groups
        }
    }

    /// Both supported countries use a two-letter postal code in their subdivision IDs.
    struct SubdivisionCode {
        let country: String
        let subdivision: String
    }

    var searchText = ""

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    enum SearchResults: Equatable {
        case noMatches
        /// All matches already appear in the selected section.
        case allSelected
        case available([Region])
    }

    /// Exact postal-code matches precede name matches from either country.
    var searchResults: SearchResults {
        let query = searchQuery
        let postalCode = query.uppercased()
        var codeMatches: [Region] = []
        var nameMatches: [Region] = []
        for region in available {
            if code(for: region)?.subdivision == postalCode {
                codeMatches.append(region)
            } else if query.isEmpty || region.localizedName.localizedStandardContains(query) {
                nameMatches.append(region)
            }
        }
        let matches = codeMatches + nameMatches
        guard !matches.isEmpty else { return .noMatches }
        let highlighted = selectedNewestFirst
        let remaining = matches.filter { !highlighted.contains($0) }
        return remaining.isEmpty ? .allSelected : .available(remaining)
    }

    func code(for region: Region) -> SubdivisionCode? {
        let parts = region.rawValue.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, parts[0] == "us" || parts[0] == "ca", parts[1].count == 2
        else { return nil }
        return SubdivisionCode(country: parts[0].uppercased(), subdivision: String(parts[1]))
    }

    /// The picked regions, in pick order.
    public private(set) var selectedRegions: [Region] = []

    /// A backup merge can restore more than five picks. The newest five appear at the top.
    /// Earlier picks remain checked in browse and search until the user removes them.
    var selectedNewestFirst: [Region] {
        Array(selectedRegions.reversed().prefix(Self.maxSelection))
    }

    /// Per-region appearance drafts. A region without an entry uses its
    /// ``RegionAppearanceCatalog/defaultAppearance(for:)`` until customized.
    private var drafts: [Region: RegionAppearance] = [:]

    /// Settings supplies the regions with days in the selected year.
    private var usedThisYear: Set<Region>?

    /// Settings enables shortcuts for regions used in the selected year.
    public var isGrouped: Bool {
        usedThisYear != nil
    }

    /// Loggable US and Canadian subdivisions in manifest order.
    public static let supportedRegions: [Region] = {
        let countries: Set<RegionCatalog.Node.ID> = [
            .init(rawValue: "united-states"),
            .init(rawValue: "canada"),
        ]
        return RegionCatalog.shared.nodes.compactMap { node in
            guard let parent = node.parentID, countries.contains(parent) else { return nil }
            return node.region
        }
    }()

    /// Loggable US jurisdictions in their canonical order.
    public static var usRegions: [Region] {
        let catalog = RegionCatalog.shared
        guard let country = catalog.node(id: .init(rawValue: "united-states")) else { return [] }
        return catalog.children(of: country).compactMap(\.region)
    }

    /// A fresh picker with nothing selected (onboarding).
    public convenience init(available: [Region] = PrimaryRegionSelectionModel.supportedRegions) {
        self.init(existing: [], available: available)
    }

    /// A picker seeded from the user's existing primary regions (Settings).
    /// Selection and drafts are restored so re-opening the editor shows the
    /// current picks.
    ///
    /// Saving replaces the primary rows with the offered regions the user picked.
    public init(
        existing: [PrimaryRegion],
        available: [Region] = PrimaryRegionSelectionModel.supportedRegions,
    ) {
        self.available = available
        let offered = Set(available)
        selectedRegions = existing.map(\.region).filter { offered.contains($0) }
        var drafts: [Region: RegionAppearance] = [:]
        for entry in existing {
            if let appearance = entry.appearance { drafts[entry.region] = appearance }
        }
        self.drafts = drafts
    }

    public var selectionCount: Int {
        selectedRegions.count
    }

    public var isAtCapacity: Bool {
        selectedRegions.count >= Self.maxSelection
    }

    public var hasSelection: Bool {
        !selectedRegions.isEmpty
    }

    public func isSelected(_ region: Region) -> Bool {
        selectedRegions.contains(region)
    }

    /// Whether tapping `region` would do something: always true when it's
    /// already selected (a tap removes it), otherwise only when there's room.
    public func canToggle(_ region: Region) -> Bool {
        isSelected(region) || (!isAtCapacity && available.contains(region))
    }

    /// Add `region` (appending to preserve pick order) or remove it. A no-op
    /// when adding past ``maxSelection``.
    public func toggle(_ region: Region) {
        if let index = selectedRegions.firstIndex(of: region) {
            selectedRegions.remove(at: index)
        } else if canToggle(region) {
            selectedRegions.append(region)
        }
    }

    /// The current appearance draft for `region` (its default until edited).
    public func appearance(for region: Region) -> RegionAppearance {
        drafts[region] ?? RegionAppearanceCatalog.defaultAppearance(for: region)
    }

    public func setColor(_ color: RegionColorToken, for region: Region) {
        var appearance = appearance(for: region)
        appearance.color = color
        drafts[region] = appearance
    }

    public func setEmoji(_ emoji: String, for region: Region) {
        var appearance = appearance(for: region)
        appearance.emoji = emoji
        drafts[region] = appearance
    }

    public func setSymbol(_ symbolName: RegionSymbol, for region: Region) {
        var appearance = appearance(for: region)
        appearance.symbolName = symbolName
        drafts[region] = appearance
    }

    /// The picked regions as ordered ``PrimaryRegion`` values (pick order →
    /// `order`), each carrying its current appearance draft.
    public var desiredPrimaryRegions: [PrimaryRegion] {
        selectedRegions.enumerated().map { index, region in
            PrimaryRegion(region: region, appearance: appearance(for: region), order: index)
        }
    }

    /// Persist the selection by replacing the primary set with it — one atomic
    /// transaction (upserts + removals-by-omission). Throws on failure so the
    /// caller can surface it; no partial success is hidden.
    public func commit(using session: WhereSession) async throws {
        try await commit(to: session.services)
    }

    /// Commit against a scope rather than a session, for onboarding — which
    /// runs at the head of the launch, where the scope it just logged in to
    /// exists but no session does yet.
    func commit(using scope: WhereScope) async throws {
        try await commit(to: scope.services)
    }

    private func commit(to services: WhereServices) async throws {
        try await services.setPrimaryRegions(desiredPrimaryRegions)
    }

    /// Use the selected year's report for Settings shortcuts.
    public func applyGrouping(usedThisYear: Set<Region>) {
        self.usedThisYear = usedThisYear
    }
}
