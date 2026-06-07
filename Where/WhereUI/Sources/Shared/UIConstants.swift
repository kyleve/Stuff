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

    /// One-off element sizes that aren't part of the spacing scale.
    enum Size {
        static let progressBarHeight: CGFloat = 6
        static let timelineAccentWidth: CGFloat = 4
        static let timelineAccentHeight: CGFloat = 34
        static let heroNumberFontSize: CGFloat = 46
        static let statusIconWidth: CGFloat = 28
        static let passportEmblemSize: CGFloat = 44
    }
}
