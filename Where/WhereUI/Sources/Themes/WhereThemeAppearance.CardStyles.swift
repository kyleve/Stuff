import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct CardStyles: Codable, Hashable, Sendable {
        public var regular: WhereThemeAppearance.CardStyle?
        public var compact: WhereThemeAppearance.CardStyle?
        public var elsewherePaper: WhereThemeAppearance.CardStyle.Paper?
        public var watermarkOpacity: BThemeValue<Double>?
        public var glassTintOpacity: BThemeValue<Double>?
        public var nameOpacity: BThemeValue<Double>?
        public var estimatedProgressOpacity: BThemeValue<Double>?
        public var estimateSticker: WhereThemeAppearance.CardStyles.EstimateSticker?
        public var rosetteFill: WhereThemeAppearance.CardStyles.RosetteFill?
        public var securityPrint: WhereThemeAppearance.CardStyles.SecurityPrint?
        public var dayCount: WhereThemeAppearance.CardStyles.DayCountStyle?
        public var constellation: WhereThemeAppearance.CardStyles.Constellation?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyles,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try regular?.apply(
                to: &value.regular,
                traits: traits,
                appearance: appearance,
                path: path + ".regular",
            )
            try compact?.apply(
                to: &value.compact,
                traits: traits,
                appearance: appearance,
                path: path + ".compact",
            )
            try elsewherePaper?.apply(
                to: &value.elsewherePaper,
                traits: traits,
                appearance: appearance,
                path: path + ".elsewherePaper",
            )
            if let authored = watermarkOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".watermarkOpacity")
                value.watermarkOpacity = resolved
            }
            if let authored = glassTintOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glassTintOpacity")
                value.glassTintOpacity = resolved
            }
            if let authored = nameOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".nameOpacity")
                value.nameOpacity = resolved
            }
            if let authored = estimatedProgressOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".estimatedProgressOpacity",
                )
                value.estimatedProgressOpacity = resolved
            }
            try estimateSticker?.apply(
                to: &value.estimateSticker,
                traits: traits,
                appearance: appearance,
                path: path + ".estimateSticker",
            )
            try rosetteFill?.apply(
                to: &value.rosetteFill,
                traits: traits,
                appearance: appearance,
                path: path + ".rosetteFill",
            )
            try securityPrint?.apply(
                to: &value.securityPrint,
                traits: traits,
                appearance: appearance,
                path: path + ".securityPrint",
            )
            try dayCount?.apply(
                to: &value.dayCount,
                traits: traits,
                appearance: appearance,
                path: path + ".dayCount",
            )
            try constellation?.apply(
                to: &value.constellation,
                traits: traits,
                appearance: appearance,
                path: path + ".constellation",
            )
        }
    }
}

extension WhereThemeAppearance.CardStyles {
    public struct Constellation: Codable, Hashable, Sendable {
        public var coreDiameter: BThemeValue<Double>?
        public var coreOpacity: BThemeValue<Double>?
        public var coreWhiteMix: BThemeValue<Double>?
        public var haloRadius: BThemeValue<Double>?
        public var haloOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyles.Constellation,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = coreDiameter {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".coreDiameter")
                value.coreDiameter = CGFloat(resolved)
            }
            if let authored = coreOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".coreOpacity")
                value.coreOpacity = resolved
            }
            if let authored = coreWhiteMix {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".coreWhiteMix")
                value.coreWhiteMix = resolved
            }
            if let authored = haloRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".haloRadius")
                value.haloRadius = CGFloat(resolved)
            }
            if let authored = haloOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".haloOpacity")
                value.haloOpacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CardStyles {
    public struct DayCountStyle: Codable, Hashable, Sendable {
        public var morph: BThemeValue<WhereThemeAppearance.CardStyles.DayCountStyle.Morph>?
        public var animation: BThemeValue<WhereThemeAnimation>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyles.DayCountStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = morph {
                let resolved = authored.resolve(mode: traits.mode)
                value.morph = resolved.native
            }
            if let authored = animation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".animation")
                value.animation = resolved.animation
            }
        }
    }
}

extension WhereThemeAppearance.CardStyles {
    public struct EstimateSticker: Codable, Hashable, Sendable {
        public var labelTypography: WhereThemeAppearance.CardStyle.Typography?
        public var valueTypography: WhereThemeAppearance.CardStyle.Typography?
        public var contentOpacity: BThemeValue<Double>?
        public var scale: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?
        public var rotationDegrees: BThemeValue<Double>?
        public var fillOpacity: BThemeValue<Double>?
        public var outlineOpacity: BThemeValue<Double>?
        public var outlineWidth: BThemeValue<Double>?
        public var innerInset: BThemeValue<Double>?
        public var innerOutlineWidth: BThemeValue<Double>?
        public var innerDash: BThemeValue<[Double]>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyles.EstimateSticker,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try labelTypography?.apply(
                to: &value.labelTypography,
                traits: traits,
                appearance: appearance,
                path: path + ".labelTypography",
            )
            try valueTypography?.apply(
                to: &value.valueTypography,
                traits: traits,
                appearance: appearance,
                path: path + ".valueTypography",
            )
            if let authored = contentOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentOpacity")
                value.contentOpacity = resolved
            }
            if let authored = scale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scale")
                value.scale = CGFloat(resolved)
            }
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
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
            if let authored = rotationDegrees {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rotationDegrees")
                value.rotationDegrees = resolved
            }
            if let authored = fillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fillOpacity")
                value.fillOpacity = resolved
            }
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
            if let authored = innerInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".innerInset")
                value.innerInset = CGFloat(resolved)
            }
            if let authored = innerOutlineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".innerOutlineWidth")
                value.innerOutlineWidth = CGFloat(resolved)
            }
            if let authored = innerDash {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".innerDash")
                value.innerDash = resolved.map { CGFloat($0) }
            }
        }
    }
}

extension WhereThemeAppearance.CardStyles {
    public struct RosetteFill: Codable, Hashable, Sendable {
        public var primary: BThemeValue<Double>?
        public var secondary: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyles.RosetteFill,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = primary {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".primary")
                value.primary = resolved
            }
            if let authored = secondary {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".secondary")
                value.secondary = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CardStyles {
    public struct SecurityPrint: Codable, Hashable, Sendable {
        public var whiteMix: BThemeValue<Double>?
        public var backgroundBlendMode: BThemeValue<WhereThemeBlend>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyles.SecurityPrint,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = whiteMix {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".whiteMix")
                value.whiteMix = resolved
            }
            if let authored = backgroundBlendMode {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundBlendMode")
                value.backgroundBlendMode = resolved.blendMode
            }
        }
    }
}

extension WhereThemeAppearance.CardStyles.DayCountStyle {
    public enum Morph: Codable, Hashable, Sendable {
        case rollingDigits
        case crossFade
        var native: WhereStylesheet.CardStyles.DayCountStyle.Morph {
            switch self {
                case .rollingDigits: .rollingDigits
                case .crossFade: .crossFade
            }
        }
    }
}
