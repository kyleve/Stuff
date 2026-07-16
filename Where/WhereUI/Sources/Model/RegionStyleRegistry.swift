import RegionKit
import Synchronization
import WhereCore

/// Process-wide source of the user's picked region appearances that backs
/// `RegionStyle.style(for:)`. It exists so the ergonomic, synchronous
/// `region.style` accessor — read from view bodies, widget views, and App
/// Intents snippets alike — can resolve *persisted* looks without every call
/// site threading a lookup or an environment value.
///
/// Written from a single place per process: the app seeds it from the store via
/// `WhereSession` (at launch and on every store change); the widget process
/// seeds it from the `WidgetSnapshot` it renders. Reads are lock-guarded so the
/// off-main-actor callers (snippets) are safe. A region with no entry falls back
/// to the deterministic default look in `RegionStyle`.
public final class RegionStyleRegistry: Sendable {
    public static let shared = RegionStyleRegistry()

    private let storage = Mutex<[Region: RegionAppearance]>([:])

    public init() {}

    /// The picked appearance for `region`, or `nil` when the user hasn't
    /// customized it (so `RegionStyle` uses its fallback default).
    public func appearance(for region: Region) -> RegionAppearance? {
        storage.withLock { $0[region] }
    }

    /// Replace the whole map — the primary-region set is small and always read
    /// as a whole, so a wholesale swap keeps the registry a faithful mirror of
    /// the store (a removed region loses its entry, not just changed ones).
    public func replaceAll(_ appearances: [Region: RegionAppearance]) {
        storage.withLock { $0 = appearances }
    }

    /// Build the map from ordered `PrimaryRegion`s, keeping only the ones that
    /// carry a resolved appearance.
    public func replaceAll(from primaryRegions: [PrimaryRegion]) {
        var map: [Region: RegionAppearance] = [:]
        for entry in primaryRegions {
            if let appearance = entry.appearance { map[entry.region] = appearance }
        }
        replaceAll(map)
    }
}
