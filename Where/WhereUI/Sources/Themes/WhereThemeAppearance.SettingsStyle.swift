import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct SettingsStyle: Codable, Hashable, Sendable {
        public var iconForeground: BThemeValue<ViewColorDescriptor>?
        public var iconSize: BThemeValue<Double>?
        public var iconCornerRadius: BThemeValue<Double>?
        public var iconSymbolSize: BThemeValue<Double>?
        public var flashAnimation: WhereThemeOptional<BThemeValue<WhereThemeAnimation>>?
        public var flashDuration: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.SettingsStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = iconForeground {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconForeground")
                value.iconForeground = appearance.color(resolved)
            }
            if let authored = iconSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconSize")
                value.iconSize = CGFloat(resolved)
            }
            if let authored = iconCornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconCornerRadius")
                value.iconCornerRadius = CGFloat(resolved)
            }
            if let authored = iconSymbolSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconSymbolSize")
                value.iconSymbolSize = CGFloat(resolved)
            }
            if let flashAnimation {
                switch flashAnimation {
                    case .clear: value.flashAnimation = nil
                    case let .value(authored):
                        let resolved = authored.resolve(mode: traits.mode)
                        try WhereThemeValidation.validate(resolved, path: path + ".flashAnimation")
                        value.flashAnimation = resolved.animation
                }
            }
            if let authored = flashDuration {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".flashDuration")
                value.flashDuration = Duration.seconds(resolved)
            }
        }
    }
}
