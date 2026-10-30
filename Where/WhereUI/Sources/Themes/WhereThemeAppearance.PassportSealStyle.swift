import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct PassportSealStyle: Codable, Hashable, Sendable {
        public var size: BThemeValue<Double>?
        public var rotationDegrees: BThemeValue<Double>?
        public var outerLineWidth: BThemeValue<Double>?
        public var innerLineWidth: BThemeValue<Double>?
        public var innerInset: BThemeValue<Double>?
        public var dashLength: BThemeValue<Double>?
        public var dashSpacing: BThemeValue<Double>?
        public var symbolFont: BThemeValue<ViewFontDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.PassportSealStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = size {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".size")
                value.size = CGFloat(resolved)
            }
            if let authored = rotationDegrees {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rotationDegrees")
                value.rotationDegrees = resolved
            }
            if let authored = outerLineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".outerLineWidth")
                value.outerLineWidth = CGFloat(resolved)
            }
            if let authored = innerLineWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".innerLineWidth")
                value.innerLineWidth = CGFloat(resolved)
            }
            if let authored = innerInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".innerInset")
                value.innerInset = CGFloat(resolved)
            }
            if let authored = dashLength {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dashLength")
                value.dashLength = CGFloat(resolved)
            }
            if let authored = dashSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: 0 ... 10000,
                    path: path + ".dashSpacing",
                )
                value.dashSpacing = CGFloat(resolved)
            }
            if let authored = symbolFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".symbolFont")
                value.symbolFont = resolved.font
            }
        }
    }
}
