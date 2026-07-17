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

    /// The regions offered, in catalog order (US jurisdictions only for now).
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

    /// The US jurisdictions from the catalog, in canonical order — the default
    /// `available` set for the picker.
    public static var usRegions: [Region] {
        RegionCatalog.shared.all.filter { $0.rawValue.hasPrefix("us-") }
    }

    /// A fresh picker with nothing selected (onboarding).
    public init(available: [Region] = PrimaryRegionSelectionModel.usRegions) {
        self.available = available
    }

    /// A picker seeded from the user's existing primary regions (Settings).
    /// Selection and drafts are restored so re-opening the editor shows the
    /// current picks.
    ///
    /// Regions outside `available` are dropped from the selection, so committing
    /// removes them (the commit replaces the whole primary set with what's
    /// selected). This is intentional: the app is US-only now, and the only
    /// non-US regions a user can have are the legacy default set (Canada / the
    /// EU, whose low-resolution polygons we no longer ship as pickable) — so a
    /// fresh install that opens the editor and saves converges to the US picks.
    public init(
        existing: [PrimaryRegion],
        available: [Region] = PrimaryRegionSelectionModel.usRegions,
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

    /// Whether tapping `region` would do something: always true when it's
    /// already selected (a tap removes it), otherwise only when there's room.
    public func canToggle(_ region: Region) -> Bool {
        isSelected(region) || !isAtCapacity
    }

    /// Add `region` (appending to preserve pick order) or remove it. A no-op
    /// when adding past ``maxSelection``.
    public func toggle(_ region: Region) {
        if let index = selectedRegions.firstIndex(of: region) {
            selectedRegions.remove(at: index)
        } else if !isAtCapacity {
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

    public func setSymbol(_ symbolName: String, for region: Region) {
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
        try await session.services.setPrimaryRegions(desiredPrimaryRegions)
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
