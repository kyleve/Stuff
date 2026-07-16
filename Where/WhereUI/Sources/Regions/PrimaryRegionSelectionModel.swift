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

    /// The regions tracked when the model was created, so the commit can
    /// untrack the ones the user removed.
    private let initialRegions: Set<Region>

    /// The US jurisdictions from the catalog, in canonical order — the default
    /// `available` set for the picker.
    public static var usRegions: [Region] {
        RegionCatalog.shared.all.filter { $0.rawValue.hasPrefix("us-") }
    }

    /// A fresh picker with nothing selected (onboarding).
    public init(available: [Region] = PrimaryRegionSelectionModel.usRegions) {
        self.available = available
        initialRegions = []
    }

    /// A picker seeded from the user's existing primary regions (Settings).
    /// Selection and drafts are restored so re-opening the editor shows the
    /// current picks; regions outside `available` (e.g. legacy non-US defaults)
    /// are still counted in `initialRegions` so the commit untracks them.
    public init(
        existing: [PrimaryRegion],
        available: [Region] = PrimaryRegionSelectionModel.usRegions,
    ) {
        self.available = available
        initialRegions = Set(existing.map(\.region))
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

    /// Persist the selection: untrack removed regions, then upsert each picked
    /// region's appearance and pick order. Runs each write through the services
    /// layer (which owns the `perform` transaction). Throws on the first
    /// failure so the caller can surface it — no partial success is hidden.
    public func commit(using session: WhereSession) async throws {
        let selected = Set(selectedRegions)
        for region in initialRegions where !selected.contains(region) {
            try await session.services.removePrimaryRegion(id: region.rawValue)
        }
        for (index, region) in selectedRegions.enumerated() {
            try await session.services.setPrimaryRegion(
                appearance(for: region),
                id: region.rawValue,
                order: index,
            )
        }
    }
}
