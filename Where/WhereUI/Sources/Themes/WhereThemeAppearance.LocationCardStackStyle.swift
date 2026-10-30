import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct LocationCardStackStyle: Codable, Hashable, Sendable {
        public var overtake: WhereThemeAppearance.LocationCardStackStyle.OvertakeMotion?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationCardStackStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try overtake?.apply(
                to: &value.overtake,
                traits: traits,
                appearance: appearance,
                path: path + ".overtake",
            )
        }
    }
}

extension WhereThemeAppearance.LocationCardStackStyle {
    public struct OvertakeMotion: Codable, Hashable, Sendable {
        public var duration: BThemeValue<Double>?
        public var bounce: BThemeValue<Double>?
        public var lateralArc: BThemeValue<Double>?
        public var liftScale: BThemeValue<Double>?
        public var rotationDegrees: BThemeValue<Double>?
        public var settleScale: BThemeValue<Double>?
        public var minimumOpacity: BThemeValue<Double>?
        public var usesSpatialMotion: BThemeValue<Bool>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = duration {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".duration")
                value.duration = resolved
            }
            if let authored = bounce {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".bounce")
                value.bounce = resolved
            }
            if let authored = lateralArc {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".lateralArc")
                value.lateralArc = CGFloat(resolved)
            }
            if let authored = liftScale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".liftScale")
                value.liftScale = CGFloat(resolved)
            }
            if let authored = rotationDegrees {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rotationDegrees")
                value.rotationDegrees = resolved
            }
            if let authored = settleScale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".settleScale")
                value.settleScale = CGFloat(resolved)
            }
            if let authored = minimumOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumOpacity")
                value.minimumOpacity = resolved
            }
            if let authored = usesSpatialMotion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".usesSpatialMotion")
                value.usesSpatialMotion = resolved
            }
        }
    }
}
