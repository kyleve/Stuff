import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct TimelineStyle: Codable, Hashable, Sendable {
        @CopyOnWrite public var flight: WhereThemeAppearance.TimelineStyle.Flight? = nil
        @CopyOnWrite public var overview: WhereThemeAppearance.TimelineStyle.Overview? = nil
        @CopyOnWrite public var ribbon: WhereThemeAppearance.TimelineStyle.Ribbon? = nil
        @CopyOnWrite public var rail: WhereThemeAppearance.TimelineStyle.Rail? = nil
        @CopyOnWrite public var row: WhereThemeAppearance.TimelineStyle.Row? = nil
        @CopyOnWrite public var planned: WhereThemeAppearance.TimelineStyle.Planned? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try flight?.apply(
                to: &value.flight,
                traits: traits,
                appearance: appearance,
                path: path + ".flight",
            )
            try overview?.apply(
                to: &value.overview,
                traits: traits,
                appearance: appearance,
                path: path + ".overview",
            )
            try ribbon?.apply(
                to: &value.ribbon,
                traits: traits,
                appearance: appearance,
                path: path + ".ribbon",
            )
            try rail?.apply(
                to: &value.rail,
                traits: traits,
                appearance: appearance,
                path: path + ".rail",
            )
            try row?.apply(
                to: &value.row,
                traits: traits,
                appearance: appearance,
                path: path + ".row",
            )
            try planned?.apply(
                to: &value.planned,
                traits: traits,
                appearance: appearance,
                path: path + ".planned",
            )
        }
    }
}

extension WhereThemeAppearance.TimelineStyle {
    public struct Flight: Codable, Hashable, Sendable {
        public var iconFont: BThemeValue<ViewFontDescriptor>?
        public var verticalPadding: BThemeValue<Double>?
        public var labelSpacing: BThemeValue<Double>?
        public var tint: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Flight,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = iconFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconFont")
                value.iconFont = resolved.font
            }
            if let authored = verticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalPadding")
                value.verticalPadding = CGFloat(resolved)
            }
            if let authored = labelSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".labelSpacing")
                value.labelSpacing = CGFloat(resolved)
            }
            if let authored = tint {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".tint")
                value.tint = appearance.color(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle {
    public struct Overview: Codable, Hashable, Sendable {
        public var spacing: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var background: BThemeValue<ViewColorDescriptor>?
        public var border: BThemeValue<ViewColorDescriptor>?
        public var borderWidth: BThemeValue<Double>?
        public var yearFont: BThemeValue<ViewFontDescriptor>?
        public var pinsToViewport: BThemeValue<Bool>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Overview,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = padding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".padding")
                value.padding = CGFloat(resolved)
            }
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = background {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".background")
                value.background = appearance.color(resolved)
            }
            if let authored = border {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".border")
                value.border = appearance.color(resolved)
            }
            if let authored = borderWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".borderWidth")
                value.borderWidth = CGFloat(resolved)
            }
            if let authored = yearFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".yearFont")
                value.yearFont = resolved.font
            }
            if let authored = pinsToViewport {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".pinsToViewport")
                value.pinsToViewport = resolved
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle {
    public struct Planned: Codable, Hashable, Sendable {
        public var fillOpacity: BThemeValue<Double>?
        public var borderOpacity: BThemeValue<Double>?
        public var hatchOpacity: BThemeValue<Double>?
        public var hatchSpacing: BThemeValue<Double>?
        public var hatchLineWidth: BThemeValue<Double>?
        public var labelOpacity: BThemeValue<Double>?
        public var transitionHeight: BThemeValue<Double>?
        public var joinedBaseHeight: BThemeValue<Double>?
        public var joinedVerticalPadding: BThemeValue<Double>?
        public var joinedLabelSpacing: BThemeValue<Double>?
        public var joinedCountHorizontalPadding: BThemeValue<Double>?
        public var joinedCountVerticalPadding: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Planned,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = fillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fillOpacity")
                value.fillOpacity = resolved
            }
            if let authored = borderOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".borderOpacity")
                value.borderOpacity = resolved
            }
            if let authored = hatchOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".hatchOpacity")
                value.hatchOpacity = resolved
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
            if let authored = labelOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".labelOpacity")
                value.labelOpacity = resolved
            }
            if let authored = transitionHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".transitionHeight")
                value.transitionHeight = CGFloat(resolved)
            }
            if let authored = joinedBaseHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".joinedBaseHeight")
                value.joinedBaseHeight = CGFloat(resolved)
            }
            if let authored = joinedVerticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".joinedVerticalPadding")
                value.joinedVerticalPadding = CGFloat(resolved)
            }
            if let authored = joinedLabelSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".joinedLabelSpacing")
                value.joinedLabelSpacing = CGFloat(resolved)
            }
            if let authored = joinedCountHorizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".joinedCountHorizontalPadding",
                )
                value.joinedCountHorizontalPadding = CGFloat(resolved)
            }
            if let authored = joinedCountVerticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".joinedCountVerticalPadding",
                )
                value.joinedCountVerticalPadding = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle {
    public struct Rail: Codable, Hashable, Sendable {
        public var lineWidth: BThemeValue<Double>?
        public var toCardSpacing: BThemeValue<Double>?
        public var nodeSize: BThemeValue<Double>?
        public var nodeEmojiFont: BThemeValue<ViewFontDescriptor>?
        public var nodeFillOpacity: BThemeValue<Double>?
        public var nodeStrokeWidth: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Rail,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = lineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lineWidth")
                value.lineWidth = CGFloat(resolved)
            }
            if let authored = toCardSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".toCardSpacing")
                value.toCardSpacing = CGFloat(resolved)
            }
            if let authored = nodeSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".nodeSize")
                value.nodeSize = CGFloat(resolved)
            }
            if let authored = nodeEmojiFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".nodeEmojiFont")
                value.nodeEmojiFont = resolved.font
            }
            if let authored = nodeFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".nodeFillOpacity")
                value.nodeFillOpacity = resolved
            }
            if let authored = nodeStrokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".nodeStrokeWidth")
                value.nodeStrokeWidth = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle {
    public struct Ribbon: Codable, Hashable, Sendable {
        public var monthLabelSpacing: BThemeValue<Double>?
        public var height: BThemeValue<Double>?
        public var track: BThemeValue<ViewColorDescriptor>?
        public var border: BThemeValue<ViewColorDescriptor>?
        public var borderWidth: BThemeValue<Double>?
        public var regionSpacing: BThemeValue<Double>?
        public var regionLabelSpacing: BThemeValue<Double>?
        public var separatesRegions: BThemeValue<Bool>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Ribbon,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = monthLabelSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".monthLabelSpacing")
                value.monthLabelSpacing = CGFloat(resolved)
            }
            if let authored = height {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".height")
                value.height = CGFloat(resolved)
            }
            if let authored = track {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".track")
                value.track = appearance.color(resolved)
            }
            if let authored = border {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".border")
                value.border = appearance.color(resolved)
            }
            if let authored = borderWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".borderWidth")
                value.borderWidth = CGFloat(resolved)
            }
            if let authored = regionSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".regionSpacing")
                value.regionSpacing = CGFloat(resolved)
            }
            if let authored = regionLabelSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".regionLabelSpacing")
                value.regionLabelSpacing = CGFloat(resolved)
            }
            if let authored = separatesRegions {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".separatesRegions")
                value.separatesRegions = resolved
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle {
    public struct Row: Codable, Hashable, Sendable {
        @CopyOnWrite public var singleDay: WhereThemeAppearance.TimelineStyle.Row.Sizing? = nil
        public var spacing: BThemeValue<Double>?
        public var labelSpacing: BThemeValue<Double>?
        public var gap: BThemeValue<Double>?
        public var baseHeight: BThemeValue<Double>?
        public var yearScaleHeight: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var fillOpacity: BThemeValue<Double>?
        public var borderOpacity: BThemeValue<Double>?
        public var borderWidth: BThemeValue<Double>?
        public var countHorizontalPadding: BThemeValue<Double>?
        public var countVerticalPadding: BThemeValue<Double>?
        public var countFillOpacity: BThemeValue<Double>?
        public var stacksDayCount: BThemeValue<Bool>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Row,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try singleDay?.apply(
                to: &value.singleDay,
                traits: traits,
                appearance: appearance,
                path: path + ".singleDay",
            )
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = labelSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".labelSpacing")
                value.labelSpacing = CGFloat(resolved)
            }
            if let authored = gap {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".gap")
                value.gap = CGFloat(resolved)
            }
            if let authored = baseHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".baseHeight")
                value.baseHeight = CGFloat(resolved)
            }
            if let authored = yearScaleHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".yearScaleHeight")
                value.yearScaleHeight = CGFloat(resolved)
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
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = fillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fillOpacity")
                value.fillOpacity = resolved
            }
            if let authored = borderOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".borderOpacity")
                value.borderOpacity = resolved
            }
            if let authored = borderWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".borderWidth")
                value.borderWidth = CGFloat(resolved)
            }
            if let authored = countHorizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".countHorizontalPadding")
                value.countHorizontalPadding = CGFloat(resolved)
            }
            if let authored = countVerticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".countVerticalPadding")
                value.countVerticalPadding = CGFloat(resolved)
            }
            if let authored = countFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".countFillOpacity")
                value.countFillOpacity = resolved
            }
            if let authored = stacksDayCount {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".stacksDayCount")
                value.stacksDayCount = resolved
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle.Row {
    public struct Sizing: Codable, Hashable, Sendable {
        public var baseHeight: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.TimelineStyle.Row.Sizing,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = baseHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".baseHeight")
                value.baseHeight = CGFloat(resolved)
            }
            if let authored = verticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalPadding")
                value.verticalPadding = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.TimelineStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.flight = inheritPatch(flight, from: parent.flight)
        result.overview = inheritPatch(overview, from: parent.overview)
        result.ribbon = inheritPatch(ribbon, from: parent.ribbon)
        result.rail = inheritPatch(rail, from: parent.rail)
        result.row = inheritPatch(row, from: parent.row)
        result.planned = inheritPatch(planned, from: parent.planned)
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Flight: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.iconFont = iconFont ?? parent.iconFont
        result.verticalPadding = verticalPadding ?? parent.verticalPadding
        result.labelSpacing = labelSpacing ?? parent.labelSpacing
        result.tint = tint ?? parent.tint
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Overview: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.spacing = spacing ?? parent.spacing
        result.padding = padding ?? parent.padding
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.background = background ?? parent.background
        result.border = border ?? parent.border
        result.borderWidth = borderWidth ?? parent.borderWidth
        result.yearFont = yearFont ?? parent.yearFont
        result.pinsToViewport = pinsToViewport ?? parent.pinsToViewport
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Planned: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.fillOpacity = fillOpacity ?? parent.fillOpacity
        result.borderOpacity = borderOpacity ?? parent.borderOpacity
        result.hatchOpacity = hatchOpacity ?? parent.hatchOpacity
        result.hatchSpacing = hatchSpacing ?? parent.hatchSpacing
        result.hatchLineWidth = hatchLineWidth ?? parent.hatchLineWidth
        result.labelOpacity = labelOpacity ?? parent.labelOpacity
        result.transitionHeight = transitionHeight ?? parent.transitionHeight
        result.joinedBaseHeight = joinedBaseHeight ?? parent.joinedBaseHeight
        result.joinedVerticalPadding = joinedVerticalPadding ?? parent.joinedVerticalPadding
        result.joinedLabelSpacing = joinedLabelSpacing ?? parent.joinedLabelSpacing
        result.joinedCountHorizontalPadding = joinedCountHorizontalPadding ?? parent
            .joinedCountHorizontalPadding
        result.joinedCountVerticalPadding = joinedCountVerticalPadding ?? parent
            .joinedCountVerticalPadding
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Rail: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.lineWidth = lineWidth ?? parent.lineWidth
        result.toCardSpacing = toCardSpacing ?? parent.toCardSpacing
        result.nodeSize = nodeSize ?? parent.nodeSize
        result.nodeEmojiFont = nodeEmojiFont ?? parent.nodeEmojiFont
        result.nodeFillOpacity = nodeFillOpacity ?? parent.nodeFillOpacity
        result.nodeStrokeWidth = nodeStrokeWidth ?? parent.nodeStrokeWidth
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Ribbon: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.monthLabelSpacing = monthLabelSpacing ?? parent.monthLabelSpacing
        result.height = height ?? parent.height
        result.track = track ?? parent.track
        result.border = border ?? parent.border
        result.borderWidth = borderWidth ?? parent.borderWidth
        result.regionSpacing = regionSpacing ?? parent.regionSpacing
        result.regionLabelSpacing = regionLabelSpacing ?? parent.regionLabelSpacing
        result.separatesRegions = separatesRegions ?? parent.separatesRegions
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Row: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.singleDay = inheritPatch(singleDay, from: parent.singleDay)
        result.spacing = spacing ?? parent.spacing
        result.labelSpacing = labelSpacing ?? parent.labelSpacing
        result.gap = gap ?? parent.gap
        result.baseHeight = baseHeight ?? parent.baseHeight
        result.yearScaleHeight = yearScaleHeight ?? parent.yearScaleHeight
        result.horizontalPadding = horizontalPadding ?? parent.horizontalPadding
        result.verticalPadding = verticalPadding ?? parent.verticalPadding
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.fillOpacity = fillOpacity ?? parent.fillOpacity
        result.borderOpacity = borderOpacity ?? parent.borderOpacity
        result.borderWidth = borderWidth ?? parent.borderWidth
        result.countHorizontalPadding = countHorizontalPadding ?? parent.countHorizontalPadding
        result.countVerticalPadding = countVerticalPadding ?? parent.countVerticalPadding
        result.countFillOpacity = countFillOpacity ?? parent.countFillOpacity
        result.stacksDayCount = stacksDayCount ?? parent.stacksDayCount
        return result
    }
}

extension WhereThemeAppearance.TimelineStyle.Row.Sizing: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.baseHeight = baseHeight ?? parent.baseHeight
        result.verticalPadding = verticalPadding ?? parent.verticalPadding
        return result
    }
}
