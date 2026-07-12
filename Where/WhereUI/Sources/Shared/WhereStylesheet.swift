import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI

/// The Where app's design tokens, resolved as a Broadway ``BStylesheet``.
///
/// Most tokens are the fixed geometry migrated from the former `UIConstants`; a
/// slice derives from the ``BContext`` traits handed to `init(context:)` (e.g.
/// larger tap targets at accessibility Dynamic Type sizes, a flatter card under
/// Reduce Transparency). Views read the active tokens from the environment via
/// `@Environment(\.stylesheet)` (seeded by `.broadwayRoot` at the app root);
/// callers off the `View` tree (layout helpers, tests) use ``default``.
struct WhereStylesheet: BStylesheet {
    var spacing = Spacing()
    var padding = Padding()
    var cornerRadius = CornerRadius()
    var shadow = Shadow()
    var size = Size()

    init() {}

    init(context: SlicingContext) throws {
        // Start from the fixed scale (property defaults), then adjust the slice
        // of tokens that should react to the current traits. Everything else
        // stays constant, so a default/system context reproduces `default`.
        let traits = context.traits

        // Grow day-grid tap targets at accessibility Dynamic Type sizes.
        if traits.contentSizeCategory.isAccessibilitySize {
            size.calendarDayMinHeight = 56
        }

        // Reduce Transparency flattens the cards: drop the decorative glow layer
        // that reads as a translucent halo.
        if traits.accessibility.isReduceTransparencyEnabled {
            shadow.cardGlowRadius = 0
            shadow.cardGlowRadiusCompact = 0
        }
    }

    /// The fixed token set: the fallback used off the `View` tree (layout
    /// helpers, tests) and when no Broadway root has seeded a context.
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

// MARK: - Themes

/// The Where app's Broadway themes, seeded at the root by `whereBroadwayRoot()`.
/// Empty for now — `WhereStylesheet` derives from traits, not themes — and the
/// home for app-level palette/typography themes as the design system grows.
enum WhereThemes {
    static var current: BThemes {
        BThemes()
    }
}

// MARK: - Root

extension View {
    /// Seeds the Where app's Broadway context — live system traits plus
    /// ``WhereThemes`` — so descendants resolve `@Environment(\.stylesheet)`
    /// against real traits rather than ``WhereStylesheet/default``.
    ///
    /// Applied once at the app root (`RootView`) and, crucially, by the widget
    /// extension: `WhereWidgets` has no other Broadway root, so without this its
    /// views would fall back to `default` and lose the trait-aware tokens (bigger
    /// day-grid tap targets, flattened card glow under Reduce Transparency).
    ///
    /// Lives here (not called as `broadwayRoot` at each site) so callers only
    /// need to import `WhereUI`: `WhereWidgets` must not link `BroadwayUI`
    /// directly — it already gets it through `WhereUI` (a dynamic framework), and
    /// a second copy would split Broadway's type-keyed environment metadata (see
    /// the root `AGENTS.md` "Targets" note).
    public func whereBroadwayRoot() -> some View {
        broadwayRoot(themes: WhereThemes.current)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The active Where design tokens, resolved from the Broadway `BContext`
    /// seeded by `whereBroadwayRoot()`. With no root present (e.g. isolated
    /// previews) the default empty context yields ``WhereStylesheet/default``.
    /// A resolution failure is a programmer error (the initializer never throws),
    /// so it traps in debug and falls back to `default` in release.
    var stylesheet: WhereStylesheet {
        bContext.stylesheet(WhereStylesheet.self, fallback: .default)
    }
}
