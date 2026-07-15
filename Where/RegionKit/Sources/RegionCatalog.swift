import Foundation
import LogKit

/// The catalog of **available** regions, loaded once from the bundled
/// `regions.json` manifest. It is RegionKit's single source of the region
/// *list* and each region's metadata — the display name, an optional
/// localization key, and the per-region GeoJSON file — replacing what used to
/// be a hardcoded `Region` enum plus a separate name table.
///
/// Because the list is data, adding a region is a manifest + geometry-file
/// change (see the RegionKit `README.md`), not a code change. `RegionAttributor`
/// loads geometry per region from the files this catalog names, so it only ever
/// parses the regions it's asked to attribute.
///
/// The manifest's array order is the catalog's **canonical order**: it fixes
/// attribution first-match priority (regions are mutually exclusive at our
/// resolution) and the day-count ranking tiebreak.
public struct RegionCatalog: Sendable {
    /// One available region plus the metadata the app needs to name and draw it.
    public struct Entry: Sendable, Hashable {
        public let region: Region
        /// English display name (the `localizedName` fallback).
        public let name: String
        /// Bundled string-catalog key, when the region has a translated name.
        public let localizationKey: String?
        /// The region's GeoJSON file under `Resources/regions/`.
        public let geometryFile: String
    }

    /// Every available region's entry, in canonical (manifest) order.
    public let entries: [Entry]
    private let byID: [String: Entry]

    /// The process-wide catalog, decoded from the bundle on first use.
    public static let shared: RegionCatalog = .loadFromBundle()

    init(entries: [Entry]) {
        self.entries = entries
        byID = Dictionary(entries.map { ($0.region.rawValue, $0) }) { first, _ in first }
    }

    /// Every available region in canonical order. Does **not** include the
    /// `.other` sentinel (which has no geometry and is not a catalog entry).
    public var all: [Region] {
        entries.map(\.region)
    }

    /// Whether `id` names a region in the catalog. Backs the failable
    /// `Region(rawValue:)`.
    public func contains(id: String) -> Bool {
        byID[id] != nil
    }

    /// The catalog entry for `region`, or `nil` for `.other` / an unknown id.
    public func entry(for region: Region) -> Entry? {
        byID[region.rawValue]
    }

    /// User-facing name for `region`: the `.other` catch-all string, a
    /// translated `localizationKey`, or the manifest `name`. Falls back to the
    /// raw id for a region the catalog doesn't know (a stored id from a
    /// different catalog version) rather than crashing.
    public func localizedName(for region: Region) -> String {
        if region == .other {
            return String(localized: "region.other", bundle: .module)
        }
        guard let entry = byID[region.rawValue] else {
            return region.rawValue
        }
        if let key = entry.localizationKey {
            return String(localized: String.LocalizationValue(key), bundle: .module)
        }
        return entry.name
    }

    /// The bundled GeoJSON URL for `region`, or `nil` when the region isn't in
    /// the catalog. A missing file (present in the manifest, absent from the
    /// bundle) is surfaced by the caller as a programmer error.
    func geometryURL(for region: Region) -> URL? {
        guard let entry = byID[region.rawValue] else { return nil }
        let stem = (entry.geometryFile as NSString).deletingPathExtension
        // `.process("Resources")` preserves the `regions/` subdirectory, but be
        // resilient to a bundler that flattens it by falling back to a top-level
        // lookup.
        return Bundle.module.url(
            forResource: stem,
            withExtension: "geojson",
            subdirectory: "regions",
        )
            ?? Bundle.module.url(forResource: stem, withExtension: "geojson")
    }
}

extension RegionCatalog {
    private static let logger = RegionLog.channel(.catalog)

    private static func loadFromBundle() -> RegionCatalog {
        guard let url = Bundle.module.url(forResource: "regions", withExtension: "json") else {
            logger.fault("Missing required bundled regions.json manifest")
            assertionFailure("Missing bundled regions.json")
            return RegionCatalog(entries: [])
        }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([ManifestItem].self, from: data)
            let entries = items.map { item in
                Entry(
                    region: Region(unchecked: item.id),
                    name: item.name,
                    localizationKey: item.localizationKey,
                    geometryFile: item.geometry.file,
                )
            }
            logger.info("Loaded region catalog with \(entries.count) region(s)")
            return RegionCatalog(entries: entries)
        } catch {
            logger.fault("Failed to decode bundled regions.json: \(error.localizedDescription)")
            assertionFailure("Failed to decode bundled regions.json: \(error)")
            return RegionCatalog(entries: [])
        }
    }

    /// One manifest entry as decoded from `regions.json`.
    private struct ManifestItem: Decodable {
        let id: String
        let name: String
        let localizationKey: String?
        let geometry: Geometry

        struct Geometry: Decodable {
            let file: String
        }
    }
}
