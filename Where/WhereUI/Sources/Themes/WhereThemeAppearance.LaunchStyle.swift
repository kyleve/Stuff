import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct LaunchStyle: Codable, Hashable, Sendable {
        public var reveal: BThemeValue<WhereThemeAppearance.LaunchStyle.Reveal>?
        public var revealAnimation: BThemeValue<WhereThemeAnimation>?
        public var captionAnimation: WhereThemeOptional<BThemeValue<WhereThemeAnimation>>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.LaunchStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = reveal {
                let resolved = authored.resolve(mode: traits.mode)
                value.reveal = resolved.native
            }
            if let authored = revealAnimation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".revealAnimation")
                value.revealAnimation = resolved.animation
            }
            if let captionAnimation {
                switch captionAnimation {
                    case .clear: value.captionAnimation = nil
                    case let .value(authored):
                        let resolved = authored.resolve(mode: traits.mode)
                        try WhereThemeValidation.validate(
                            resolved,
                            path: path + ".captionAnimation",
                        )
                        value.captionAnimation = resolved.animation
                }
            }
        }
    }
}

extension WhereThemeAppearance.LaunchStyle {
    public enum Reveal: Codable, Hashable, Sendable {
        case zoom
        case crossfade
        var native: WhereStylesheet.LaunchStyle.Reveal {
            switch self {
                case .zoom: .zoom
                case .crossfade: .crossfade
            }
        }
    }
}
