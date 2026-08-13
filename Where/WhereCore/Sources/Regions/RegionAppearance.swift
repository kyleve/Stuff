import Foundation

/// A stable, storable identifier for a region's accent color. Persisted (as its
/// `rawValue`) rather than a platform `Color` so the choice survives across
/// processes, backups, and the CloudKit mirror; the presentation layer
/// (`WhereUI.RegionStyle`) maps each token to a concrete SwiftUI color.
///
/// The first cases mirror the historical `RegionStyle` default palette so an
/// unpicked region and a picked-then-matched one render identically. Additional
/// picker colors append to that set so existing raw values stay stable.
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
    case gold
    case lime
    case coral
    case magenta
    case silver
    case slate
    case charcoal
}

/// The user-chosen look for a region: an accent color token, an emoji, and an
/// SF Symbol identifier. Pure data — the concrete symbol and option catalogs live
/// in the presentation layer. Persisted alongside the region's tracked-region
/// row so a customized region keeps its look across devices and reinstalls.
public struct RegionAppearance: Hashable, Sendable, Codable {
    public var color: RegionColorToken
    public var emoji: String
    public var symbolName: RegionSymbol

    public init(color: RegionColorToken, emoji: String, symbolName: RegionSymbol) {
        self.color = color
        self.emoji = emoji
        self.symbolName = symbolName
    }
}
