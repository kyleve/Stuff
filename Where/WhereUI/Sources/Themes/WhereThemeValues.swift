import BroadwayCore
import ViewDocumentCore

/// Named authored values. Components hold typed references rather than styling paths.
public struct WhereThemeValues: Codable, Hashable, Sendable {
    public var colors: [ColorValue]?
    public var fonts: [FontValue]?
    public var surfaces: [SurfaceValue]?

    public init(colors: [ColorValue]?, fonts: [FontValue]?, surfaces: [SurfaceValue]?) {
        self.colors = colors
        self.fonts = fonts
        self.surfaces = surfaces
    }

    public struct ColorValue: Codable, Hashable, Sendable, Identifiable {
        public struct ID: RawRepresentable, Codable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public var id: ID
        public var value: BThemeValue<ViewColorDescriptor>
        public init(id: ID, value: BThemeValue<ViewColorDescriptor>) {
            self.id = id; self.value = value
        }
    }

    public struct FontValue: Codable, Hashable, Sendable, Identifiable {
        public struct ID: RawRepresentable, Codable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public var id: ID
        public var value: BThemeValue<ViewFontDescriptor>
        public init(id: ID, value: BThemeValue<ViewFontDescriptor>) {
            self.id = id; self.value = value
        }
    }

    public struct SurfaceValue: Codable, Hashable, Sendable, Identifiable {
        public struct ID: RawRepresentable, Codable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public var id: ID
        public var value: BThemeValue<Surface>
        public init(id: ID, value: BThemeValue<Surface>) {
            self.id = id; self.value = value
        }
    }

    public enum Surface: Codable, Hashable, Sendable {
        case reflective
        case paper(Paper)
    }

    public struct Paper: Codable, Hashable, Sendable {
        public var fill: ColorValue.ID
        public var tintMix: Double
        public var outline: Outline
        public var shadow: Shadow
        public var pressedTintOpacity: Double

        public init(
            fill: ColorValue.ID,
            tintMix: Double,
            outline: Outline,
            shadow: Shadow,
            pressedTintOpacity: Double,
        ) {
            self.fill = fill; self.tintMix = tintMix; self.outline = outline
            self.shadow = shadow; self.pressedTintOpacity = pressedTintOpacity
        }

        public struct Outline: Codable, Hashable, Sendable {
            public var opacity: Double
            public var width: Double
            public init(opacity: Double, width: Double) {
                self.opacity = opacity; self.width = width
            }
        }

        public struct Shadow: Codable, Hashable, Sendable {
            public var color: ColorValue.ID
            public var radius: Double
            public var offsetY: Double
            public init(color: ColorValue.ID, radius: Double, offsetY: Double) {
                self.color = color; self.radius = radius; self.offsetY = offsetY
            }
        }
    }
}
