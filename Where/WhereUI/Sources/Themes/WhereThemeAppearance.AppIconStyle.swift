import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct AppIconStyle: Codable, Hashable, Sendable {
        public var gridMax: BThemeValue<Double>?
        public var previewMax: BThemeValue<Double>?
        public var gridSpacing: BThemeValue<Double>?
        public var columnSpacing: BThemeValue<Double>?
        public var gridPadding: BThemeValue<Double>?
        public var cellSpacing: BThemeValue<Double>?
        public var cellLabelSpacing: BThemeValue<Double>?
        public var backgroundedCellOpacity: BThemeValue<Double>?
        public var scrim: BThemeValue<ViewColorDescriptor>?
        public var panel: WhereThemeAppearance.AppIconStyle.PanelStyle?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.AppIconStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = gridMax {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".gridMax")
                value.gridMax = CGFloat(resolved)
            }
            if let authored = previewMax {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".previewMax")
                value.previewMax = CGFloat(resolved)
            }
            if let authored = gridSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".gridSpacing")
                value.gridSpacing = CGFloat(resolved)
            }
            if let authored = columnSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".columnSpacing")
                value.columnSpacing = CGFloat(resolved)
            }
            if let authored = gridPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".gridPadding")
                value.gridPadding = CGFloat(resolved)
            }
            if let authored = cellSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cellSpacing")
                value.cellSpacing = CGFloat(resolved)
            }
            if let authored = cellLabelSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cellLabelSpacing")
                value.cellLabelSpacing = CGFloat(resolved)
            }
            if let authored = backgroundedCellOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundedCellOpacity")
                value.backgroundedCellOpacity = resolved
            }
            if let authored = scrim {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scrim")
                value.scrim = appearance.color(resolved)
            }
            try panel?.apply(
                to: &value.panel,
                traits: traits,
                appearance: appearance,
                path: path + ".panel",
            )
        }
    }
}

extension WhereThemeAppearance.AppIconStyle {
    public struct PanelStyle: Codable, Hashable, Sendable {
        public var spacing: BThemeValue<Double>?
        public var textSpacing: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var bottomPadding: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var background: BThemeValue<ViewColorDescriptor>?
        public var shadowColor: BThemeValue<ViewColorDescriptor>?
        public var shadowRadius: BThemeValue<Double>?
        public var shadowOffsetY: BThemeValue<Double>?
        public var grabberSize: BThemeValue<WhereThemeSize>?
        public var grabberOpacity: BThemeValue<Double>?
        public var grabberTopPadding: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.AppIconStyle.PanelStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = textSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".textSpacing")
                value.textSpacing = CGFloat(resolved)
            }
            if let authored = horizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".horizontalPadding")
                value.horizontalPadding = CGFloat(resolved)
            }
            if let authored = bottomPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".bottomPadding")
                value.bottomPadding = CGFloat(resolved)
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
            if let authored = grabberSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".grabberSize")
                value.grabberSize = resolved.size
            }
            if let authored = grabberOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".grabberOpacity")
                value.grabberOpacity = resolved
            }
            if let authored = grabberTopPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".grabberTopPadding")
                value.grabberTopPadding = CGFloat(resolved)
            }
        }
    }
}
