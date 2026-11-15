import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct EvidenceStyle: Codable, Hashable, Sendable {
        public var previewCornerRadius: BThemeValue<Double>?
        public var pdfPreviewMinHeight: BThemeValue<Double>?
        public var loadingMinHeight: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.EvidenceStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = previewCornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".previewCornerRadius")
                value.previewCornerRadius = CGFloat(resolved)
            }
            if let authored = pdfPreviewMinHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".pdfPreviewMinHeight")
                value.pdfPreviewMinHeight = CGFloat(resolved)
            }
            if let authored = loadingMinHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".loadingMinHeight")
                value.loadingMinHeight = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.EvidenceStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.previewCornerRadius = previewCornerRadius ?? parent.previewCornerRadius
        result.pdfPreviewMinHeight = pdfPreviewMinHeight ?? parent.pdfPreviewMinHeight
        result.loadingMinHeight = loadingMinHeight ?? parent.loadingMinHeight
        return result
    }
}
