import RegionKit
import SwiftUI
import WhereCore

/// The predefined option sets the region-customization UI offers — the colors,
/// emoji, and SF Symbols a user picks from — plus the mapping from a stored
/// ``RegionColorToken`` to a concrete SwiftUI `Color`. Presentation data, so it
/// lives in `WhereUI` next to the pickers and `RegionStyle` (which shares the
/// color mapping and default look).
public enum RegionAppearanceCatalog {
    /// Selectable accent colors, in the order the picker lays them out. The full
    /// token set — matching `RegionStyle`'s historical default palette so a
    /// picked color reads the same as an auto-assigned one.
    public static let colors: [RegionColorToken] = RegionColorToken.allCases

    /// Selectable emoji, grouped loosely by theme (places, nature, transit,
    /// weather, symbols) for a scannable grid.
    public static let emojis: [String] = [
        "📍",
        "🏙️",
        "🏖️",
        "🏔️",
        "🏜️",
        "🌆",
        "🌉",
        "🗽",
        "🏛️",
        "🏰",
        "🌴",
        "🌵",
        "🌲",
        "🌾",
        "🍁",
        "🌻",
        "🌊",
        "⛰️",
        "🏝️",
        "🏞️",
        "✈️",
        "🚗",
        "🚂",
        "⛵️",
        "🚀",
        "🧭",
        "🗺️",
        "⭐️",
        "❤️",
        "🔥",
        "☀️",
        "🌙",
        "❄️",
        "🌈",
        "⚡️",
        "🎡",
        "🎢",
        "🎸",
        "🍷",
        "☕️",
    ]

    /// Selectable SF Symbols, all guaranteed-available multicolor-friendly
    /// location/place glyphs.
    public static let symbols: [String] = [
        "mappin.circle.fill",
        "location.fill",
        "map.fill",
        "flag.fill",
        "house.fill",
        "building.2.fill",
        "building.columns.fill",
        "tent.fill",
        "sun.max.fill",
        "moon.stars.fill",
        "cloud.fill",
        "snowflake",
        "leaf.fill",
        "tree.fill",
        "mountain.2.fill",
        "water.waves",
        "airplane",
        "car.fill",
        "tram.fill",
        "sailboat.fill",
        "star.fill",
        "heart.fill",
        "flame.fill",
        "bolt.fill",
        "globe.americas.fill",
        "beach.umbrella.fill",
        "camera.fill",
        "sparkles",
    ]

    /// The default appearance for `region` when the user hasn't picked one — the
    /// starting point the customization step pre-fills, and the fallback
    /// `RegionStyle.fallbackStyle(for:)` renders. A small table of hand-tuned
    /// looks for the regions the app shipped with (and the `.other` catch-all);
    /// an id-derived color + generic map-pin glyph for everything else, so the
    /// same region is always the same color across launches.
    public static func defaultAppearance(for region: Region) -> RegionAppearance {
        bespokeAppearances[region.rawValue]
            ?? RegionAppearance(
                color: defaultColor(for: region.rawValue),
                emoji: "📍",
                symbolName: "mappin.circle.fill",
            )
    }

    private static let bespokeAppearances: [String: RegionAppearance] = [
        Region.california.rawValue:
            RegionAppearance(color: .orange, emoji: "🌴", symbolName: "sun.max.fill"),
        Region.newYork.rawValue:
            RegionAppearance(color: .indigo, emoji: "🗽", symbolName: "building.2.fill"),
        Region.canada.rawValue:
            RegionAppearance(color: .red, emoji: "🍁", symbolName: "leaf.fill"),
        Region.europeanUnion.rawValue:
            RegionAppearance(color: .blue, emoji: "🇪🇺", symbolName: "star.fill"),
        // `.other` keeps its original catch-all look; `location.magnifyingglass`
        // isn't in the pickable `symbols` catalog, but a fallback default isn't
        // constrained to the picker's options.
        Region.other.rawValue:
            RegionAppearance(color: .teal, emoji: "🧭", symbolName: "location.magnifyingglass"),
    ]

    /// A stable accent token derived from the region id, matching the order of
    /// ``colors`` so an auto-assigned color is one the picker can also show.
    private static func defaultColor(for id: String) -> RegionColorToken {
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[sum % colors.count]
    }
}

extension RegionColorToken {
    /// The concrete SwiftUI color for this token. Shared by `RegionStyle` and the
    /// color picker so a swatch and the rendered card always match.
    public var color: Color {
        switch self {
            case .orange: .orange
            case .indigo: .indigo
            case .red: .red
            case .blue: .blue
            case .teal: .teal
            case .green: .green
            case .mint: .mint
            case .cyan: .cyan
            case .purple: .purple
            case .pink: .pink
            case .brown: .brown
        }
    }
}
