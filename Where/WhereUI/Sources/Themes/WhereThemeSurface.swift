import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

/// Selecting matte preserves an inherited matte finish; reflective fallbacks start with neutral
/// paper.
public enum WhereThemeSurface: Codable, Hashable, Sendable {
    case reflective
    case matte(WhereThemeMatteSurface)

    func resolve(
        mode: BMode,
        appearance: ViewDocumentAppearance,
        base: WhereStylesheet.SurfaceTreatment,
    ) throws -> WhereStylesheet.SurfaceTreatment {
        switch self {
            case .reflective: .reflective
            case let .matte(patch):
                switch base {
                    case let .matte(inherited): try .matte(patch.resolve(
                            mode: mode,
                            appearance: appearance,
                            base: inherited,
                        ))
                    case .reflective: try .matte(patch.resolve(
                            mode: mode,
                            appearance: appearance,
                            base: Self.neutralPaper(background: appearance.background),
                        ))
                }
        }
    }

    private static func neutralPaper(background: Color) -> WhereStylesheet.MatteSurface {
        .init(
            fill: .init(base: background, tintMix: 0),
            outline: .init(opacity: 0, width: 0),
            shadow: .init(color: .clear, radius: 0, offsetY: 0),
            pressedTintOpacity: 0,
        )
    }
}

public struct WhereThemeMatteSurface: Codable, Hashable, Sendable {
    public var fill: Fill?
    public var outline: Outline?
    public var shadow: Shadow?
    public var pressedTintOpacity: Double?
    public init() {}
    public init(fill: Fill?, outline: Outline?, shadow: Shadow?, pressedTintOpacity: Double?) {
        self.fill = fill
        self.outline = outline
        self.shadow = shadow
        self
            .pressedTintOpacity = pressedTintOpacity
    }

    public struct Fill: Codable, Hashable, Sendable {
        public var base: BThemeValue<ViewColorDescriptor>?
        public var tintMix: Double?
        public init() {}
        public init(base: BThemeValue<ViewColorDescriptor>?, tintMix: Double?) {
            self.base = base
            self.tintMix = tintMix
        }
    }

    public struct Outline: Codable, Hashable, Sendable {
        public var opacity: Double?
        public var width: Double?
        public init() {}
        public init(opacity: Double?, width: Double?) {
            self.opacity = opacity
            self.width = width
        }
    }

    public struct Shadow: Codable, Hashable, Sendable {
        public var color: BThemeValue<ViewColorDescriptor>?
        public var radius: Double?
        public var offsetY: Double?
        public init() {}
        public init(color: BThemeValue<ViewColorDescriptor>?, radius: Double?, offsetY: Double?) {
            self.color = color
            self.radius = radius
            self.offsetY = offsetY
        }
    }

    func resolve(
        mode: BMode,
        appearance: ViewDocumentAppearance,
        base: WhereStylesheet.MatteSurface,
    ) throws -> WhereStylesheet.MatteSurface {
        var result = base
        if let value = fill?.base?.resolve(mode: mode) {
            try WhereThemeValidation.validate(value, path: "surface.fill.base")
            guard WhereThemeValidation.isOpaque(value) else {
                throw WhereThemeValidationError(
                    path: "surface.fill.base",
                    reason: "Matte paper requires opaque RGBA, primary, or background color",
                )
            }
            result.fill.base = appearance.color(value)
        }
        if let value = fill?.tintMix {
            try WhereThemeValidation.validate(value, path: "surface.fill.tintMix")
            result.fill.tintMix = value
        }
        if let value = outline?.opacity {
            try WhereThemeValidation.validate(value, path: "surface.outline.opacity")
            result.outline.opacity = value
        }
        if let value = outline?.width {
            try WhereThemeValidation.validate(value, path: "surface.outline.width")
            result.outline.width = value
        }
        if let value = shadow?.color?.resolve(mode: mode) {
            try WhereThemeValidation.validate(value, path: "surface.shadow.color")
            result.shadow.color = appearance.color(value)
        }
        if let value = shadow?.radius {
            try WhereThemeValidation.validate(value, path: "surface.shadow.radius")
            result.shadow.radius = value
        }
        if let value = shadow?.offsetY {
            try WhereThemeValidation.validate(value, path: "surface.shadow.offsetY")
            result.shadow.offsetY = value
        }
        if let value = pressedTintOpacity {
            try WhereThemeValidation.validate(value, path: "surface.pressedTintOpacity")
            result.pressedTintOpacity = value
        }
        return result
    }
}
