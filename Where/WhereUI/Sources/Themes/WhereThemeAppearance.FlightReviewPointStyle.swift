import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct FlightReviewPointStyle: Codable, Hashable, Sendable {
        public var titleFont: BThemeValue<ViewFontDescriptor>?
        public var detailFont: BThemeValue<ViewFontDescriptor>?
        public var minimumActionHeight: BThemeValue<Double>?
        public var mapCornerRadius: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.FlightReviewPointStyle,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = titleFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".titleFont")
                value.titleFont = resolved.font
            }
            if let authored = detailFont {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".detailFont")
                value.detailFont = resolved.font
            }
            if let authored = minimumActionHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minimumActionHeight")
                value.minimumActionHeight = CGFloat(resolved)
            }
            if let authored = mapCornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".mapCornerRadius")
                value.mapCornerRadius = CGFloat(resolved)
            }
        }
    }
}
