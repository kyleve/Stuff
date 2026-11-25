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

    /// The picked regions, in pick order.
    public private(set) var selectedRegions: [Region] = []

    /// Per-region appearance drafts. A region without an entry uses its
    /// ``RegionAppearanceCatalog/defaultAppearance(for:)`` until customized.
    private var drafts: [Region: RegionAppearance] = [:]

    /// The picks when the model was created — the stable "Your regions" group
    /// (so a row doesn't jump between sections as it's toggled). Empty for the
    /// onboarding picker.
    private var initialSelection: [Region] = []

    /// Regions with days in the selected year (from the report), used only to
    /// surface a "used this year" group in the grouped (Settings) list.
    private var usedThisYear: Set<Region> = []

    /// Whether the list groups into your-regions / used-this-year / everything-
    /// else. Off by default (onboarding shows the flat searchable list); Settings
    /// turns it on via ``applyGrouping(usedThisYear:)``.
    public private(set) var isGrouped = false

    /// Loggable North American countries and their subdivisions in manifest order.
    public static let supportedRegions: [Region] = {
        let countries: Set<RegionCatalog.Node.ID> = [
            .init(rawValue: "united-states"),
            .init(rawValue: Region.canada.rawValue),
        ]
        return RegionCatalog.shared.nodes.compactMap { node in
            countries.contains(node.parentID ?? node.id) ? node.region : nil
        }
    }()

    /// Loggable US jurisdictions in their canonical order.
    public static var usRegions: [Region] {
        let catalog = RegionCatalog.shared
        guard let country = catalog.node(id: .init(rawValue: "united-states")) else { return [] }
        return catalog.children(of: country).compactMap(\.region)
    }

    /// A fresh picker with nothing selected (onboarding).
    public init(available: [Region] = PrimaryRegionSelectionModel.supportedRegions) {
        self.available = available
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
        initialSelection = selectedRegions
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

    /// A country selection colors the area covered by its subdivisions. An explicitly
    /// selected subdivision uses its own color.
    func selectedRegionCoveringMapArea(_ region: Region) -> Region? {
        if isSelected(region) { return region }
        let catalog = RegionCatalog.shared
        guard let node = catalog.node(for: region), let parent = catalog.parent(of: node)?.region,
              isSelected(parent) else { return nil }
        return parent
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

    // MARK: - Grouping (Settings list)

    /// Turn on the grouped list, sourcing the "used this year" group from the
    /// selected year's regions. The your-regions group stays keyed on the picks
    /// at open (``initialSelection``), so rows don't jump while editing.
    public func applyGrouping(usedThisYear: Set<Region>) {
        self.usedThisYear = usedThisYear
        isGrouped = true
    }

    /// The shared three-way grouping of the offered regions — your picks at open
    /// (the stable reference set), used-this-year, everything else. Valid once
    /// ``isGrouped`` is true. Internal: the grouping type is a WhereUI detail.
    var grouping: RegionGrouping {
        RegionGrouping(available: available, primary: initialSelection, usedThisYear: usedThisYear)
    }
}
