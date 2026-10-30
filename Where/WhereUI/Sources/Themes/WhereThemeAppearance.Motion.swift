import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct Motion: Codable, Hashable, Sendable {
        public var reveal: BThemeValue<WhereThemeAnimation>?
        public var reducedReveal: BThemeValue<WhereThemeAnimation>?
        public var captionFade: BThemeValue<WhereThemeAnimation>?
        @CopyOnWrite public var staggeredReveal: WhereThemeAppearance.Motion.StaggeredReveal? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Motion,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = reveal {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".reveal")
                value.reveal = resolved.animation
            }
            if let authored = reducedReveal {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".reducedReveal")
                value.reducedReveal = resolved.animation
            }
            if let authored = captionFade {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".captionFade")
                value.captionFade = resolved.animation
            }
            try staggeredReveal?.apply(
                to: &value.staggeredReveal,
                traits: traits,
                appearance: appearance,
                path: path + ".staggeredReveal",
            )
        }
    }
}

extension WhereThemeAppearance.Motion {
    public struct StaggeredReveal: Codable, Hashable, Sendable {
        public var animation: BThemeValue<WhereThemeAnimation>?
        public var verticalOffset: BThemeValue<Double>?
        public var delay: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Motion.StaggeredReveal,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = animation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".animation")
                value.animation = resolved.animation
            }
            if let authored = verticalOffset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalOffset")
                value.verticalOffset = CGFloat(resolved)
            }
            if let authored = delay {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".delay")
                value.delay = resolved
            }
        }
    }
}

extension WhereThemeAppearance.Motion: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.reveal = reveal ?? parent.reveal
        result.reducedReveal = reducedReveal ?? parent.reducedReveal
        result.captionFade = captionFade ?? parent.captionFade
        result.staggeredReveal = inheritPatch(staggeredReveal, from: parent.staggeredReveal)
        return result
    }
}

extension WhereThemeAppearance.Motion.StaggeredReveal: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.animation = animation ?? parent.animation
        result.verticalOffset = verticalOffset ?? parent.verticalOffset
        result.delay = delay ?? parent.delay
        return result
    }
}
