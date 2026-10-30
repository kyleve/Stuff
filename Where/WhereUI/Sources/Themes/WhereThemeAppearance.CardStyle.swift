import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct CardStyle: Codable, Hashable, Sendable {
        public var surface: BThemeValue<WhereThemeSurface>?
        public var contentTint: BThemeValue<WhereThemeTintAdjustment>?
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var progressBarHeight: BThemeValue<Double>?
        public var entryStamp: WhereThemeAppearance.CardStyle.EntryStamp?
        public var regionNameTypography: WhereThemeAppearance.CardStyle.Typography?
        public var regionNameTracking: BThemeValue<Double>?
        public var heroNumberTypography: WhereThemeAppearance.CardStyle.Typography?
        public var dayUnitTypography: WhereThemeAppearance.CardStyle.Typography?
        public var watermarkFontSize: BThemeValue<Double>?
        public var watermarkOffset: BThemeValue<WhereThemeSize>?
        public var regionShape: WhereThemeOptional<WhereThemeAppearance.CardStyle.RegionShape>?
        public var sheen: WhereThemeAppearance.CardStyle.Sheen?
        public var rosette: WhereThemeAppearance.CardStyle.Rosette?
        public var glow: WhereThemeAppearance.CardStyle.Shadow?
        public var lift: WhereThemeAppearance.CardStyle.Shadow?
        public var paper: WhereThemeOptional<WhereThemeAppearance.CardStyle.Paper>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle,
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
            if let authored = contentTint {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentTint")
                value.contentTint = try resolved.resolve(
                    mode: traits.mode,
                    appearance: appearance,
                    base: value.contentTint,
                )
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
            if let authored = progressBarHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".progressBarHeight")
                value.progressBarHeight = CGFloat(resolved)
            }
            try entryStamp?.apply(
                to: &value.entryStamp,
                traits: traits,
                appearance: appearance,
                path: path + ".entryStamp",
            )
            try regionNameTypography?.apply(
                to: &value.regionNameTypography,
                traits: traits,
                appearance: appearance,
                path: path + ".regionNameTypography",
            )
            if let authored = regionNameTracking {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".regionNameTracking")
                value.regionNameTracking = CGFloat(resolved)
            }
            try heroNumberTypography?.apply(
                to: &value.heroNumberTypography,
                traits: traits,
                appearance: appearance,
                path: path + ".heroNumberTypography",
            )
            try dayUnitTypography?.apply(
                to: &value.dayUnitTypography,
                traits: traits,
                appearance: appearance,
                path: path + ".dayUnitTypography",
            )
            if let authored = watermarkFontSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".watermarkFontSize")
                value.watermarkFontSize = CGFloat(resolved)
            }
            if let authored = watermarkOffset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".watermarkOffset")
                value.watermarkOffset = resolved.size
            }
            if let regionShape {
                switch regionShape {
                    case .clear: value.regionShape = nil
                    case let .value(patch):
                        var component = value.regionShape ?? .standard
                        try patch.apply(
                            to: &component,
                            traits: traits,
                            appearance: appearance,
                            path: path + ".regionShape",
                        )
                        value.regionShape = component
                }
            }
            try sheen?.apply(
                to: &value.sheen,
                traits: traits,
                appearance: appearance,
                path: path + ".sheen",
            )
            try rosette?.apply(
                to: &value.rosette,
                traits: traits,
                appearance: appearance,
                path: path + ".rosette",
            )
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
            if let paper {
                switch paper {
                    case .clear: value.paper = nil
                    case let .value(patch):
                        var component = value.paper ?? .light
                        try patch.apply(
                            to: &component,
                            traits: traits,
                            appearance: appearance,
                            path: path + ".paper",
                        )
                        value.paper = component
                }
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle {
    public struct EntryStamp: Codable, Hashable, Sendable {
        public var size: BThemeValue<Double>?
        public var outerRing: WhereThemeAppearance.CardStyle.EntryStamp.Ring?
        public var innerRing: WhereThemeAppearance.CardStyle.EntryStamp.DashedRing?
        public var content: WhereThemeAppearance.CardStyle.EntryStamp.Content?
        public var arc: WhereThemeOptional<WhereThemeAppearance.CardStyle.EntryStamp.Arc>?
        public var rotationDegrees: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = size {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".size")
                value.size = CGFloat(resolved)
            }
            try outerRing?.apply(
                to: &value.outerRing,
                traits: traits,
                appearance: appearance,
                path: path + ".outerRing",
            )
            try innerRing?.apply(
                to: &value.innerRing,
                traits: traits,
                appearance: appearance,
                path: path + ".innerRing",
            )
            try content?.apply(
                to: &value.content,
                traits: traits,
                appearance: appearance,
                path: path + ".content",
            )
            if let arc {
                switch arc {
                    case .clear: value.arc = nil
                    case let .value(patch):
                        var component = value.arc ?? .init(
                            radiusFraction: 0.37,
                            font: .init(sizeFraction: 0.1, weight: .semibold, design: .serif),
                            opacity: 0.7,
                            maximumSweepDegrees: 250,
                            sweepDegreesPerCharacter: 17,
                        )
                        try patch.apply(
                            to: &component,
                            traits: traits,
                            appearance: appearance,
                            path: path + ".arc",
                        )
                        value.arc = component
                }
            }
            if let authored = rotationDegrees {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rotationDegrees")
                value.rotationDegrees = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle {
    public struct Paper: Codable, Hashable, Sendable {
        public var surface: BThemeValue<WhereThemeMatteSurface>?
        public var contentTint: BThemeValue<WhereThemeTintAdjustment>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.Paper,
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
            if let authored = contentTint {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentTint")
                value.contentTint = try resolved.resolve(
                    mode: traits.mode,
                    appearance: appearance,
                    base: value.contentTint,
                )
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle {
    public struct RegionShape: Codable, Hashable, Sendable {
        public var watermark: WhereThemeAppearance.CardStyle.RegionShape.Artwork?
        public var stamp: WhereThemeAppearance.CardStyle.RegionShape.Artwork?
        public var securityBorder: WhereThemeAppearance.CardStyle.RegionShape.SecurityBorder?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.RegionShape,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try watermark?.apply(
                to: &value.watermark,
                traits: traits,
                appearance: appearance,
                path: path + ".watermark",
            )
            try stamp?.apply(
                to: &value.stamp,
                traits: traits,
                appearance: appearance,
                path: path + ".stamp",
            )
            try securityBorder?.apply(
                to: &value.securityBorder,
                traits: traits,
                appearance: appearance,
                path: path + ".securityBorder",
            )
        }
    }
}

extension WhereThemeAppearance.CardStyle {
    public struct Rosette: Codable, Hashable, Sendable {
        public var wobble: BThemeValue<Double>?
        public var lineWidth: BThemeValue<Double>?
        public var primaryRingSpacing: BThemeValue<Double>?
        public var secondaryRingSpacing: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.Rosette,
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

extension WhereThemeAppearance.CardStyle {
    public struct Shadow: Codable, Hashable, Sendable {
        public var opacity: BThemeValue<Double>?
        public var radius: BThemeValue<Double>?
        public var offsetY: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.Shadow,
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

extension WhereThemeAppearance.CardStyle {
    public struct Sheen: Codable, Hashable, Sendable {
        public var intensity: BThemeValue<Double>?
        public var staticGlintIntensity: BThemeValue<Double>?
        public var staticPose: WhereThemeAppearance.CardStyle.Sheen.Pose?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.Sheen,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
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

extension WhereThemeAppearance.CardStyle {
    public struct Typography: Codable, Hashable, Sendable {
        public var size: BThemeValue<WhereThemeAppearance.CardStyle.Typography.Size>?
        public var weight: BThemeValue<WhereThemeAppearance.CardStyle.Typography.Weight>?
        public var design: BThemeValue<WhereThemeAppearance.CardStyle.Typography.Design>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.Typography,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = size {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".size")
                value.size = resolved.native
            }
            if let authored = weight {
                let resolved = authored.resolve(mode: traits.mode)
                value.weight = resolved.native
            }
            if let authored = design {
                let resolved = authored.resolve(mode: traits.mode)
                value.design = resolved.native
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.EntryStamp {
    public struct Arc: Codable, Hashable, Sendable {
        public var radiusFraction: BThemeValue<Double>?
        public var font: WhereThemeAppearance.CardStyle.EntryStamp.Typography?
        public var opacity: BThemeValue<Double>?
        public var maximumSweepDegrees: BThemeValue<Double>?
        public var sweepDegreesPerCharacter: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp.Arc,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = radiusFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".radiusFraction")
                value.radiusFraction = CGFloat(resolved)
            }
            try font?.apply(
                to: &value.font,
                traits: traits,
                appearance: appearance,
                path: path + ".font",
            )
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
            if let authored = maximumSweepDegrees {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maximumSweepDegrees")
                value.maximumSweepDegrees = resolved
            }
            if let authored = sweepDegreesPerCharacter {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".sweepDegreesPerCharacter",
                )
                value.sweepDegreesPerCharacter = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.EntryStamp {
    public struct Content: Codable, Hashable, Sendable {
        public var spacingFraction: BThemeValue<Double>?
        public var artworkExtent: BThemeValue<WhereThemeSize>?
        public var symbolFont: WhereThemeAppearance.CardStyle.EntryStamp.Typography?
        public var yearFont: WhereThemeAppearance.CardStyle.EntryStamp.Typography?
        public var opacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp.Content,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = spacingFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacingFraction")
                value.spacingFraction = CGFloat(resolved)
            }
            if let authored = artworkExtent {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".artworkExtent")
                value.artworkExtent = resolved.size
            }
            try symbolFont?.apply(
                to: &value.symbolFont,
                traits: traits,
                appearance: appearance,
                path: path + ".symbolFont",
            )
            try yearFont?.apply(
                to: &value.yearFont,
                traits: traits,
                appearance: appearance,
                path: path + ".yearFont",
            )
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.EntryStamp {
    public struct DashedRing: Codable, Hashable, Sendable {
        public var opacity: BThemeValue<Double>?
        public var lineWidthFraction: BThemeValue<Double>?
        public var dash: WhereThemeAppearance.CardStyle.EntryStamp.DashedRing.Dash?
        public var insetFraction: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp.DashedRing,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
            if let authored = lineWidthFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lineWidthFraction")
                value.lineWidthFraction = CGFloat(resolved)
            }
            try dash?.apply(
                to: &value.dash,
                traits: traits,
                appearance: appearance,
                path: path + ".dash",
            )
            if let authored = insetFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".insetFraction")
                value.insetFraction = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.EntryStamp {
    public struct Ring: Codable, Hashable, Sendable {
        public var opacity: BThemeValue<Double>?
        public var lineWidthFraction: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp.Ring,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
            if let authored = lineWidthFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lineWidthFraction")
                value.lineWidthFraction = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.EntryStamp {
    public struct Typography: Codable, Hashable, Sendable {
        public var sizeFraction: BThemeValue<Double>?
        public var weight: BThemeValue<ViewFontDescriptor.Weight>?
        public var design: BThemeValue<ViewFontDescriptor.Design>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp.Typography,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = sizeFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sizeFraction")
                value.sizeFraction = CGFloat(resolved)
            }
            if let authored = weight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".weight")
                value.weight = resolved.fontWeight
            }
            if let authored = design {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".design")
                value.design = resolved.fontDesign
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.RegionShape {
    public struct Artwork: Codable, Hashable, Sendable {
        public var center: BThemeValue<WhereThemePoint>?
        public var extent: BThemeValue<WhereThemeSize>?
        public var scale: BThemeValue<Double>?
        public var fillOpacity: BThemeValue<Double>?
        public var stroke: WhereThemeOptional<WhereThemeAppearance.CardStyle.RegionShape.Artwork
            .Stroke>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.RegionShape.Artwork,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = center {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".center")
                value.center = resolved.point
            }
            if let authored = extent {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".extent")
                value.extent = resolved.size
            }
            if let authored = scale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scale")
                value.scale = CGFloat(resolved)
            }
            if let authored = fillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fillOpacity")
                value.fillOpacity = resolved
            }
            if let stroke {
                switch stroke {
                    case .clear: value.stroke = nil
                    case let .value(patch):
                        var component = value.stroke ?? .init(opacity: 0.28, width: 1.5)
                        try patch.apply(
                            to: &component,
                            traits: traits,
                            appearance: appearance,
                            path: path + ".stroke",
                        )
                        value.stroke = component
                }
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.RegionShape {
    public struct SecurityBorder: Codable, Hashable, Sendable {
        public var inset: BThemeValue<Double>?
        public var glyphSize: BThemeValue<Double>?
        public var spacing: BThemeValue<Double>?
        public var opacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.RegionShape.SecurityBorder,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = inset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".inset")
                value.inset = CGFloat(resolved)
            }
            if let authored = glyphSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glyphSize")
                value.glyphSize = CGFloat(resolved)
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.Sheen {
    public struct Pose: Codable, Hashable, Sendable {
        public var roll: BThemeValue<Double>?
        public var pitch: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.Sheen.Pose,
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

extension WhereThemeAppearance.CardStyle.Typography {
    public enum Design: Codable, Hashable, Sendable {
        case `default`
        case serif
        case rounded
        case monospaced
        var native: WhereStylesheet.CardStyle.Typography.Design {
            switch self {
                case .default: .default
                case .serif: .serif
                case .rounded: .rounded
                case .monospaced: .monospaced
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.Typography {
    public enum Size: Codable, Hashable, Sendable {
        case fixed(Double)
        case semantic(ViewFontDescriptor.TextStyle)
        var native: WhereStylesheet.CardStyle.Typography.Size {
            switch self {
                case let .fixed(points): .fixed(CGFloat(points))
                case let .semantic(style):
                    switch style {
                        case .largeTitle: .semantic(.largeTitle)
                        case .title: .semantic(.title)
                        case .title2: .semantic(.title2)
                        case .title3: .semantic(.title3)
                        case .headline: .semantic(.headline)
                        case .subheadline: .semantic(.subheadline)
                        case .body: .semantic(.body)
                        case .callout: .semantic(.callout)
                        case .footnote: .semantic(.footnote)
                        case .caption: .semantic(.caption)
                        case .caption2: .semantic(.caption2)
                    }
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.Typography {
    public enum Weight: Codable, Hashable, Sendable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black
        var native: WhereStylesheet.CardStyle.Typography.Weight {
            switch self {
                case .ultraLight: .ultraLight
                case .thin: .thin
                case .light: .light
                case .regular: .regular
                case .medium: .medium
                case .semibold: .semibold
                case .bold: .bold
                case .heavy: .heavy
                case .black: .black
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.EntryStamp.DashedRing {
    public struct Dash: Codable, Hashable, Sendable {
        public var lengthFraction: BThemeValue<Double>?
        public var spacingFraction: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.EntryStamp.DashedRing.Dash,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = lengthFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lengthFraction")
                value.lengthFraction = CGFloat(resolved)
            }
            if let authored = spacingFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacingFraction")
                value.spacingFraction = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.CardStyle.RegionShape.Artwork {
    public struct Stroke: Codable, Hashable, Sendable {
        public var opacity: BThemeValue<Double>?
        public var width: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CardStyle.RegionShape.Artwork.Stroke,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
            if let authored = width {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".width")
                value.width = CGFloat(resolved)
            }
        }
    }
}
