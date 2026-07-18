import Foundation

/// A stable, storable identifier for a region's accent color. Persisted (as its
/// `rawValue`) rather than a platform `Color` so the choice survives across
/// processes, backups, and the CloudKit mirror; the presentation layer
/// (`WhereUI.RegionStyle`) maps each token to a concrete SwiftUI color.
///
/// The cases mirror the historical `RegionStyle` default palette so an
/// unpicked region and a picked-then-matched one render identically.
public enum RegionColorToken: String, CaseIterable, Sendable, Codable, Hashable {
    case orange
    case indigo
    case red
    case blue
    case teal
    case green
    case mint
    case cyan
    case purple
    case pink
    case brown
}

/// The user-chosen look for a region: an accent color token, an emoji, and an
/// SF Symbol name. Pure data — the concrete color and any option catalogs live
/// in the presentation layer. Persisted alongside the region's tracked-region
/// row so a customized region keeps its look across devices and reinstalls.
public struct RegionAppearance: Hashable, Sendable, Codable {
    public var color: RegionColorToken
    public var emoji: String
    public var symbolName: String

    public init(color: RegionColorToken, emoji: String, symbolName: String) {
        self.color = color
        self.emoji = emoji
        self.symbolName = symbolName
    }
}
