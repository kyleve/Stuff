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
    var size = Size()
    var card = CardStyles.standard

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

        // Reduce Transparency flattens the cards: drop the decorative rim-glow
        // layer (the translucent halo) on both card variants.
        if traits.accessibility.isReduceTransparencyEnabled {
            card.regular.glow.radius = 0
            card.compact.glow.radius = 0
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

    /// One-off element sizes that aren't part of the spacing scale. Card-specific
    /// geometry (stamp, watermark, progress bar, shadows, fonts) lives on
    /// ``CardStyle`` instead.
    struct Size: Equatable {
        var timelineAccentWidth: CGFloat = 4
        var timelineAccentHeight: CGFloat = 34
        var calendarDot: CGFloat = 6
        var calendarDayMinHeight: CGFloat = 44
        var statusIconWidth: CGFloat = 28
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

// MARK: - Card

extension WhereStylesheet {
    /// The complete visual spec for a `RegionSummaryCard`. Bundling every value
    /// the card's appearance depends on into one type — with a `.regular` variant
    /// (the big Primary cards) and a `.compact` variant (the Elsewhere list) —
    /// lets the view read a single resolved `CardStyle` instead of branching on a
    /// `compact` flag across ~30 tokens. Non-varying generic spacing (the inner
    /// header/number stacks) still comes from ``Spacing``.
    struct CardStyle: Equatable {
        /// Which card the stylesheet vends: the Primary tab uses `.regular`, the
        /// Elsewhere tab `.compact`.
        enum Variant {
            case regular
            case compact
        }

        var cornerRadius: CGFloat
        var padding: CGFloat
        /// Spacing between the card's stacked rows (header, hero number, bar).
        var contentSpacing: CGFloat
        var progressBarHeight: CGFloat
        /// Diameter of the circular "entry stamp" impression.
        var entryStampSize: CGFloat
        /// Whether the entry stamp draws its curved region-name arc — dropped on
        /// the small compact stamp where it can't be read.
        var showsArcText: Bool
        var regionNameFont: Font
        var regionNameTracking: CGFloat
        var heroNumberFont: Font
        var dayUnitFont: Font
        /// Point size of the oversized region glyph watermarked behind the card.
        var watermarkFontSize: CGFloat
        /// Offset of that watermark toward the bottom-trailing corner.
        var watermarkOffset: CGSize
        /// Holographic sheen strength (the Primary cards catch more light).
        var holographicIntensity: Double
        /// Line width of the heavy outer frame stroke.
        var frameOuterLineWidth: CGFloat
        /// Whether the dashed perforation ring is drawn (Primary cards only).
        var showsPerforationRing: Bool
        /// Inset of the innermost dashed frame line.
        var innerFrameInset: CGFloat
        var rosette: Rosette
        /// The tight rim glow; its `radius` drops to 0 under Reduce Transparency.
        var glow: Shadow
        /// The broad lift shadow beneath the card.
        var lift: Shadow

        /// The concentric "security print" rings printed behind the stamp.
        struct Rosette: Equatable {
            var wobble: CGFloat
            var lineWidth: CGFloat
            var primaryRingSpacing: CGFloat
            var secondaryRingSpacing: CGFloat
        }

        /// A region-tinted drop shadow: the view supplies the region tint, this
        /// supplies the geometry and how strongly to tint it.
        struct Shadow: Equatable {
            var opacity: Double
            var radius: CGFloat
            var offsetY: CGFloat = 0
        }
    }

    /// The `.regular` / `.compact` card specs the stylesheet vends; a view picks
    /// one with `stylesheet.card[variant]`.
    struct CardStyles: Equatable {
        var regular: CardStyle
        var compact: CardStyle

        subscript(_ variant: CardStyle.Variant) -> CardStyle {
            switch variant {
                case .regular: regular
                case .compact: compact
            }
        }

        /// The fixed card geometry, migrated from the former split
        /// `Shadow`/`Size` tokens and the card's inline `compact ? … : …` values.
        static let standard = CardStyles(
            regular: CardStyle(
                cornerRadius: 28,
                padding: 22,
                contentSpacing: 16,
                progressBarHeight: 10,
                entryStampSize: 88,
                showsArcText: true,
                // Fixed point size (not a Dynamic Type text style) for precise
                // control against the entry stamp: the longest common headline
                // names ("California" / "New York") fit, and any over-long one
                // tightens then scales via `minimumScaleFactor`.
                regionNameFont: .system(size: 38, weight: .semibold, design: .serif),
                regionNameTracking: -0.5,
                heroNumberFont: .system(size: 40, weight: .bold, design: .rounded),
                dayUnitFont: .title3.weight(.medium),
                watermarkFontSize: 150,
                watermarkOffset: CGSize(width: 20, height: 12),
                holographicIntensity: 1,
                frameOuterLineWidth: 3.5,
                showsPerforationRing: true,
                innerFrameInset: 16,
                rosette: CardStyle.Rosette(
                    wobble: 3,
                    lineWidth: 3,
                    primaryRingSpacing: 18,
                    secondaryRingSpacing: 15,
                ),
                glow: CardStyle.Shadow(opacity: 0.75, radius: 12),
                lift: CardStyle.Shadow(opacity: 0.6, radius: 34, offsetY: 18),
            ),
            compact: CardStyle(
                cornerRadius: 22,
                padding: 16,
                contentSpacing: 10,
                progressBarHeight: 6,
                entryStampSize: 52,
                showsArcText: false,
                regionNameFont: .system(.title3, design: .serif).weight(.semibold),
                regionNameTracking: 0,
                heroNumberFont: .system(.title, design: .rounded, weight: .bold),
                dayUnitFont: .subheadline.weight(.medium),
                watermarkFontSize: 96,
                watermarkOffset: CGSize(width: 12, height: 10),
                holographicIntensity: 0.5,
                frameOuterLineWidth: 2.5,
                showsPerforationRing: false,
                innerFrameInset: 12,
                rosette: CardStyle.Rosette(
                    wobble: 2,
                    lineWidth: 2,
                    primaryRingSpacing: 13,
                    secondaryRingSpacing: 11,
                ),
                glow: CardStyle.Shadow(opacity: 0.55, radius: 6),
                lift: CardStyle.Shadow(opacity: 0.4, radius: 17, offsetY: 9),
            ),
        )
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
