import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct RegionMapStyle: Codable, Hashable, Sendable {
        public var overview: WhereThemeAppearance.RegionMapStyle.Viewport?
        public var pointPreview: WhereThemeAppearance.RegionMapStyle.Viewport?
        public var uncertaintyFillOpacity: BThemeValue<Double>?
        public var uncertaintyStrokeOpacity: BThemeValue<Double>?
        public var uncertaintyStrokeWidth: BThemeValue<Double>?
        public var routeLineWidth: BThemeValue<Double>?
        public var capturePointDiameter: BThemeValue<Double>?
        public var captureInset: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.RegionMapStyle,
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
            try pointPreview?.apply(
                to: &value.pointPreview,
                traits: traits,
                appearance: appearance,
                path: path + ".pointPreview",
            )
            if let authored = uncertaintyFillOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".uncertaintyFillOpacity")
                value.uncertaintyFillOpacity = resolved
            }
            if let authored = uncertaintyStrokeOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".uncertaintyStrokeOpacity",
                )
                value.uncertaintyStrokeOpacity = resolved
            }
            if let authored = uncertaintyStrokeWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".uncertaintyStrokeWidth")
                value.uncertaintyStrokeWidth = CGFloat(resolved)
            }
            if let authored = routeLineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".routeLineWidth")
                value.routeLineWidth = CGFloat(resolved)
            }
            if let authored = capturePointDiameter {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".capturePointDiameter")
                value.capturePointDiameter = CGFloat(resolved)
            }
            if let authored = captureInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".captureInset")
                value.captureInset = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.RegionMapStyle {
    public struct Viewport: Codable, Hashable, Sendable {
        public var height: BThemeValue<Double>?
        public var minimumSpanMeters: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.RegionMapStyle.Viewport,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = height {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".height")
                value.height = CGFloat(resolved)
            }
            if let authored = minimumSpanMeters {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumSpanMeters")
                value.minimumSpanMeters = resolved
            }
        }
    }
}
