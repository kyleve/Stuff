import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct Size: Codable, Hashable, Sendable {
        public var statusIconWidth: BThemeValue<Double>?
        public var launchIcon: BThemeValue<Double>?
        public var launchCaptionBottomInset: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Size,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = statusIconWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".statusIconWidth")
                value.statusIconWidth = CGFloat(resolved)
            }
            if let authored = launchIcon {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".launchIcon")
                value.launchIcon = CGFloat(resolved)
            }
            if let authored = launchCaptionBottomInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".launchCaptionBottomInset",
                )
                value.launchCaptionBottomInset = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.Size: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.statusIconWidth = statusIconWidth ?? parent.statusIconWidth
        result.launchIcon = launchIcon ?? parent.launchIcon
        result.launchCaptionBottomInset = launchCaptionBottomInset ?? parent
            .launchCaptionBottomInset
        return result
    }
}
