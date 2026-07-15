import RegionKit
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
    public let symbolName: String
    public let emoji: String
    public let tint: Color

    public init(symbolName: String, emoji: String, tint: Color) {
        self.symbolName = symbolName
        self.emoji = emoji
        self.tint = tint
    }

    public static func style(for region: Region) -> RegionStyle {
        bespokeStyles[region.rawValue] ?? defaultStyle(for: region)
    }

    /// Hand-tuned looks for the regions the app shipped with (and the `.other`
    /// catch-all).
    ///
    /// TODO: Remove when user-chosen per-region styling lands — these bespoke
    /// looks become user data (a picked emoji / symbol / tint). Deleting this
    /// one table cleanly falls back to `defaultStyle(for:)`; nothing else here
    /// hard-codes a region.
    private static let bespokeStyles: [String: RegionStyle] = [
        Region.california.rawValue: RegionStyle(
            symbolName: "sun.max.fill",
            emoji: "🌴",
            tint: .orange,
        ),
        Region.newYork.rawValue: RegionStyle(
            symbolName: "building.2.fill",
            emoji: "🗽",
            tint: .indigo,
        ),
        Region.canada.rawValue: RegionStyle(symbolName: "leaf.fill", emoji: "🍁", tint: .red),
        Region.europeanUnion.rawValue: RegionStyle(
            symbolName: "star.circle.fill",
            emoji: "🇪🇺",
            tint: .blue,
        ),
        Region.other.rawValue: RegionStyle(
            symbolName: "location.magnifyingglass",
            emoji: "🧭",
            tint: .teal,
        ),
    ]

    /// A stable default look for any region without a bespoke entry: a generic
    /// map-pin symbol/emoji and a tint chosen deterministically from the id, so
    /// the same region is always the same color across launches.
    private static func defaultStyle(for region: Region) -> RegionStyle {
        RegionStyle(
            symbolName: "mappin.circle.fill",
            emoji: "📍",
            tint: defaultPalette[paletteIndex(for: region.rawValue)],
        )
    }

    private static let defaultPalette: [Color] = [
        .orange,
        .indigo,
        .red,
        .blue,
        .teal,
        .green,
        .mint,
        .cyan,
        .purple,
        .pink,
        .brown,
    ]

    private static func paletteIndex(for id: String) -> Int {
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sum % defaultPalette.count
    }
}

extension Region {
    /// Convenience accessor so views can write `region.style`.
    public var style: RegionStyle {
        RegionStyle.style(for: self)
    }
}
