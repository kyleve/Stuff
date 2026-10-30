import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct LocationsBackgroundStyle: Codable, Hashable, Sendable {
        public var paper: BThemeValue<ViewColorDescriptor>?
        public var ink: BThemeValue<ViewColorDescriptor>?
        public var showsInk: BThemeValue<Bool>?
        public var preferredCellSize: BThemeValue<Double>?
        public var artwork: WhereThemeAppearance.CardStyle.RegionShape.Artwork?
        public var maximumAspectScale: BThemeValue<Double>?
        public var rosette: WhereThemeAppearance.CardStyle.Rosette?
        public var rosetteOpacity: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationsBackgroundStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = paper {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".paper")
                value.paper = appearance.color(resolved)
            }
            if let authored = ink {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".ink")
                value.ink = appearance.color(resolved)
            }
            if let authored = showsInk {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".showsInk")
                value.showsInk = resolved
            }
            if let authored = preferredCellSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".preferredCellSize")
                value.preferredCellSize = CGFloat(resolved)
            }
            try artwork?.apply(
                to: &value.artwork,
                traits: traits,
                appearance: appearance,
                path: path + ".artwork",
            )
            if let authored = maximumAspectScale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maximumAspectScale")
                value.maximumAspectScale = CGFloat(resolved)
            }
            try rosette?.apply(
                to: &value.rosette,
                traits: traits,
                appearance: appearance,
                path: path + ".rosette",
            )
            if let authored = rosetteOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rosetteOpacity")
                value.rosetteOpacity = resolved
            }
        }
    }
}
