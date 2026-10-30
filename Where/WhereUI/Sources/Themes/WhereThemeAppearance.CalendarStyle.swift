import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct CalendarStyle: Codable, Hashable, Sendable {
        public var overview: Overview?
        public var monthSpacing: BThemeValue<Double>?
        @CopyOnWrite public var month: WhereThemeAppearance.CalendarStyle.MonthStyle? = nil
        public var dotSize: BThemeValue<Double>?
        @CopyOnWrite public var regionBand: WhereThemeAppearance.CalendarStyle.RegionBand? = nil
        @CopyOnWrite public var day: WhereThemeAppearance.CalendarStyle.DayStyle? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try overview?.apply(
                to: &value.overview,
                traits: traits,
                appearance: appearance,
                path: path + ".overview",
            )
            if let authored = monthSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".monthSpacing")
                value.monthSpacing = CGFloat(resolved)
            }
            try month?.apply(
                to: &value.month,
                traits: traits,
                appearance: appearance,
                path: path + ".month",
            )
            if let authored = dotSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dotSize")
                value.dotSize = CGFloat(resolved)
            }
            try regionBand?.apply(
                to: &value.regionBand,
                traits: traits,
                appearance: appearance,
                path: path + ".regionBand",
            )
            try day?.apply(
                to: &value.day,
                traits: traits,
                appearance: appearance,
                path: path + ".day",
            )
        }
    }
}

extension WhereThemeAppearance.CalendarStyle {
    public struct DayBadge: Codable, Hashable, Sendable {
        public var iconSize: BThemeValue<Double>?
        public var iconSpacing: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var offset: BThemeValue<WhereThemeSize>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle.DayBadge,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = iconSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconSize")
                value.iconSize = CGFloat(resolved)
            }
            if let authored = iconSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconSpacing")
                value.iconSpacing = CGFloat(resolved)
            }
            if let authored = padding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".padding")
                value.padding = CGFloat(resolved)
            }
            if let authored = offset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".offset")
                value.offset = resolved.size
            }
        }
    }
}

extension WhereThemeAppearance.CalendarStyle {
    public struct DayStyle: Codable, Hashable, Sendable {
        public var minHeight: BThemeValue<Double>?
        public var numberSize: BThemeValue<Double>?
        public var numberFontSize: BThemeValue<Double>?
        public var numberDotSpacing: BThemeValue<Double>?
        public var dotSize: BThemeValue<Double>?
        public var dotOverlap: BThemeValue<Double>?
        public var dotStrokeWidth: BThemeValue<Double>?
        public var contentSpacing: BThemeValue<Double>?
        public var todayMarker: BThemeValue<ViewColorDescriptor>?
        public var todayNumberColor: BThemeValue<ViewColorDescriptor>?
        public var unresolvedMarker: BThemeValue<ViewColorDescriptor>?
        public var unresolvedNumberColor: BThemeValue<ViewColorDescriptor>?
        @CopyOnWrite public var badge: WhereThemeAppearance.CalendarStyle.DayBadge? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle.DayStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = minHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minHeight")
                value.minHeight = CGFloat(resolved)
            }
            if let authored = numberSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".numberSize")
                value.numberSize = CGFloat(resolved)
            }
            if let authored = numberFontSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".numberFontSize")
                value.numberFontSize = CGFloat(resolved)
            }
            if let authored = numberDotSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".numberDotSpacing")
                value.numberDotSpacing = CGFloat(resolved)
            }
            if let authored = dotSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dotSize")
                value.dotSize = CGFloat(resolved)
            }
            if let authored = dotOverlap {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dotOverlap")
                value.dotOverlap = CGFloat(resolved)
            }
            if let authored = dotStrokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dotStrokeWidth")
                value.dotStrokeWidth = CGFloat(resolved)
            }
            if let authored = contentSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".contentSpacing")
                value.contentSpacing = CGFloat(resolved)
            }
            if let authored = todayMarker {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".todayMarker")
                value.todayMarker = appearance.color(resolved)
            }
            if let authored = todayNumberColor {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".todayNumberColor")
                value.todayNumberColor = appearance.color(resolved)
            }
            if let authored = unresolvedMarker {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unresolvedMarker")
                value.unresolvedMarker = appearance.color(resolved)
            }
            if let authored = unresolvedNumberColor {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unresolvedNumberColor")
                value.unresolvedNumberColor = appearance.color(resolved)
            }
            try badge?.apply(
                to: &value.badge,
                traits: traits,
                appearance: appearance,
                path: path + ".badge",
            )
        }
    }
}

extension WhereThemeAppearance.CalendarStyle {
    public struct MonthStyle: Codable, Hashable, Sendable {
        public var sectionSpacing: BThemeValue<Double>?
        public var gridSpacing: BThemeValue<Double>?
        public var weekdayFontSize: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        @CopyOnWrite public var plain: WhereThemeAppearance.CalendarStyle.MonthStyle.Card? = nil
        @CopyOnWrite public var current: WhereThemeAppearance.CalendarStyle.MonthStyle.Card? = nil
        public var footerDividerSpacing: BThemeValue<Double>?
        public var footerSpacing: BThemeValue<Double>?
        public var footerRowSpacing: BThemeValue<Double>?
        public var stacksFooter: BThemeValue<Bool>?
        public var unfocusedRowOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle.MonthStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = sectionSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sectionSpacing")
                value.sectionSpacing = CGFloat(resolved)
            }
            if let authored = gridSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".gridSpacing")
                value.gridSpacing = CGFloat(resolved)
            }
            if let authored = weekdayFontSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".weekdayFontSize")
                value.weekdayFontSize = CGFloat(resolved)
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
            try plain?.apply(
                to: &value.plain,
                traits: traits,
                appearance: appearance,
                path: path + ".plain",
            )
            try current?.apply(
                to: &value.current,
                traits: traits,
                appearance: appearance,
                path: path + ".current",
            )
            if let authored = footerDividerSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".footerDividerSpacing")
                value.footerDividerSpacing = CGFloat(resolved)
            }
            if let authored = footerSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".footerSpacing")
                value.footerSpacing = CGFloat(resolved)
            }
            if let authored = footerRowSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".footerRowSpacing")
                value.footerRowSpacing = CGFloat(resolved)
            }
            if let authored = stacksFooter {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".stacksFooter")
                value.stacksFooter = resolved
            }
            if let authored = unfocusedRowOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unfocusedRowOpacity")
                value.unfocusedRowOpacity = resolved
            }
        }
    }
}

extension WhereThemeAppearance.CalendarStyle {
    public struct RegionBand: Codable, Hashable, Sendable {
        public var opacity: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var continuationRadius: BThemeValue<Double>?
        public var verticalInset: BThemeValue<Double>?
        @CopyOnWrite public var planned: WhereThemeAppearance.CalendarStyle.RegionBand
            .Planned? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle.RegionBand,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = opacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".opacity")
                value.opacity = resolved
            }
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = continuationRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".continuationRadius")
                value.continuationRadius = CGFloat(resolved)
            }
            if let authored = verticalInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalInset")
                value.verticalInset = CGFloat(resolved)
            }
            try planned?.apply(
                to: &value.planned,
                traits: traits,
                appearance: appearance,
                path: path + ".planned",
            )
        }
    }
}

extension WhereThemeAppearance.CalendarStyle.MonthStyle {
    public struct Card: Codable, Hashable, Sendable {
        public var fill: BThemeValue<ViewColorDescriptor>?
        public var border: BThemeValue<ViewColorDescriptor>?
        public var borderWidth: BThemeValue<Double>?
        public var foreground: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle.MonthStyle.Card,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = fill {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fill")
                value.fill = appearance.color(resolved)
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
            if let authored = foreground {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".foreground")
                value.foreground = appearance.color(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.CalendarStyle.RegionBand {
    public struct Planned: Codable, Hashable, Sendable {
        public var fillOpacity: BThemeValue<Double>?
        public var hatchOpacity: BThemeValue<Double>?
        public var hatchSpacing: BThemeValue<Double>?
        public var hatchLineWidth: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.CalendarStyle.RegionBand.Planned,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = fillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fillOpacity")
                value.fillOpacity = resolved
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
        }
    }
}

extension WhereThemeAppearance.CalendarStyle {
    public struct Overview: Codable, Hashable, Sendable {
        public var columns: BThemeValue<Int>?
        public var spacing: BThemeValue<Double>?
        public var padding: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var dayHeight: BThemeValue<Double>?
        public var dayFontSize: BThemeValue<Double>?
        public var titleFontSize: BThemeValue<Double>?
        public var sectionSpacing: BThemeValue<Double>?
        public var borderWidth: BThemeValue<Double>?
        public var currentBorderWidth: BThemeValue<Double>?
        public var unavailableForeground: BThemeValue<ViewColorDescriptor>?
        public var usesSpatialMotion: BThemeValue<Bool>?
        public var duration: BThemeValue<Double>?
        public var zoomDuration: BThemeValue<Double>?
        public var zoomBackground: BThemeValue<ViewColorDescriptor>?
        public var shakeDistance: BThemeValue<Double>?
        public var regionBand: RegionBand?
        public init() {}
        func apply(
            to value: inout WhereStylesheet.CalendarStyle.Overview,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = columns {
                let resolved = authored.resolve(mode: traits.mode)
                guard (1 ... 12).contains(resolved) else { throw WhereThemeValidationError(
                    path: path + ".columns",
                    reason: "Calendar columns must be between one and twelve",
                ) }
                value.columns = resolved
            }
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
            if let authored = dayHeight {
                let resolved = authored.resolve(mode: traits.mode)
                guard resolved.isFinite,
                      (2 ... 10000).contains(resolved)
                else { throw WhereThemeValidationError(
                    path: path + ".dayHeight",
                    reason: "Overview day height must be at least two points",
                ) }
                value.dayHeight = CGFloat(resolved)
            }
            if let authored = dayFontSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dayFontSize")
                value.dayFontSize = CGFloat(resolved)
            }
            if let authored = titleFontSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleFontSize")
                value.titleFontSize = CGFloat(resolved)
            }
            if let authored = sectionSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".sectionSpacing")
                value.sectionSpacing = CGFloat(resolved)
            }
            if let authored = borderWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".borderWidth")
                value.borderWidth = CGFloat(resolved)
            }
            if let authored = currentBorderWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".currentBorderWidth")
                value.currentBorderWidth = CGFloat(resolved)
            }
            if let authored = unavailableForeground {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unavailableForeground")
                value.unavailableForeground = appearance.color(resolved)
            }
            if let authored = usesSpatialMotion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".usesSpatialMotion")
                value.usesSpatialMotion = resolved
            }
            if let authored = duration {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".duration")
                value.duration = resolved
            }
            if let authored = zoomDuration {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".zoomDuration")
                value.zoomDuration = resolved
            }
            if let authored = zoomBackground {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".zoomBackground")
                value.zoomBackground = appearance.color(resolved)
            }
            if let authored = shakeDistance {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shakeDistance")
                value.shakeDistance = CGFloat(resolved)
            }
            try regionBand?.apply(
                to: &value.regionBand,
                traits: traits,
                appearance: appearance,
                path: path + ".regionBand",
            )
        }
    }
}

extension WhereThemeAppearance.CalendarStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.overview = inheritPatch(overview, from: parent.overview)
        result.monthSpacing = monthSpacing ?? parent.monthSpacing
        result.month = inheritPatch(month, from: parent.month)
        result.dotSize = dotSize ?? parent.dotSize
        result.regionBand = inheritPatch(regionBand, from: parent.regionBand)
        result.day = inheritPatch(day, from: parent.day)
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.DayBadge: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.iconSize = iconSize ?? parent.iconSize
        result.iconSpacing = iconSpacing ?? parent.iconSpacing
        result.padding = padding ?? parent.padding
        result.offset = offset ?? parent.offset
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.DayStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.minHeight = minHeight ?? parent.minHeight
        result.numberSize = numberSize ?? parent.numberSize
        result.numberFontSize = numberFontSize ?? parent.numberFontSize
        result.numberDotSpacing = numberDotSpacing ?? parent.numberDotSpacing
        result.dotSize = dotSize ?? parent.dotSize
        result.dotOverlap = dotOverlap ?? parent.dotOverlap
        result.dotStrokeWidth = dotStrokeWidth ?? parent.dotStrokeWidth
        result.contentSpacing = contentSpacing ?? parent.contentSpacing
        result.todayMarker = todayMarker ?? parent.todayMarker
        result.todayNumberColor = todayNumberColor ?? parent.todayNumberColor
        result.unresolvedMarker = unresolvedMarker ?? parent.unresolvedMarker
        result.unresolvedNumberColor = unresolvedNumberColor ?? parent.unresolvedNumberColor
        result.badge = inheritPatch(badge, from: parent.badge)
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.MonthStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.sectionSpacing = sectionSpacing ?? parent.sectionSpacing
        result.gridSpacing = gridSpacing ?? parent.gridSpacing
        result.weekdayFontSize = weekdayFontSize ?? parent.weekdayFontSize
        result.padding = padding ?? parent.padding
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.plain = inheritPatch(plain, from: parent.plain)
        result.current = inheritPatch(current, from: parent.current)
        result.footerDividerSpacing = footerDividerSpacing ?? parent.footerDividerSpacing
        result.footerSpacing = footerSpacing ?? parent.footerSpacing
        result.footerRowSpacing = footerRowSpacing ?? parent.footerRowSpacing
        result.stacksFooter = stacksFooter ?? parent.stacksFooter
        result.unfocusedRowOpacity = unfocusedRowOpacity ?? parent.unfocusedRowOpacity
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.RegionBand: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.opacity = opacity ?? parent.opacity
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.continuationRadius = continuationRadius ?? parent.continuationRadius
        result.verticalInset = verticalInset ?? parent.verticalInset
        result.planned = inheritPatch(planned, from: parent.planned)
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.MonthStyle.Card: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.fill = fill ?? parent.fill
        result.border = border ?? parent.border
        result.borderWidth = borderWidth ?? parent.borderWidth
        result.foreground = foreground ?? parent.foreground
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.RegionBand.Planned: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.fillOpacity = fillOpacity ?? parent.fillOpacity
        result.hatchOpacity = hatchOpacity ?? parent.hatchOpacity
        result.hatchSpacing = hatchSpacing ?? parent.hatchSpacing
        result.hatchLineWidth = hatchLineWidth ?? parent.hatchLineWidth
        return result
    }
}

extension WhereThemeAppearance.CalendarStyle.Overview: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.columns = columns ?? parent.columns
        result.spacing = spacing ?? parent.spacing
        result.padding = padding ?? parent.padding
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.dayHeight = dayHeight ?? parent.dayHeight
        result.dayFontSize = dayFontSize ?? parent.dayFontSize
        result.titleFontSize = titleFontSize ?? parent.titleFontSize
        result.sectionSpacing = sectionSpacing ?? parent.sectionSpacing
        result.borderWidth = borderWidth ?? parent.borderWidth
        result.currentBorderWidth = currentBorderWidth ?? parent.currentBorderWidth
        result.unavailableForeground = unavailableForeground ?? parent.unavailableForeground
        result.usesSpatialMotion = usesSpatialMotion ?? parent.usesSpatialMotion
        result.duration = duration ?? parent.duration
        result.zoomDuration = zoomDuration ?? parent.zoomDuration
        result.zoomBackground = zoomBackground ?? parent.zoomBackground
        result.shakeDistance = shakeDistance ?? parent.shakeDistance
        result.regionBand = inheritPatch(regionBand, from: parent.regionBand)
        return result
    }
}
