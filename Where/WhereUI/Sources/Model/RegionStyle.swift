import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Whimsical, location-themed styling for a `Region`: an SF Symbol, a playful
/// emoji, and an accent color. Pure presentation, so it lives in `WhereUI`
/// alongside the views it decorates.
///
/// Every region gets a stable style: a small set of hand-tuned looks for the
/// regions the app started with, and an id-derived default (a deterministic
/// tint from a palette) for everything else, so any of the 50+ available
/// regions renders sensibly without a bespoke entry.
public struct RegionStyle: Sendable {
    public let symbol: SFSymbol
    public let emoji: String
    public let tint: Color

    public init(symbol: SFSymbol, emoji: String, tint: Color) {
        self.symbol = symbol
        self.emoji = emoji
        self.tint = tint
    }

    /// Build a style from a user-picked ``RegionAppearance`` (token → color).
    public init(_ appearance: RegionAppearance) {
        self.init(
            symbol: appearance.symbolName.sfSymbol,
            emoji: appearance.emoji,
            tint: appearance.color.color,
        )
    }

    /// The look for a region with no user-picked appearance: the region's
    /// default ``RegionAppearance`` (a hand-tuned look for the regions the app
    /// shipped with, an id-derived default for everything else). Sharing
    /// `RegionAppearanceCatalog.defaultAppearance(for:)` keeps the fallback and
    /// the customization pre-fill in lockstep — a picked appearance always wins.
    public static func fallbackStyle(for region: Region) -> RegionStyle {
        RegionStyle(RegionAppearanceCatalog.defaultAppearance(for: region))
    }
}
