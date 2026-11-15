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
        @CopyOnWrite public var artwork: WhereThemeAppearance.CardStyle.RegionShape.Artwork? = nil
        public var maximumAspectScale: BThemeValue<Double>?
        @CopyOnWrite public var rosette: WhereThemeAppearance.CardStyle.Rosette? = nil
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

extension WhereThemeAppearance.LocationsBackgroundStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.paper = paper ?? parent.paper
        result.ink = ink ?? parent.ink
        result.showsInk = showsInk ?? parent.showsInk
        result.preferredCellSize = preferredCellSize ?? parent.preferredCellSize
        result.artwork = inheritPatch(artwork, from: parent.artwork)
        result.maximumAspectScale = maximumAspectScale ?? parent.maximumAspectScale
        result.rosette = inheritPatch(rosette, from: parent.rosette)
        result.rosetteOpacity = rosetteOpacity ?? parent.rosetteOpacity
        return result
    }
}
