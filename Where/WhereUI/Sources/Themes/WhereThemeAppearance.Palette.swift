import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct Palette: Codable, Hashable, Sendable {
        public var primary: WhereThemeAppearance.Palette.Primary?
        public var splash: WhereThemeAppearance.Palette.Splash?
        public var onboarding: WhereThemeAppearance.Palette.Onboarding?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Palette,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try primary?.apply(
                to: &value.primary,
                traits: traits,
                appearance: appearance,
                path: path + ".primary",
            )
            try splash?.apply(
                to: &value.splash,
                traits: traits,
                appearance: appearance,
                path: path + ".splash",
            )
            try onboarding?.apply(
                to: &value.onboarding,
                traits: traits,
                appearance: appearance,
                path: path + ".onboarding",
            )
        }
    }
}

extension WhereThemeAppearance.Palette {
    public struct Onboarding: Codable, Hashable, Sendable {
        public var backgroundTop: BThemeValue<ViewColorDescriptor>?
        public var backgroundBottom: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Palette.Onboarding,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = backgroundTop {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundTop")
                value.backgroundTop = appearance.color(resolved)
            }
            if let authored = backgroundBottom {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundBottom")
                value.backgroundBottom = appearance.color(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.Palette {
    public struct Primary: Codable, Hashable, Sendable {
        public var backgroundTop: BThemeValue<ViewColorDescriptor>?
        public var backgroundBottom: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Palette.Primary,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = backgroundTop {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundTop")
                value.backgroundTop = appearance.color(resolved)
            }
            if let authored = backgroundBottom {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".backgroundBottom")
                value.backgroundBottom = appearance.color(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.Palette {
    public struct Splash: Codable, Hashable, Sendable {
        public var background: BThemeValue<ViewColorDescriptor>?
        public var vignetteCenter: BThemeValue<ViewColorDescriptor>?
        public var vignetteEdge: BThemeValue<ViewColorDescriptor>?
        public var iconGlow: BThemeValue<ViewColorDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Palette.Splash,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = background {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".background")
                value.background = appearance.color(resolved)
            }
            if let authored = vignetteCenter {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".vignetteCenter")
                value.vignetteCenter = appearance.color(resolved)
            }
            if let authored = vignetteEdge {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".vignetteEdge")
                value.vignetteEdge = appearance.color(resolved)
            }
            if let authored = iconGlow {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconGlow")
                value.iconGlow = appearance.color(resolved)
            }
        }
    }
}
