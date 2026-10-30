import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct LocationWelcomeStyle: Codable, Hashable, Sendable {
        public var surface: BThemeValue<WhereThemeSurface>?
        public var maxWidth: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var paperOpacity: BThemeValue<Double>?
        public var scrimOpacity: BThemeValue<Double>?
        public var glassTintOpacity: BThemeValue<Double>?
        @CopyOnWrite public var glow: WhereThemeAppearance.LocationWelcomeStyle.Shadow? = nil
        @CopyOnWrite public var lift: WhereThemeAppearance.LocationWelcomeStyle.Shadow? = nil
        @CopyOnWrite public var close: WhereThemeAppearance.LocationWelcomeStyle.Close? = nil
        @CopyOnWrite public var accessory: WhereThemeAppearance.LocationWelcomeStyle
            .Accessory? = nil
        @CopyOnWrite public var motion: WhereThemeAppearance.LocationWelcomeStyle.Motion? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationWelcomeStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = surface {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".surface")
                value.surface = try resolved.resolve(
                    mode: traits.mode,
                    appearance: appearance,
                    base: value.surface,
                )
            }
            if let authored = maxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxWidth")
                value.maxWidth = CGFloat(resolved)
            }
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = padding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".padding")
                value.padding = CGFloat(resolved)
            }
            if let authored = contentSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentSpacing")
                value.contentSpacing = CGFloat(resolved)
            }
            if let authored = paperOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".paperOpacity")
                value.paperOpacity = resolved
            }
            if let authored = scrimOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scrimOpacity")
                value.scrimOpacity = resolved
            }
            if let authored = glassTintOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glassTintOpacity")
                value.glassTintOpacity = resolved
            }
            try glow?.apply(
                to: &value.glow,
                traits: traits,
                appearance: appearance,
                path: path + ".glow",
            )
            try lift?.apply(
                to: &value.lift,
                traits: traits,
                appearance: appearance,
                path: path + ".lift",
            )
            try close?.apply(
                to: &value.close,
                traits: traits,
                appearance: appearance,
                path: path + ".close",
            )
            try accessory?.apply(
                to: &value.accessory,
                traits: traits,
                appearance: appearance,
                path: path + ".accessory",
            )
            try motion?.apply(
                to: &value.motion,
                traits: traits,
                appearance: appearance,
                path: path + ".motion",
            )
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle {
    public struct Accessory: Codable, Hashable, Sendable {
        public var copy: BThemeValue<WhereThemeAppearance.LocationWelcomeStyle.Accessory.Copy>?
        public var contentSpacing: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?
        public var minimumActionHeight: BThemeValue<Double>?
        public var symbolSize: BThemeValue<Double>?
        public var titleFont: BThemeValue<ViewFontDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationWelcomeStyle.Accessory,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = copy {
                let resolved = authored.resolve(mode: traits.mode)
                value.copy = resolved.native
            }
            if let authored = contentSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentSpacing")
                value.contentSpacing = CGFloat(resolved)
            }
            if let authored = horizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".horizontalPadding")
                value.horizontalPadding = CGFloat(resolved)
            }
            if let authored = verticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalPadding")
                value.verticalPadding = CGFloat(resolved)
            }
            if let authored = minimumActionHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumActionHeight")
                value.minimumActionHeight = CGFloat(resolved)
            }
            if let authored = symbolSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".symbolSize")
                value.symbolSize = CGFloat(resolved)
            }
            if let authored = titleFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleFont")
                value.titleFont = resolved.font
            }
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle {
    public struct Close: Codable, Hashable, Sendable {
        public var surface: BThemeValue<WhereThemeSurface>?
        public var offset: BThemeValue<WhereThemeSize>?
        public var tintOpacity: BThemeValue<Double>?
        @CopyOnWrite public var glow: WhereThemeAppearance.LocationWelcomeStyle.Shadow? = nil
        @CopyOnWrite public var lift: WhereThemeAppearance.LocationWelcomeStyle.Shadow? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationWelcomeStyle.Close,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = surface {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".surface")
                value.surface = try resolved.resolve(
                    mode: traits.mode,
                    appearance: appearance,
                    base: value.surface,
                )
            }
            if let authored = offset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".offset")
                value.offset = resolved.size
            }
            if let authored = tintOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".tintOpacity")
                value.tintOpacity = resolved
            }
            try glow?.apply(
                to: &value.glow,
                traits: traits,
                appearance: appearance,
                path: path + ".glow",
            )
            try lift?.apply(
                to: &value.lift,
                traits: traits,
                appearance: appearance,
                path: path + ".lift",
            )
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle {
    public struct Motion: Codable, Hashable, Sendable {
        @CopyOnWrite public var arrival: WhereThemeAppearance.LocationWelcomeStyle.Motion
            .Movement? = nil
        @CopyOnWrite public var departure: WhereThemeAppearance.LocationWelcomeStyle.Motion
            .Movement? = nil
        public var scrimAnimation: BThemeValue<WhereThemeAnimation>?
        public var usesSpatialMotion: BThemeValue<Bool>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationWelcomeStyle.Motion,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try arrival?.apply(
                to: &value.arrival,
                traits: traits,
                appearance: appearance,
                path: path + ".arrival",
            )
            try departure?.apply(
                to: &value.departure,
                traits: traits,
                appearance: appearance,
                path: path + ".departure",
            )
            if let authored = scrimAnimation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scrimAnimation")
                value.scrimAnimation = resolved.animation
            }
            if let authored = usesSpatialMotion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".usesSpatialMotion")
                value.usesSpatialMotion = resolved
            }
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle {
    public struct Shadow: Codable, Hashable, Sendable {
        public var opacity: BThemeValue<Double>?
        public var radius: BThemeValue<Double>?
        public var offsetY: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationWelcomeStyle.Shadow,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
            if let authored = radius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".radius")
                value.radius = CGFloat(resolved)
            }
            if let authored = offsetY {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".offsetY")
                value.offsetY = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Accessory {
    public enum Copy: Codable, Hashable, Sendable {
        case full
        case compact
        var native: WhereStylesheet.LocationWelcomeStyle.Accessory.Copy {
            switch self {
                case .full: .full
                case .compact: .compact
            }
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Motion {
    public struct Movement: Codable, Hashable, Sendable {
        public var animation: BThemeValue<WhereThemeAnimation>?
        public var scale: BThemeValue<Double>?
        public var rotationDegrees: BThemeValue<Double>?
        public var verticalOffset: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationWelcomeStyle.Motion.Movement,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = animation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".animation")
                value.animation = resolved.animation
            }
            if let authored = scale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scale")
                value.scale = CGFloat(resolved)
            }
            if let authored = rotationDegrees {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rotationDegrees")
                value.rotationDegrees = resolved
            }
            if let authored = verticalOffset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalOffset")
                value.verticalOffset = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.surface = inheritModePatch(surface, from: parent.surface)
        result.maxWidth = maxWidth ?? parent.maxWidth
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.padding = padding ?? parent.padding
        result.contentSpacing = contentSpacing ?? parent.contentSpacing
        result.paperOpacity = paperOpacity ?? parent.paperOpacity
        result.scrimOpacity = scrimOpacity ?? parent.scrimOpacity
        result.glassTintOpacity = glassTintOpacity ?? parent.glassTintOpacity
        result.glow = inheritPatch(glow, from: parent.glow)
        result.lift = inheritPatch(lift, from: parent.lift)
        result.close = inheritPatch(close, from: parent.close)
        result.accessory = inheritPatch(accessory, from: parent.accessory)
        result.motion = inheritPatch(motion, from: parent.motion)
        return result
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Accessory: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.copy = copy ?? parent.copy
        result.contentSpacing = contentSpacing ?? parent.contentSpacing
        result.horizontalPadding = horizontalPadding ?? parent.horizontalPadding
        result.verticalPadding = verticalPadding ?? parent.verticalPadding
        result.minimumActionHeight = minimumActionHeight ?? parent.minimumActionHeight
        result.symbolSize = symbolSize ?? parent.symbolSize
        result.titleFont = titleFont ?? parent.titleFont
        return result
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Close: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.surface = inheritModePatch(surface, from: parent.surface)
        result.offset = offset ?? parent.offset
        result.tintOpacity = tintOpacity ?? parent.tintOpacity
        result.glow = inheritPatch(glow, from: parent.glow)
        result.lift = inheritPatch(lift, from: parent.lift)
        return result
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Motion: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.arrival = inheritPatch(arrival, from: parent.arrival)
        result.departure = inheritPatch(departure, from: parent.departure)
        result.scrimAnimation = scrimAnimation ?? parent.scrimAnimation
        result.usesSpatialMotion = usesSpatialMotion ?? parent.usesSpatialMotion
        return result
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Shadow: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.opacity = opacity ?? parent.opacity
        result.radius = radius ?? parent.radius
        result.offsetY = offsetY ?? parent.offsetY
        return result
    }
}

extension WhereThemeAppearance.LocationWelcomeStyle.Motion.Movement: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.animation = animation ?? parent.animation
        result.scale = scale ?? parent.scale
        result.rotationDegrees = rotationDegrees ?? parent.rotationDegrees
        result.verticalOffset = verticalOffset ?? parent.verticalOffset
        return result
    }
}
