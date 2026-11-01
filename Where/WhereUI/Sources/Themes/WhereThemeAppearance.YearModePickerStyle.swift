import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct YearModePickerStyle: Codable, Hashable, Sendable {
        public var layout: BThemeValue<WhereThemeAppearance.ContentLayout>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.YearModePickerStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path _: String,
        ) throws {
            if let authored = layout {
                let resolved = authored.resolve(mode: traits.mode)
                value.layout = resolved.native
            }
        }
    }
}

extension WhereThemeAppearance.YearModePickerStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.layout = layout ?? parent.layout
        return result
    }
}
