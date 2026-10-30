import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct StampBannerStyle: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var tint: BThemeValue<ViewColorDescriptor>?
        public var padding: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var titleFont: BThemeValue<ViewFontDescriptor>?
        public var detailFont: BThemeValue<ViewFontDescriptor>?
        public var outlineWidth: BThemeValue<Double>?
        public var rosette: WhereThemeAppearance.StampBannerStyle.Rosette?
        public var ink: WhereThemeAppearance.StampBannerStyle.Ink?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.StampBannerStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = tint {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".tint")
                value.tint = appearance.color(resolved)
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
            if let authored = outlineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineWidth")
                value.outlineWidth = CGFloat(resolved)
            }
            try rosette?.apply(
                to: &value.rosette,
                traits: traits,
                appearance: appearance,
                path: path + ".rosette",
            )
            try ink?.apply(
                to: &value.ink,
                traits: traits,
                appearance: appearance,
                path: path + ".ink",
            )
        }
    }
}

extension WhereThemeAppearance.StampBannerStyle {
    public struct Ink: Codable, Hashable, Sendable {
        public var outlineOpacity: BThemeValue<Double>?
        public var primaryRosetteOpacity: BThemeValue<Double>?
        public var secondaryRosetteOpacity: BThemeValue<Double>?
        public var sealOpacity: BThemeValue<Double>?
        public var titleOpacity: BThemeValue<Double>?
        public var detailOpacity: BThemeValue<Double>?
        public var accessoryOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.StampBannerStyle.Ink,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = outlineOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineOpacity")
                value.outlineOpacity = resolved
            }
            if let authored = primaryRosetteOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".primaryRosetteOpacity")
                value.primaryRosetteOpacity = resolved
            }
            if let authored = secondaryRosetteOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".secondaryRosetteOpacity")
                value.secondaryRosetteOpacity = resolved
            }
            if let authored = sealOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sealOpacity")
                value.sealOpacity = resolved
            }
            if let authored = titleOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleOpacity")
                value.titleOpacity = resolved
            }
            if let authored = detailOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".detailOpacity")
                value.detailOpacity = resolved
            }
            if let authored = accessoryOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".accessoryOpacity")
                value.accessoryOpacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.StampBannerStyle {
    public struct Rosette: Codable, Hashable, Sendable {
        public var wobble: BThemeValue<Double>?
        public var lineWidth: BThemeValue<Double>?
        public var primaryRingSpacing: BThemeValue<Double>?
        public var secondaryRingSpacing: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.StampBannerStyle.Rosette,
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
        }
    }
}
