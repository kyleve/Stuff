import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct RegionPickerStyle: Codable, Hashable, Sendable {
        public var mapCornerRadius: BThemeValue<Double>?
        public var selectedFillOpacity: BThemeValue<Double>?
        public var unselectedFillOpacity: BThemeValue<Double>?
        public var selectedStrokeOpacity: BThemeValue<Double>?
        public var unselectedStrokeOpacity: BThemeValue<Double>?
        public var selectedStrokeWidth: BThemeValue<Double>?
        public var unselectedStrokeWidth: BThemeValue<Double>?
        public var colorSwatchSize: BThemeValue<Double>?
        public var colorSwatchSelectionRing: BThemeValue<Double>?
        public var colorSwatchMinWidth: BThemeValue<Double>?
        public var glyphTileSize: BThemeValue<Double>?
        public var glyphTileMinWidth: BThemeValue<Double>?
        public var glyphCornerRadius: BThemeValue<Double>?
        public var glyphSelectionStrokeWidth: BThemeValue<Double>?
        public var glyphSelectedBackgroundOpacity: BThemeValue<Double>?
        public var mapCenterLatitude: BThemeValue<Double>?
        public var mapCenterLongitude: BThemeValue<Double>?
        public var mapSpanLatitude: BThemeValue<Double>?
        public var mapSpanLongitude: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.RegionPickerStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = mapCornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".mapCornerRadius")
                value.mapCornerRadius = CGFloat(resolved)
            }
            if let authored = selectedFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".selectedFillOpacity")
                value.selectedFillOpacity = resolved
            }
            if let authored = unselectedFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unselectedFillOpacity")
                value.unselectedFillOpacity = resolved
            }
            if let authored = selectedStrokeOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".selectedStrokeOpacity")
                value.selectedStrokeOpacity = resolved
            }
            if let authored = unselectedStrokeOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unselectedStrokeOpacity")
                value.unselectedStrokeOpacity = resolved
            }
            if let authored = selectedStrokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".selectedStrokeWidth")
                value.selectedStrokeWidth = CGFloat(resolved)
            }
            if let authored = unselectedStrokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".unselectedStrokeWidth")
                value.unselectedStrokeWidth = CGFloat(resolved)
            }
            if let authored = colorSwatchSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".colorSwatchSize")
                value.colorSwatchSize = CGFloat(resolved)
            }
            if let authored = colorSwatchSelectionRing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".colorSwatchSelectionRing",
                )
                value.colorSwatchSelectionRing = CGFloat(resolved)
            }
            if let authored = colorSwatchMinWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".colorSwatchMinWidth")
                value.colorSwatchMinWidth = CGFloat(resolved)
            }
            if let authored = glyphTileSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glyphTileSize")
                value.glyphTileSize = CGFloat(resolved)
            }
            if let authored = glyphTileMinWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glyphTileMinWidth")
                value.glyphTileMinWidth = CGFloat(resolved)
            }
            if let authored = glyphCornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glyphCornerRadius")
                value.glyphCornerRadius = CGFloat(resolved)
            }
            if let authored = glyphSelectionStrokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".glyphSelectionStrokeWidth",
                )
                value.glyphSelectionStrokeWidth = CGFloat(resolved)
            }
            if let authored = glyphSelectedBackgroundOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".glyphSelectedBackgroundOpacity",
                )
                value.glyphSelectedBackgroundOpacity = resolved
            }
            if let authored = mapCenterLatitude {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: -90 ... 90,
                    path: path + ".mapCenterLatitude",
                )
                value.mapCenterLatitude = resolved
            }
            if let authored = mapCenterLongitude {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: -180 ... 180,
                    path: path + ".mapCenterLongitude",
                )
                value.mapCenterLongitude = resolved
            }
            if let authored = mapSpanLatitude {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: Double.leastNormalMagnitude ... 180,
                    path: path + ".mapSpanLatitude",
                )
                value.mapSpanLatitude = resolved
            }
            if let authored = mapSpanLongitude {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: Double.leastNormalMagnitude ... 360,
                    path: path + ".mapSpanLongitude",
                )
                value.mapSpanLongitude = resolved
            }
        }
    }
}
