import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct PrivacyPassportCardStyle: Codable, Hashable, Sendable {
        public var surface: BThemeValue<WhereThemeSurface>?
        public var headerLayout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var sectionSpacing: BThemeValue<Double>?
        public var headerSpacing: BThemeValue<Double>?
        public var titleFont: BThemeValue<ViewFontDescriptor>?
        public var detailFont: BThemeValue<ViewFontDescriptor>?
        public var rosette: WhereThemeAppearance.PrivacyPassportCardStyle.Rosette?
        public var reflectiveSurface: WhereThemeAppearance.PrivacyPassportCardStyle
            .ReflectiveSurface?
        public var disclosure: WhereThemeAppearance.PrivacyPassportCardStyle.Disclosure?
        public var outlineOpacity: BThemeValue<Double>?
        public var outlineWidth: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.PrivacyPassportCardStyle,
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
            if let authored = headerLayout {
                let resolved = authored.resolve(mode: traits.mode)
                value.headerLayout = resolved.native
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
            if let authored = sectionSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sectionSpacing")
                value.sectionSpacing = CGFloat(resolved)
            }
            if let authored = headerSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".headerSpacing")
                value.headerSpacing = CGFloat(resolved)
            }
            if let authored = titleFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleFont")
                value.titleFont = resolved.font
            }
            if let authored = detailFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".detailFont")
                value.detailFont = resolved.font
            }
            try rosette?.apply(
                to: &value.rosette,
                traits: traits,
                appearance: appearance,
                path: path + ".rosette",
            )
            try reflectiveSurface?.apply(
                to: &value.reflectiveSurface,
                traits: traits,
                appearance: appearance,
                path: path + ".reflectiveSurface",
            )
            try disclosure?.apply(
                to: &value.disclosure,
                traits: traits,
                appearance: appearance,
                path: path + ".disclosure",
            )
            if let authored = outlineOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineOpacity")
                value.outlineOpacity = resolved
            }
            if let authored = outlineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineWidth")
                value.outlineWidth = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.PrivacyPassportCardStyle {
    public struct Disclosure: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var rowSpacing: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var textSpacing: BThemeValue<Double>?
        public var iconSize: BThemeValue<Double>?
        public var symbolFont: BThemeValue<ViewFontDescriptor>?
        public var titleFont: BThemeValue<ViewFontDescriptor>?
        public var detailFont: BThemeValue<ViewFontDescriptor>?
        public var statusFont: BThemeValue<ViewFontDescriptor>?
        public var statusHorizontalPadding: BThemeValue<Double>?
        public var statusVerticalPadding: BThemeValue<Double>?
        public var fillOpacity: BThemeValue<Double>?
        public var strokeOpacity: BThemeValue<Double>?
        public var strokeWidth: BThemeValue<Double>?
        public var statusFillOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.PrivacyPassportCardStyle.Disclosure,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = rowSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowSpacing")
                value.rowSpacing = CGFloat(resolved)
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
            if let authored = textSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".textSpacing")
                value.textSpacing = CGFloat(resolved)
            }
            if let authored = iconSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconSize")
                value.iconSize = CGFloat(resolved)
            }
            if let authored = symbolFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".symbolFont")
                value.symbolFont = resolved.font
            }
            if let authored = titleFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleFont")
                value.titleFont = resolved.font
            }
            if let authored = detailFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".detailFont")
                value.detailFont = resolved.font
            }
            if let authored = statusFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".statusFont")
                value.statusFont = resolved.font
            }
            if let authored = statusHorizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".statusHorizontalPadding")
                value.statusHorizontalPadding = CGFloat(resolved)
            }
            if let authored = statusVerticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".statusVerticalPadding")
                value.statusVerticalPadding = CGFloat(resolved)
            }
            if let authored = fillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fillOpacity")
                value.fillOpacity = resolved
            }
            if let authored = strokeOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".strokeOpacity")
                value.strokeOpacity = resolved
            }
            if let authored = strokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".strokeWidth")
                value.strokeWidth = CGFloat(resolved)
            }
            if let authored = statusFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".statusFillOpacity")
                value.statusFillOpacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.PrivacyPassportCardStyle {
    public struct ReflectiveSurface: Codable, Hashable, Sendable {
        public var backgroundTop: BThemeValue<ViewColorDescriptor>?
        public var backgroundBottom: BThemeValue<ViewColorDescriptor>?
        public var accent: BThemeValue<ViewColorDescriptor>?
        public var intensity: BThemeValue<Double>?
        public var staticGlintIntensity: BThemeValue<Double>?
        public var staticPose: WhereThemeAppearance.PrivacyPassportCardStyle.ReflectiveSurface.Pose?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.PrivacyPassportCardStyle.ReflectiveSurface,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = backgroundTop {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundTop")
                value.backgroundTop = appearance.color(resolved)
            }
            if let authored = backgroundBottom {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundBottom")
                value.backgroundBottom = appearance.color(resolved)
            }
            if let authored = accent {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".accent")
                value.accent = appearance.color(resolved)
            }
            if let authored = intensity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: 0 ... 1,
                    path: path + ".intensity",
                )
                value.intensity = resolved
            }
            if let authored = staticGlintIntensity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: 0 ... 1,
                    path: path + ".staticGlintIntensity",
                )
                value.staticGlintIntensity = resolved
            }
            try staticPose?.apply(
                to: &value.staticPose,
                traits: traits,
                appearance: appearance,
                path: path + ".staticPose",
            )
        }
    }
}

extension WhereThemeAppearance.PrivacyPassportCardStyle {
    public struct Rosette: Codable, Hashable, Sendable {
        public var wobble: BThemeValue<Double>?
        public var lineWidth: BThemeValue<Double>?
        public var primaryRingSpacing: BThemeValue<Double>?
        public var secondaryRingSpacing: BThemeValue<Double>?
        public var primaryOpacity: BThemeValue<Double>?
        public var secondaryOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.PrivacyPassportCardStyle.Rosette,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = wobble {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".wobble")
                value.wobble = CGFloat(resolved)
            }
            if let authored = lineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lineWidth")
                value.lineWidth = CGFloat(resolved)
            }
            if let authored = primaryRingSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".primaryRingSpacing")
                value.primaryRingSpacing = CGFloat(resolved)
            }
            if let authored = secondaryRingSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".secondaryRingSpacing")
                value.secondaryRingSpacing = CGFloat(resolved)
            }
            if let authored = primaryOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".primaryOpacity")
                value.primaryOpacity = resolved
            }
            if let authored = secondaryOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".secondaryOpacity")
                value.secondaryOpacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.PrivacyPassportCardStyle.ReflectiveSurface {
    public struct Pose: Codable, Hashable, Sendable {
        public var roll: BThemeValue<Double>?
        public var pitch: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.PrivacyPassportCardStyle.ReflectiveSurface.Pose,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = roll {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".roll")
                value.roll = resolved
            }
            if let authored = pitch {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".pitch")
                value.pitch = resolved
            }
        }
    }
}
