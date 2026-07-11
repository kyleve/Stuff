import BroadwayCore
import CoreGraphics
import SwiftUI

/// The Where app's design tokens, resolved as a Broadway ``BStylesheet``.
///
/// The values currently mirror the former `UIConstants` verbatim; the type
/// exists so that tokens can later derive from the ``BContext`` traits and
/// themes handed to `init(context:)` (light/dark, Dynamic Type, accessibility)
/// rather than staying fixed. Views read the active tokens from the
/// environment via `@Environment(\.whereStyle)`; callers off the `View` tree
/// (layout helpers, tests) use ``default``.
struct WhereStylesheet: BStylesheet {
    var spacing = Spacing()
    var padding = Padding()
    var cornerRadius = CornerRadius()
    var shadow = Shadow()
    var size = Size()

    init() {}

    init(context _: SlicingContext) throws {
        // The values default to the fixed scale above. A later step reads
        // `context.traits` / `context.themes` here to make tokens trait-aware.
    }

    /// The fixed token set: the environment fallback and the value used off the
    /// `View` tree, where the Broadway context isn't reachable.
    static let `default` = WhereStylesheet()
}

extension WhereStylesheet {
    /// Generic spacing scale, in points.
    struct Spacing: Equatable {
        var xxSmall: CGFloat = 2
        var xSmall: CGFloat = 4
        var small: CGFloat = 6
        var medium: CGFloat = 8
        var regular: CGFloat = 10
        var large: CGFloat = 12
        var xLarge: CGFloat = 14
        var xxLarge: CGFloat = 16
        var xxxLarge: CGFloat = 20
    }

    /// Padding inside container surfaces such as the region cards.
    struct Padding: Equatable {
        var compactCard: CGFloat = 16
        var card: CGFloat = 22
    }

    /// Corner radii for Liquid Glass surfaces.
    struct CornerRadius: Equatable {
        var compactCard: CGFloat = 22
        var card: CGFloat = 28
    }

    /// Tinted drop-shadow geometry for the region cards, giving them a bold,
    /// color-saturated lift off the page. Two layers stack: a tight rim glow
    /// (`cardGlowRadius`) and a broad lift (`cardRadius`).
    struct Shadow: Equatable {
        var cardRadius: CGFloat = 34
        var cardRadiusCompact: CGFloat = 17
        var cardGlowRadius: CGFloat = 12
        var cardGlowRadiusCompact: CGFloat = 6
        var cardOffsetY: CGFloat = 18
        var cardOffsetYCompact: CGFloat = 9
    }

    /// One-off element sizes that aren't part of the spacing scale.
    struct Size: Equatable {
        var progressBarHeight: CGFloat = 10
        var progressBarHeightCompact: CGFloat = 6
        var timelineAccentWidth: CGFloat = 4
        var timelineAccentHeight: CGFloat = 34
        var calendarDot: CGFloat = 6
        var calendarDayMinHeight: CGFloat = 44
        var heroNumberFontSize: CGFloat = 40
        /// Point size of the region name header on the big Primary cards. Fixed
        /// (rather than a Dynamic Type text style) for precise control against
        /// the entry stamp on the right: the longest common headline names
        /// ("California" / "New York") still fit at this size, and any over-long
        /// one tightens then scales down via `minimumScaleFactor`.
        var regionNameFontSize: CGFloat = 38
        var statusIconWidth: CGFloat = 28
        /// Diameter of the region card's circular "entry stamp" impression.
        var entryStamp: CGFloat = 88
        var entryStampCompact: CGFloat = 52
        /// Point size of the oversized region glyph watermarked behind a card.
        var stampWatermark: CGFloat = 150
        var stampWatermarkCompact: CGFloat = 96
        /// Height of the map header on the Elsewhere region drill-in.
        var regionMapHeight: CGFloat = 220
        /// Upper bound for a picker-grid thumbnail edge; the actual size flexes
        /// with the container width (see `AppIconLayout`) so icons grow to fill
        /// the space but never exceed this on large displays like iPad.
        var appIconGridMax: CGFloat = 180
        /// Upper bound for the large app-icon preview edge; the actual size
        /// flexes with the container (see `AppIconLayout`). The small preview is
        /// derived from the large one, so it needs no separate cap.
        var appIconPreviewLargeMax: CGFloat = 280
        /// Edge of the selected app icon shown as the hero on the launch splash.
        var launchIcon: CGFloat = 120
        /// Inset from the bottom edge for the launch splash's status caption
        /// (the "updating your data" line shown during a slow store open), kept
        /// clear of the home indicator.
        var launchCaptionBottomInset: CGFloat = 72
    }
}

extension EnvironmentValues {
    // The active Where design tokens. This currently always resolves to
    // ``WhereStylesheet/default``; a later step seeds it from the Broadway
    // `BContext` so the tokens can react to traits and themes.
    @Entry var whereStyle: WhereStylesheet = .default
}
