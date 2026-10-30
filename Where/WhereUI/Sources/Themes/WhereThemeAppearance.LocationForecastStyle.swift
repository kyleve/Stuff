import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct LocationForecastStyle: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var rowSpacing: BThemeValue<Double>?
        public var expansionAnimation: BThemeValue<WhereThemeAnimation>?
        public var surface: WhereThemeAppearance.LocationForecastStyle.Surface?
        public var header: WhereThemeAppearance.LocationForecastStyle.Header?
        public var row: WhereThemeAppearance.LocationForecastStyle.Row?
        public var progress: WhereThemeAppearance.LocationForecastStyle.Progress?
        public var controls: WhereThemeAppearance.LocationForecastStyle.Controls?
        public var ink: WhereThemeAppearance.LocationForecastStyle.Ink?
        public var summary: WhereThemeAppearance.LocationForecastStyle.Summary?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
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
            if let authored = rowSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowSpacing")
                value.rowSpacing = CGFloat(resolved)
            }
            if let authored = expansionAnimation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".expansionAnimation")
                value.expansionAnimation = resolved.animation
            }
            try surface?.apply(
                to: &value.surface,
                traits: traits,
                appearance: appearance,
                path: path + ".surface",
            )
            try header?.apply(
                to: &value.header,
                traits: traits,
                appearance: appearance,
                path: path + ".header",
            )
            try row?.apply(
                to: &value.row,
                traits: traits,
                appearance: appearance,
                path: path + ".row",
            )
            try progress?.apply(
                to: &value.progress,
                traits: traits,
                appearance: appearance,
                path: path + ".progress",
            )
            try controls?.apply(
                to: &value.controls,
                traits: traits,
                appearance: appearance,
                path: path + ".controls",
            )
            try ink?.apply(
                to: &value.ink,
                traits: traits,
                appearance: appearance,
                path: path + ".ink",
            )
            try summary?.apply(
                to: &value.summary,
                traits: traits,
                appearance: appearance,
                path: path + ".summary",
            )
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Controls: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var sectionSpacing: BThemeValue<Double>?
        public var layoutSpacing: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var minimumHeight: BThemeValue<Double>?
        public var strokeWidth: BThemeValue<Double>?
        public var font: BThemeValue<ViewFontDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Controls,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = sectionSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sectionSpacing")
                value.sectionSpacing = CGFloat(resolved)
            }
            if let authored = layoutSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".layoutSpacing")
                value.layoutSpacing = CGFloat(resolved)
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
            if let authored = minimumHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumHeight")
                value.minimumHeight = CGFloat(resolved)
            }
            if let authored = strokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".strokeWidth")
                value.strokeWidth = CGFloat(resolved)
            }
            if let authored = font {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".font")
                value.font = resolved.font
            }
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Header: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var contentSpacing: BThemeValue<Double>?
        public var textSpacing: BThemeValue<Double>?
        public var titleFont: BThemeValue<ViewFontDescriptor>?
        public var elapsedFont: BThemeValue<ViewFontDescriptor>?
        public var minimumHeight: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Header,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
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
            if let authored = titleFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleFont")
                value.titleFont = resolved.font
            }
            if let authored = elapsedFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".elapsedFont")
                value.elapsedFont = resolved.font
            }
            if let authored = minimumHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumHeight")
                value.minimumHeight = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Ink: Codable, Hashable, Sendable {
        public var surfaceWashOpacity: BThemeValue<Double>?
        public var surfaceOutlineOpacity: BThemeValue<Double>?
        public var microprintOpacity: BThemeValue<Double>?
        public var rosettePrimaryOpacity: BThemeValue<Double>?
        public var rosetteSecondaryOpacity: BThemeValue<Double>?
        public var sealOpacity: BThemeValue<Double>?
        public var rowFillOpacity: BThemeValue<Double>?
        public var rowOutlineOpacity: BThemeValue<Double>?
        public var progressTrackOpacity: BThemeValue<Double>?
        public var progressEstimateFillOpacity: BThemeValue<Double>?
        public var progressHatchOpacity: BThemeValue<Double>?
        public var controlFillOpacity: BThemeValue<Double>?
        public var controlStrokeOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Ink,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = surfaceWashOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".surfaceWashOpacity")
                value.surfaceWashOpacity = resolved
            }
            if let authored = surfaceOutlineOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".surfaceOutlineOpacity")
                value.surfaceOutlineOpacity = resolved
            }
            if let authored = microprintOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".microprintOpacity")
                value.microprintOpacity = resolved
            }
            if let authored = rosettePrimaryOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rosettePrimaryOpacity")
                value.rosettePrimaryOpacity = resolved
            }
            if let authored = rosetteSecondaryOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rosetteSecondaryOpacity")
                value.rosetteSecondaryOpacity = resolved
            }
            if let authored = sealOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sealOpacity")
                value.sealOpacity = resolved
            }
            if let authored = rowFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowFillOpacity")
                value.rowFillOpacity = resolved
            }
            if let authored = rowOutlineOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowOutlineOpacity")
                value.rowOutlineOpacity = resolved
            }
            if let authored = progressTrackOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".progressTrackOpacity")
                value.progressTrackOpacity = resolved
            }
            if let authored = progressEstimateFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".progressEstimateFillOpacity",
                )
                value.progressEstimateFillOpacity = resolved
            }
            if let authored = progressHatchOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".progressHatchOpacity")
                value.progressHatchOpacity = resolved
            }
            if let authored = controlFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".controlFillOpacity")
                value.controlFillOpacity = resolved
            }
            if let authored = controlStrokeOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".controlStrokeOpacity")
                value.controlStrokeOpacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Progress: Codable, Hashable, Sendable {
        public var height: BThemeValue<Double>?
        public var hatchSpacing: BThemeValue<Double>?
        public var hatchLineWidth: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Progress,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = height {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".height")
                value.height = CGFloat(resolved)
            }
            if let authored = hatchSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".hatchSpacing")
                value.hatchSpacing = CGFloat(resolved)
            }
            if let authored = hatchLineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".hatchLineWidth")
                value.hatchLineWidth = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Row: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var estimateSpacing: BThemeValue<Double>?
        public var regionFont: BThemeValue<ViewFontDescriptor>?
        public var estimateFont: BThemeValue<ViewFontDescriptor>?
        public var detailFont: BThemeValue<ViewFontDescriptor>?
        public var outlineWidth: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Row,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
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
            if let authored = estimateSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".estimateSpacing")
                value.estimateSpacing = CGFloat(resolved)
            }
            if let authored = regionFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".regionFont")
                value.regionFont = resolved.font
            }
            if let authored = estimateFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".estimateFont")
                value.estimateFont = resolved.font
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
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Summary: Codable, Hashable, Sendable {
        public var artwork: WhereThemeAppearance.LocationForecastStyle.Summary.Artwork?
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var ink: BThemeValue<ViewColorDescriptor>?
        public var treatment: BThemeValue<WhereThemeSurface>?
        public var paper: BThemeValue<ViewColorDescriptor>?
        public var usesOpaquePaper: BThemeValue<Bool>?
        public var glassTintOpacity: BThemeValue<Double>?
        public var outlineColor: BThemeValue<ViewColorDescriptor>?
        public var outlineWidth: BThemeValue<Double>?
        public var shadowOpacity: BThemeValue<Double>?
        public var shadowRadius: BThemeValue<Double>?
        public var shadowOffsetY: BThemeValue<Double>?
        public var rosetteOpacity: BThemeValue<Double>?
        public var rosette: WhereThemeAppearance.CardStyle.Rosette?
        public var border: WhereThemeAppearance.CardStyle.RegionShape.SecurityBorder?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Summary,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try artwork?.apply(
                to: &value.artwork,
                traits: traits,
                appearance: appearance,
                path: path + ".artwork",
            )
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
            if let authored = ink {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".ink")
                value.ink = appearance.color(resolved)
            }
            if let authored = treatment {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".treatment")
                value.treatment = try resolved.resolve(
                    mode: traits.mode,
                    appearance: appearance,
                    base: value.treatment,
                )
            }
            if let authored = paper {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".paper")
                value.paper = appearance.color(resolved)
            }
            if let authored = usesOpaquePaper {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".usesOpaquePaper")
                value.usesOpaquePaper = resolved
            }
            if let authored = glassTintOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glassTintOpacity")
                value.glassTintOpacity = resolved
            }
            if let authored = outlineColor {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineColor")
                value.outlineColor = appearance.color(resolved)
            }
            if let authored = outlineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineWidth")
                value.outlineWidth = CGFloat(resolved)
            }
            if let authored = shadowOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowOpacity")
                value.shadowOpacity = resolved
            }
            if let authored = shadowRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowRadius")
                value.shadowRadius = CGFloat(resolved)
            }
            if let authored = shadowOffsetY {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowOffsetY")
                value.shadowOffsetY = CGFloat(resolved)
            }
            if let authored = rosetteOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rosetteOpacity")
                value.rosetteOpacity = resolved
            }
            try rosette?.apply(
                to: &value.rosette,
                traits: traits,
                appearance: appearance,
                path: path + ".rosette",
            )
            try border?.apply(
                to: &value.border,
                traits: traits,
                appearance: appearance,
                path: path + ".border",
            )
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle {
    public struct Surface: Codable, Hashable, Sendable {
        public var outlineWidth: BThemeValue<Double>?
        public var inset: BThemeValue<Double>?
        public var microprintGlyphSize: BThemeValue<Double>?
        public var microprintSpacing: BThemeValue<Double>?
        public var rosetteWobble: BThemeValue<Double>?
        public var rosetteLineWidth: BThemeValue<Double>?
        public var primaryRingSpacing: BThemeValue<Double>?
        public var secondaryRingSpacing: BThemeValue<Double>?
        public var shadowColor: BThemeValue<ViewColorDescriptor>?
        public var shadowRadius: BThemeValue<Double>?
        public var shadowOffsetY: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Surface,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = outlineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outlineWidth")
                value.outlineWidth = CGFloat(resolved)
            }
            if let authored = inset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".inset")
                value.inset = CGFloat(resolved)
            }
            if let authored = microprintGlyphSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".microprintGlyphSize")
                value.microprintGlyphSize = CGFloat(resolved)
            }
            if let authored = microprintSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".microprintSpacing")
                value.microprintSpacing = CGFloat(resolved)
            }
            if let authored = rosetteWobble {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rosetteWobble")
                value.rosetteWobble = CGFloat(resolved)
            }
            if let authored = rosetteLineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rosetteLineWidth")
                value.rosetteLineWidth = CGFloat(resolved)
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
            if let authored = shadowColor {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowColor")
                value.shadowColor = appearance.color(resolved)
            }
            if let authored = shadowRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowRadius")
                value.shadowRadius = CGFloat(resolved)
            }
            if let authored = shadowOffsetY {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowOffsetY")
                value.shadowOffsetY = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.LocationForecastStyle.Summary {
    public struct Artwork: Codable, Hashable, Sendable {
        public var widthFraction: BThemeValue<Double>?
        public var inset: BThemeValue<Double>?
        public var gap: BThemeValue<Double>?
        public var leadingOpacity: BThemeValue<Double>?
        public var silhouette: WhereThemeAppearance.CardStyle.RegionShape.Artwork?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationForecastStyle.Summary.Artwork,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = widthFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".widthFraction")
                value.widthFraction = CGFloat(resolved)
            }
            if let authored = inset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".inset")
                value.inset = CGFloat(resolved)
            }
            if let authored = gap {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".gap")
                value.gap = CGFloat(resolved)
            }
            if let authored = leadingOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".leadingOpacity")
                value.leadingOpacity = resolved
            }
            try silhouette?.apply(
                to: &value.silhouette,
                traits: traits,
                appearance: appearance,
                path: path + ".silhouette",
            )
        }
    }
}
