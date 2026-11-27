import Observation
import RegionKit
import WhereCore

/// The pending primary-region edits owned by one onboarding flow or Settings sheet.
/// Pick order drives customization and the saved `PrimaryRegion.order`. Each
/// screen reads or edits this same draft until the flow commits it.
@MainActor
@Observable
public final class PrimaryRegionDraft {
    /// The most primary regions a user can pick.
    public static let maxSelection = 5

    /// The regions offered, in catalog order.
    public let available: [Region]

    /// The picked regions, in pick order.
    public private(set) var selectedRegions: [Region] = []

    /// Per-region appearance drafts. A region without an entry uses its
    /// ``RegionAppearanceCatalog/defaultAppearance(for:)`` until customized.
    private var drafts: [Region: RegionAppearance] = [:]

    /// Loggable US and Canadian subdivisions in manifest order.
    public static let supportedRegions: [Region] = {
        let countries: Set<RegionCatalog.Node.ID> = [.unitedStates, .canada]
        return RegionCatalog.shared.nodes.compactMap { node in
            guard let parent = node.parentID, countries.contains(parent) else { return nil }
            return node.region
        }
    }()

    /// Loggable US jurisdictions in their canonical order.
    public static var usRegions: [Region] {
        let catalog = RegionCatalog.shared
        guard let country = catalog.node(id: .unitedStates) else { return [] }
        return catalog.children(of: country).compactMap(\.region)
    }

    /// Starts empty for onboarding or restores the offered picks for Settings.
    public init(
        existing: [PrimaryRegion] = [],
        available: [Region] = PrimaryRegionDraft.supportedRegions,
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

    /// The current appearance draft, with the default as a fallback until edited.
    public subscript(appearanceFor region: Region) -> RegionAppearance {
        get { drafts[region] ?? RegionAppearanceCatalog.defaultAppearance(for: region) }
        set { drafts[region] = newValue }
    }

    /// The picked regions as ordered ``PrimaryRegion`` values (pick order →
    /// `order`), each carrying its current appearance draft.
    public var desiredPrimaryRegions: [PrimaryRegion] {
        selectedRegions.enumerated().map { index, region in
            PrimaryRegion(region: region, appearance: self[appearanceFor: region], order: index)
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
}
