import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct ThemePickerStyle: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?
        public var spacing: BThemeValue<Double>?
        public var minimumOptionWidth: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.ThemePickerStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
            if let authored = spacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".spacing")
                value.spacing = CGFloat(resolved)
            }
            if let authored = minimumOptionWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumOptionWidth")
                value.minimumOptionWidth = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.ThemePickerStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.layout = layout ?? parent.layout
        result.spacing = spacing ?? parent.spacing
        result.minimumOptionWidth = minimumOptionWidth ?? parent.minimumOptionWidth
        return result
    }
}
