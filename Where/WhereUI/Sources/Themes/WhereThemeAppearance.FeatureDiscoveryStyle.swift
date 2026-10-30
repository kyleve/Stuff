import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct FeatureDiscoveryStyle: Codable, Hashable, Sendable {
        public var appIcon: WhereThemeAppearance.FeatureDiscoveryStyle.AppIconPreview?
        public var regionStyle: WhereThemeAppearance.FeatureDiscoveryStyle.RegionStylePreview?
        public var shareSheet: WhereThemeAppearance.FeatureDiscoveryStyle.ShareSheetPreview?
        public var evidenceArchive: WhereThemeAppearance.FeatureDiscoveryStyle
            .EvidenceArchivePreview?
        public var marketingHeader: WhereThemeAppearance.FeatureDiscoveryStyle.MarketingHeader?
        public var marketingPanel: WhereThemeAppearance.FeatureDiscoveryStyle.MarketingPanel?
        public var backgroundPattern: WhereThemeAppearance.FeatureDiscoveryStyle.BackgroundPattern?
        public var estimatedTime: WhereThemeAppearance.FeatureDiscoveryStyle.EstimatedTime?
        public var siri: WhereThemeAppearance.FeatureDiscoveryStyle.Siri?
        public var widgets: WhereThemeAppearance.FeatureDiscoveryStyle.Widgets?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try appIcon?.apply(
                to: &value.appIcon,
                traits: traits,
                appearance: appearance,
                path: path + ".appIcon",
            )
            try regionStyle?.apply(
                to: &value.regionStyle,
                traits: traits,
                appearance: appearance,
                path: path + ".regionStyle",
            )
            try shareSheet?.apply(
                to: &value.shareSheet,
                traits: traits,
                appearance: appearance,
                path: path + ".shareSheet",
            )
            try evidenceArchive?.apply(
                to: &value.evidenceArchive,
                traits: traits,
                appearance: appearance,
                path: path + ".evidenceArchive",
            )
            try marketingHeader?.apply(
                to: &value.marketingHeader,
                traits: traits,
                appearance: appearance,
                path: path + ".marketingHeader",
            )
            try marketingPanel?.apply(
                to: &value.marketingPanel,
                traits: traits,
                appearance: appearance,
                path: path + ".marketingPanel",
            )
            try backgroundPattern?.apply(
                to: &value.backgroundPattern,
                traits: traits,
                appearance: appearance,
                path: path + ".backgroundPattern",
            )
            try estimatedTime?.apply(
                to: &value.estimatedTime,
                traits: traits,
                appearance: appearance,
                path: path + ".estimatedTime",
            )
            try siri?.apply(
                to: &value.siri,
                traits: traits,
                appearance: appearance,
                path: path + ".siri",
            )
            try widgets?.apply(
                to: &value.widgets,
                traits: traits,
                appearance: appearance,
                path: path + ".widgets",
            )
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct AppIconPreview: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var spacing: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.AppIconPreview,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct BackgroundPattern: Codable, Hashable, Sendable {
        public var contourSpacing: BThemeValue<Double>?
        public var primaryDistortion: BThemeValue<Double>?
        public var secondaryDistortion: BThemeValue<Double>?
        public var horizontalScale: BThemeValue<Double>?
        public var centerXRatio: BThemeValue<Double>?
        public var centerYRatio: BThemeValue<Double>?
        public var phaseStep: BThemeValue<Double>?
        public var lineWidth: BThemeValue<Double>?
        public var opacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.BackgroundPattern,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = contourSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contourSpacing")
                value.contourSpacing = CGFloat(resolved)
            }
            if let authored = primaryDistortion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".primaryDistortion")
                value.primaryDistortion = CGFloat(resolved)
            }
            if let authored = secondaryDistortion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".secondaryDistortion")
                value.secondaryDistortion = CGFloat(resolved)
            }
            if let authored = horizontalScale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".horizontalScale")
                value.horizontalScale = CGFloat(resolved)
            }
            if let authored = centerXRatio {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".centerXRatio")
                value.centerXRatio = CGFloat(resolved)
            }
            if let authored = centerYRatio {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".centerYRatio")
                value.centerYRatio = CGFloat(resolved)
            }
            if let authored = phaseStep {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".phaseStep")
                value.phaseStep = CGFloat(resolved)
            }
            if let authored = lineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lineWidth")
                value.lineWidth = CGFloat(resolved)
            }
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct EstimatedTime: Codable, Hashable, Sendable {
        public var timelineHeight: BThemeValue<Double>?
        public var timelineSpacing: BThemeValue<Double>?
        public var calculationSpacing: BThemeValue<Double>?
        public var segmentCornerRadius: BThemeValue<Double>?
        public var legendDotSize: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.EstimatedTime,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = timelineHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".timelineHeight")
                value.timelineHeight = CGFloat(resolved)
            }
            if let authored = timelineSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".timelineSpacing")
                value.timelineSpacing = CGFloat(resolved)
            }
            if let authored = calculationSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".calculationSpacing")
                value.calculationSpacing = CGFloat(resolved)
            }
            if let authored = segmentCornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".segmentCornerRadius")
                value.segmentCornerRadius = CGFloat(resolved)
            }
            if let authored = legendDotSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".legendDotSize")
                value.legendDotSize = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct EvidenceArchivePreview: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var spacing: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.EvidenceArchivePreview,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct MarketingHeader: Codable, Hashable, Sendable {
        public var badgeSize: BThemeValue<Double>?
        public var symbolPointSize: BThemeValue<Double>?
        public var badgeTintOpacity: BThemeValue<Double>?
        public var contentMaxWidth: BThemeValue<Double>?
        public var spacing: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.MarketingHeader,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = badgeSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".badgeSize")
                value.badgeSize = CGFloat(resolved)
            }
            if let authored = symbolPointSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".symbolPointSize")
                value.symbolPointSize = CGFloat(resolved)
            }
            if let authored = badgeTintOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".badgeTintOpacity")
                value.badgeTintOpacity = resolved
            }
            if let authored = contentMaxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentMaxWidth")
                value.contentMaxWidth = CGFloat(resolved)
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = verticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalPadding")
                value.verticalPadding = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct MarketingPanel: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var maxWidth: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var rowVerticalInset: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.MarketingPanel,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = maxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxWidth")
                value.maxWidth = CGFloat(resolved)
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
            if let authored = rowVerticalInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowVerticalInset")
                value.rowVerticalInset = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct RegionStylePreview: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var spacing: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.RegionStylePreview,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct ShareSheetPreview: Codable, Hashable, Sendable {
        public var sourcesLayout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var sourceLayout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var sourcesSpacing: BThemeValue<Double>?
        public var titleAlignment: BThemeValue<WhereThemeTextAlignment>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.ShareSheetPreview,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = sourcesLayout {
                let resolved = authored.resolve(mode: traits.mode)
                value.sourcesLayout = resolved.native
            }
            if let authored = sourceLayout {
                let resolved = authored.resolve(mode: traits.mode)
                value.sourceLayout = resolved.native
            }
            if let authored = sourcesSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sourcesSpacing")
                value.sourcesSpacing = CGFloat(resolved)
            }
            if let authored = titleAlignment {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleAlignment")
                value.titleAlignment = resolved.alignment
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct Siri: Codable, Hashable, Sendable {
        public var card: WhereThemeAppearance.FeatureDiscoveryStyle.Siri.Card?
        public var bubble: WhereThemeAppearance.FeatureDiscoveryStyle.Siri.Bubble?
        public var speakerIcon: WhereThemeAppearance.FeatureDiscoveryStyle.Siri.SpeakerIcon?
        public var accent: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Siri,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try card?.apply(
                to: &value.card,
                traits: traits,
                appearance: appearance,
                path: path + ".card",
            )
            try bubble?.apply(
                to: &value.bubble,
                traits: traits,
                appearance: appearance,
                path: path + ".bubble",
            )
            try speakerIcon?.apply(
                to: &value.speakerIcon,
                traits: traits,
                appearance: appearance,
                path: path + ".speakerIcon",
            )
            if let authored = accent {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".accent")
                value.accent = appearance.color(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle {
    public struct Widgets: Codable, Hashable, Sendable {
        public var device: WhereThemeAppearance.FeatureDiscoveryStyle.Widgets.Device?
        public var frame: WhereThemeAppearance.FeatureDiscoveryStyle.Widgets.Frame?
        public var wallpapers: WhereThemeAppearance.FeatureDiscoveryStyle.Widgets.Wallpapers?
        public var lockWidgetHeight: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Widgets,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try device?.apply(
                to: &value.device,
                traits: traits,
                appearance: appearance,
                path: path + ".device",
            )
            try frame?.apply(
                to: &value.frame,
                traits: traits,
                appearance: appearance,
                path: path + ".frame",
            )
            try wallpapers?.apply(
                to: &value.wallpapers,
                traits: traits,
                appearance: appearance,
                path: path + ".wallpapers",
            )
            if let authored = lockWidgetHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lockWidgetHeight")
                value.lockWidgetHeight = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Siri {
    public struct Bubble: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?
        public var indent: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Siri.Bubble,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
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
            if let authored = indent {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".indent")
                value.indent = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Siri {
    public struct Card: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var maxWidth: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var spacing: BThemeValue<Double>?
        public var rowVerticalInset: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Siri.Card,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = maxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxWidth")
                value.maxWidth = CGFloat(resolved)
            }
            if let authored = padding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".padding")
                value.padding = CGFloat(resolved)
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = rowVerticalInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowVerticalInset")
                value.rowVerticalInset = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Siri {
    public struct SpeakerIcon: Codable, Hashable, Sendable {
        public var containerSize: BThemeValue<Double>?
        public var symbolPointSize: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Siri.SpeakerIcon,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = containerSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".containerSize")
                value.containerSize = CGFloat(resolved)
            }
            if let authored = symbolPointSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".symbolPointSize")
                value.symbolPointSize = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Widgets {
    public struct Device: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var contentMaxWidth: BThemeValue<Double>?
        public var regularContentWidth: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var spacing: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Widgets.Device,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = contentMaxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentMaxWidth")
                value.contentMaxWidth = CGFloat(resolved)
            }
            if let authored = regularContentWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".regularContentWidth")
                value.regularContentWidth = CGFloat(resolved)
            }
            if let authored = padding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".padding")
                value.padding = CGFloat(resolved)
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Widgets {
    public struct Frame: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Widgets.Frame,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
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
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Widgets {
    public struct Wallpapers: Codable, Hashable, Sendable {
        public var home: WhereThemeAppearance.FeatureDiscoveryStyle.Widgets.Wallpapers.Gradient?
        public var lock: WhereThemeAppearance.FeatureDiscoveryStyle.Widgets.Wallpapers.Gradient?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Widgets.Wallpapers,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try home?.apply(
                to: &value.home,
                traits: traits,
                appearance: appearance,
                path: path + ".home",
            )
            try lock?.apply(
                to: &value.lock,
                traits: traits,
                appearance: appearance,
                path: path + ".lock",
            )
        }
    }
}

extension WhereThemeAppearance.FeatureDiscoveryStyle.Widgets.Wallpapers {
    public struct Gradient: Codable, Hashable, Sendable {
        public var top: BThemeValue<ViewColorDescriptor>?
        public var bottom: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FeatureDiscoveryStyle.Widgets.Wallpapers.Gradient,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = top {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".top")
                value.top = appearance.color(resolved)
            }
            if let authored = bottom {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".bottom")
                value.bottom = appearance.color(resolved)
            }
        }
    }
}
