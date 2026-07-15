import Foundation

/// A geographic region we track presence in for purposes like state-residency
/// audits. Not US-specific: Canada and the European Union are first-class, and
/// any US state (plus DC / PR) is an available region.
///
/// A `Region` is a thin `Hashable` value wrapping a **stable string id**
/// (`rawValue`, e.g. `"us-CA"`, `"canada"`) — the identifier used by SwiftData,
/// `Codable`, and lookup tables. It is **not** user-facing; use `localizedName`.
/// The set of available regions and each region's metadata (display name,
/// geometry file) live in ``RegionCatalog``, loaded from the bundled
/// `regions.json` manifest, so adding a region is a data change, not a new case.
///
/// `.other` is the catch-all for any coordinate outside every loaded region (or
/// a manual day the user marks as "somewhere else"); it has no geometry and is
/// not a catalog entry.
public struct Region: Hashable, Sendable, RawRepresentable {
    /// The stable data identifier (e.g. `"us-CA"`, `"canada"`). Never shown to
    /// the user — user-facing labels go through `localizedName`.
    public let rawValue: String

    /// Wraps `rawValue` **without** validating it against the catalog. Used to
    /// rehydrate stored/decoded ids (which must round-trip even if the catalog
    /// later changes) and to define the well-known conveniences.
    init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a region only if `rawValue` names a catalog region (or is the
    /// `.other` sentinel), returning `nil` otherwise — matching the former
    /// enum's failable initializer. Use it for untrusted input (an intent
    /// parameter, a Spotlight id); rehydrate values the app itself produced
    /// through the `Codable` path or ``init(unchecked:)`` so a valid stored id
    /// is never dropped.
    public init?(rawValue: String) {
        if rawValue == Region.other.rawValue {
            self = .other
        } else if RegionCatalog.shared.contains(id: rawValue) {
            self.init(unchecked: rawValue)
        } else {
            return nil
        }
    }
}

/// Hand-written `Codable` rather than the compiler-synthesized one: a single
/// `rawValue` field would synthesize a *keyed* container (`{"rawValue":"us-CA"}`),
/// but we want the **bare id string** (`"us-CA"`). That keeps `Set<Region>` /
/// `[Region: Int]` and the persisted `regionRaws: [String]` round-tripping as
/// plain strings — matching what the former `String`-backed enum produced, so
/// stored SwiftData, widget snapshots, and backup archives stay compatible.
extension Region: Codable {
    /// Decodes the bare id string **without** catalog validation, so a stored
    /// region stays honest even if the catalog changes between writes and reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(unchecked: container.decode(String.self))
    }

    /// Encodes as the bare id string (see the type note above).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Region {
    /// User-facing name for this region, resolved through ``RegionCatalog`` (a
    /// `localizationKey` from the bundled string catalog when present, otherwise
    /// the manifest's English `name`).
    public var localizedName: String {
        RegionCatalog.shared.localizedName(for: self)
    }
}

// MARK: - Well-known regions

extension Region {
    /// The catch-all sentinel: any coordinate outside every loaded region. Has
    /// no geometry and is not a catalog entry.
    public static let other = Region(unchecked: "other")

    /// Conveniences for the regions the app has historically tracked, so call
    /// sites read as naturally as the former enum cases (`.california`). Every
    /// other available region is reached through ``RegionCatalog``.
    public static let california = Region(unchecked: "us-CA")
    public static let newYork = Region(unchecked: "us-NY")
    public static let canada = Region(unchecked: "canada")
    public static let europeanUnion = Region(unchecked: "european-union")
}

// MARK: - CaseIterable compatibility

extension Region: CaseIterable {
    /// Every available region in canonical (catalog) order, followed by the
    /// `.other` sentinel. Callers that want only the *available* regions (no
    /// `.other`) use ``RegionCatalog/all`` directly.
    public static var allCases: [Region] {
        RegionCatalog.shared.all + [.other]
    }
}
