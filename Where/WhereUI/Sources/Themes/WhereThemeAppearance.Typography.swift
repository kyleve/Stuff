import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct Typography: Codable, Hashable, Sendable {
        public var onboardingIcon: BThemeValue<ViewFontDescriptor>?
        public var widgetHeroRegion: BThemeValue<ViewFontDescriptor>?
        public var widgetTotalNumber: BThemeValue<ViewFontDescriptor>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.Typography,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = onboardingIcon {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".onboardingIcon")
                value.onboardingIcon = resolved.font
            }
            if let authored = widgetHeroRegion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".widgetHeroRegion")
                value.widgetHeroRegion = resolved.font
            }
            if let authored = widgetTotalNumber {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".widgetTotalNumber")
                value.widgetTotalNumber = resolved.font
            }
        }
    }
}

extension WhereThemeAppearance.Typography: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.onboardingIcon = onboardingIcon ?? parent.onboardingIcon
        result.widgetHeroRegion = widgetHeroRegion ?? parent.widgetHeroRegion
        result.widgetTotalNumber = widgetTotalNumber ?? parent.widgetTotalNumber
        return result
    }
}
