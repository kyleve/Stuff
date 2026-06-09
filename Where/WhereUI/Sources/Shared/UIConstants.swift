import CoreGraphics

/// Centralized layout constants for WhereUI so views don't sprinkle magic
/// numbers for spacing, padding, corner radii, and one-off element sizes.
enum UIConstants {
    /// Generic spacing scale, in points.
    enum Spacings {
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let regular: CGFloat = 10
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 14
        static let xxLarge: CGFloat = 16
        static let xxxLarge: CGFloat = 20
    }

    /// Padding inside container surfaces such as the region cards.
    enum Padding {
        static let compactCard: CGFloat = 16
        static let card: CGFloat = 22
    }

    /// Corner radii for Liquid Glass surfaces.
    enum CornerRadius {
        static let compactCard: CGFloat = 22
        static let card: CGFloat = 28
    }

    /// Tinted drop-shadow geometry for the region cards, giving them a bold,
    /// color-saturated lift off the page. Two layers stack: a tight rim glow
    /// (`cardGlowRadius`) and a broad lift (`cardRadius`).
    enum Shadow {
        static let cardRadius: CGFloat = 34
        static let cardRadiusCompact: CGFloat = 17
        static let cardGlowRadius: CGFloat = 12
        static let cardGlowRadiusCompact: CGFloat = 6
        static let cardOffsetY: CGFloat = 18
        static let cardOffsetYCompact: CGFloat = 9
    }

    /// One-off element sizes that aren't part of the spacing scale.
    enum Size {
        static let progressBarHeight: CGFloat = 6
        static let timelineAccentWidth: CGFloat = 4
        static let timelineAccentHeight: CGFloat = 34
        static let heroNumberFontSize: CGFloat = 46
        static let statusIconWidth: CGFloat = 28
        /// Diameter of the region card's circular "entry stamp" impression.
        static let entryStamp: CGFloat = 88
        static let entryStampCompact: CGFloat = 52
        /// Point size of the oversized region glyph watermarked behind a card.
        static let stampWatermark: CGFloat = 150
        static let stampWatermarkCompact: CGFloat = 96
        /// Point size of the card's faux machine-readable-zone (MRZ) code.
        static let mrzFontSize: CGFloat = 11
        /// Point size of the Primary tab's gold-foil "Where" masthead.
        static let mastheadFontSize: CGFloat = 52
        /// Diameter of the gold passport crest emblem.
        static let passportCrest: CGFloat = 72
        /// Height of the map header on the Elsewhere region drill-in.
        static let regionMapHeight: CGFloat = 220
    }
}
