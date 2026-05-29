import SwiftUI
import WhereCore

/// Whimsical, location-themed styling for a `Region`: an SF Symbol, a playful
/// emoji, and an accent color. Pure presentation, so it lives in `WhereUI`
/// alongside the views it decorates.
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
        switch region {
            case .california:
                RegionStyle(symbolName: "sun.max.fill", emoji: "🌴", tint: .orange)
            case .newYork:
                RegionStyle(symbolName: "building.2.fill", emoji: "🗽", tint: .indigo)
            case .canada:
                RegionStyle(symbolName: "leaf.fill", emoji: "🍁", tint: .red)
            case .europeanUnion:
                RegionStyle(symbolName: "star.circle.fill", emoji: "🇪🇺", tint: .blue)
            case .other:
                RegionStyle(symbolName: "location.magnifyingglass", emoji: "🧭", tint: .teal)
        }
    }
}

extension Region {
    /// Convenience accessor so views can write `region.style`.
    public var style: RegionStyle {
        RegionStyle.style(for: self)
    }
}
