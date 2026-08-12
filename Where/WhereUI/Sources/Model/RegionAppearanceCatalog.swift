import RegionKit
import SwiftUI
import WhereCore

/// The predefined option sets the region-customization UI offers — the colors,
/// emoji, and SF Symbols a user picks from — plus the mapping from a stored
/// ``RegionColorToken`` to a concrete SwiftUI `Color`. Presentation data, so it
/// lives in `WhereUI` next to the pickers and `RegionStyle` (which shares the
/// color mapping and default look).
public enum RegionAppearanceCatalog {
    /// Selectable accent colors, in the order the picker lays them out. Every
    /// persisted token is pickable; additions append so familiar choices keep
    /// their positions.
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
    public static let symbols: [RegionSymbol] = [
        .mappinCircleFill,
        .locationFill,
        .mapFill,
        .flagFill,
        .houseFill,
        .building2Fill,
        .buildingColumnsFill,
        .tentFill,
        .sunMaxFill,
        .moonStarsFill,
        .cloudFill,
        .snowflake,
        .leafFill,
        .treeFill,
        .mountain2Fill,
        .waterWaves,
        .airplane,
        .carFill,
        .tramFill,
        .sailboatFill,
        .starFill,
        .heartFill,
        .flameFill,
        .boltFill,
        .globeAmericasFill,
        .beachUmbrellaFill,
        .cameraFill,
        .sparkles,
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
                symbolName: .mappinCircleFill,
            )
    }

    private static let bespokeAppearances: [String: RegionAppearance] = [
        Region.california.rawValue:
            RegionAppearance(color: .orange, emoji: "🌴", symbolName: .sunMaxFill),
        Region.newYork.rawValue:
            RegionAppearance(color: .indigo, emoji: "🗽", symbolName: .building2Fill),
        Region.canada.rawValue:
            RegionAppearance(color: .red, emoji: "🍁", symbolName: .leafFill),
        Region.europeanUnion.rawValue:
            RegionAppearance(color: .blue, emoji: "🇪🇺", symbolName: .starFill),
        // `.other` keeps its original catch-all look; `location.magnifyingglass`
        // isn't in the pickable `symbols` catalog, but a fallback default isn't
        // constrained to the picker's options.
        Region.other.rawValue:
            RegionAppearance(color: .teal, emoji: "🧭", symbolName: .locationMagnifyingglass),
    ]

    /// An accent token derived from the region id across every selectable color.
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
            case .gold: Color(red: 0.65, green: 0.43, blue: 0)
            case .lime: Color(red: 0.40, green: 0.62, blue: 0.08)
            case .coral: Color(red: 0.88, green: 0.26, blue: 0.22)
            case .magenta: Color(red: 0.72, green: 0.12, blue: 0.52)
            case .silver: Color(red: 0.55, green: 0.55, blue: 0.55)
            case .slate: Color(red: 0.45, green: 0.45, blue: 0.45)
            case .charcoal: Color(red: 0.35, green: 0.35, blue: 0.35)
        }
    }

    /// Selection glyph color chosen for contrast against each swatch.
    var selectionForeground: Color {
        switch self {
            case .gold, .lime, .silver: .black
            case .orange, .indigo, .red, .blue, .teal, .green, .mint, .cyan,
                 .purple, .pink, .brown, .coral, .magenta, .slate, .charcoal: .white
        }
    }
}
