import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct Spacing: Codable, Hashable, Sendable {
        public var xxSmall: BThemeValue<Double>?
        public var xSmall: BThemeValue<Double>?
        public var small: BThemeValue<Double>?
        public var medium: BThemeValue<Double>?
        public var regular: BThemeValue<Double>?
        public var large: BThemeValue<Double>?
        public var xLarge: BThemeValue<Double>?
        public var xxLarge: BThemeValue<Double>?
        public var xxxLarge: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Spacing,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = xxSmall {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".xxSmall")
                value.xxSmall = CGFloat(resolved)
            }
            if let authored = xSmall {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".xSmall")
                value.xSmall = CGFloat(resolved)
            }
            if let authored = small {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".small")
                value.small = CGFloat(resolved)
            }
            if let authored = medium {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".medium")
                value.medium = CGFloat(resolved)
            }
            if let authored = regular {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".regular")
                value.regular = CGFloat(resolved)
            }
            if let authored = large {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".large")
                value.large = CGFloat(resolved)
            }
            if let authored = xLarge {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".xLarge")
                value.xLarge = CGFloat(resolved)
            }
            if let authored = xxLarge {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".xxLarge")
                value.xxLarge = CGFloat(resolved)
            }
            if let authored = xxxLarge {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".xxxLarge")
                value.xxxLarge = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.Spacing: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.xxSmall = xxSmall ?? parent.xxSmall
        result.xSmall = xSmall ?? parent.xSmall
        result.small = small ?? parent.small
        result.medium = medium ?? parent.medium
        result.regular = regular ?? parent.regular
        result.large = large ?? parent.large
        result.xLarge = xLarge ?? parent.xLarge
        result.xxLarge = xxLarge ?? parent.xxLarge
        result.xxxLarge = xxxLarge ?? parent.xxxLarge
        return result
    }
}
