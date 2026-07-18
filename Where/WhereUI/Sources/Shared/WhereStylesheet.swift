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
    var size = Size()
    var card = CardStyles.standard
    var calendar = CalendarStyle.standard
    var appIcon = AppIconStyle.standard
    var timeline = TimelineStyle.standard
    var regionMap = RegionMapStyle.standard
    var regionPicker = RegionPickerStyle.standard
    var evidence = EvidenceStyle.standard
    var palette = Palette.standard
    var motion = Motion.standard
    var typography = Typography.standard

    init() {}

    init(context: SlicingContext) throws {
        // Start from the fixed scale (property defaults), then adjust the slice
        // of tokens that should react to the current traits. Everything else
        // stays constant, so a default/system context reproduces `default`.
        let traits = context.traits

        // Grow day-grid tap targets at accessibility Dynamic Type sizes.
        if traits.contentSizeCategory.isAccessibilitySize {
            calendar.dayMinHeight = 56
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

    /// One-off element sizes that aren't part of the spacing scale. Component
    /// geometry (the region card's stamp/shadows, the calendar's day grid/dots,
    /// the app-icon picker) lives on the component style groups instead.
    struct Size: Equatable {
        var statusIconWidth: CGFloat = 28
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
        /// Opacity of the region tint applied to the watermark glyph.
        var watermarkOpacity: Double
        /// Opacity of the region tint mixed into the Liquid Glass surface.
        var glassTintOpacity: Double
        /// Opacity of the region-name header.
        var nameOpacity: Double
        /// The layered stamp frame's strokes (shared across both variants).
        var frame: Frame
        /// Fill opacities of the two security-print rosettes.
        var rosetteFill: RosetteFill

        /// The passport-style frame drawn over the card: a heavy outer line, a
        /// thin line, an optional perforation ring (see
        /// ``CardStyle/showsPerforationRing``), and a dashed inner line. Each
        /// opacity applies over the region tint.
        struct Frame: Equatable {
            var outerOpacity: Double
            var thinOpacity: Double
            var thinWidth: CGFloat
            var perforationOpacity: Double
            var perforationWidth: CGFloat
            var perforationDash: [CGFloat]
            var innerOpacity: Double
            var innerWidth: CGFloat
            var innerDash: [CGFloat]
        }

        /// Fill opacity of the bold and faint security-print rosettes.
        struct RosetteFill: Equatable {
            var primary: Double
            var secondary: Double
        }

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
            watermarkOpacity: 0.08,
            glassTintOpacity: 0.18,
            nameOpacity: 0.8,
            frame: Frame(
                outerOpacity: 0.6,
                thinOpacity: 0.35,
                thinWidth: 1,
                perforationOpacity: 0.45,
                perforationWidth: 2.5,
                perforationDash: [0.01, 6],
                innerOpacity: 0.4,
                innerWidth: 1,
                innerDash: [5, 4],
            ),
            rosetteFill: RosetteFill(primary: 0.12, secondary: 0.08),
        )
    }
}

// MARK: - Calendar

extension WhereStylesheet {
    /// Style for the year calendar (`CalendarView`): `month` covers one month
    /// section, and the remaining properties cover the day cells shared across
    /// every month. Grouping the component's appearance here (rather than reading
    /// scattered generic tokens) keeps its full spec in one place and gives a
    /// future theme a single surface to reskin.
    struct CalendarStyle: Equatable {
        /// Vertical spacing between month sections in the scroll.
        var monthSpacing: CGFloat
        var month: MonthStyle
        /// Min height (tap target) of a day cell — grows at accessibility
        /// Dynamic Type sizes.
        var dayMinHeight: CGFloat
        /// Diameter of a region-presence dot.
        var dotSize: CGFloat
        /// Spacing inside a day cell (the number over its dots).
        var dayContentSpacing: CGFloat
        /// Edge of the rounded day-number chip.
        var dayNumberSize: CGFloat
        /// Fill behind today's day number, and the color of that number.
        var todayMarker: Color
        var todayNumberColor: Color
        /// Fill behind a day that needs attention (unresolved), and its number.
        var unresolvedDayMarker: Color
        var unresolvedNumberColor: Color
        /// The small badge marking a day that carries evidence.
        var evidenceBadge: EvidenceBadge

        /// Style for one month section: the header/grid/footer stack, its
        /// current-month highlight, and the tally footer.
        struct MonthStyle: Equatable {
            /// Spacing between the month header, day grid, and footer.
            var sectionSpacing: CGFloat
            /// Spacing between day cells in the grid (both axes).
            var gridSpacing: CGFloat
            var padding: CGFloat
            var cornerRadius: CGFloat
            /// Wash behind the current month.
            var currentMonthHighlight: Color
            /// Spacing between footer rows.
            var footerSpacing: CGFloat
            /// Spacing within a footer row (dot ↔ label).
            var footerRowSpacing: CGFloat
            /// Opacity of an unfocused footer row while a region is focused.
            var unfocusedRowOpacity: Double
        }

        /// The paperclip badge in a day cell's top-trailing corner marking a day
        /// that carries evidence. Its tint (accent) and backing disc (system
        /// background) follow the app/system roles, so only geometry lives here.
        struct EvidenceBadge: Equatable {
            /// Point size of the paperclip glyph.
            var iconSize: CGFloat
            /// Padding around the glyph inside its backing disc.
            var padding: CGFloat
            /// Offset nudging the badge past the day-number chip's corner.
            var offset: CGSize
        }

        /// The fixed calendar geometry, migrated from the former generic
        /// spacing/size tokens and inline colors in `CalendarView`.
        static let standard = CalendarStyle(
            monthSpacing: 16,
            month: MonthStyle(
                sectionSpacing: 8,
                gridSpacing: 6,
                padding: 16,
                cornerRadius: 22,
                currentMonthHighlight: Color.accentColor.opacity(0.08),
                footerSpacing: 4,
                footerRowSpacing: 6,
                unfocusedRowOpacity: 0.55,
            ),
            dayMinHeight: 44,
            dotSize: 6,
            dayContentSpacing: 2,
            dayNumberSize: 26,
            todayMarker: .accentColor,
            todayNumberColor: .white,
            unresolvedDayMarker: Color.red.opacity(0.15),
            unresolvedNumberColor: .red,
            evidenceBadge: EvidenceBadge(
                iconSize: 8,
                padding: 2,
                offset: CGSize(width: 3, height: -2),
            ),
        )
    }
}

// MARK: - App Icon

extension WhereStylesheet {
    /// Style for the app-icon picker (`AppIconView` + `AppIconLayout`): the grid,
    /// its cells, and the slide-up preview panel (`panel`).
    struct AppIconStyle: Equatable {
        /// Upper bound for a grid thumbnail edge — the size flexes with width.
        var gridMax: CGFloat
        /// Upper bound for the large preview icon edge.
        var previewMax: CGFloat
        /// Spacing between grid rows.
        var gridSpacing: CGFloat
        /// Gap between grid columns (also used to lay the columns out).
        var columnSpacing: CGFloat
        /// Padding around the grid.
        var gridPadding: CGFloat
        /// Spacing inside a cell (icon over its label).
        var cellSpacing: CGFloat
        /// Spacing within a cell's label (checkmark ↔ name).
        var cellLabelSpacing: CGFloat
        /// Opacity of a cell's icon while its own preview panel is up.
        var backgroundedCellOpacity: Double
        /// The dimming scrim behind the preview panel.
        var scrim: Color
        var panel: PanelStyle

        /// The slide-up preview panel.
        struct PanelStyle: Equatable {
            /// Spacing between the panel's stacked elements.
            var spacing: CGFloat
            /// Spacing within the name/hint text stack.
            var textSpacing: CGFloat
            var horizontalPadding: CGFloat
            var bottomPadding: CGFloat
            var cornerRadius: CGFloat
            var background: Color
            var shadowColor: Color
            var shadowRadius: CGFloat
            var shadowOffsetY: CGFloat
            /// The drag-handle grabber's size, opacity, and top inset.
            var grabberSize: CGSize
            var grabberOpacity: Double
            var grabberTopPadding: CGFloat
        }

        static let standard = AppIconStyle(
            gridMax: 180,
            previewMax: 280,
            gridSpacing: 20,
            columnSpacing: 16,
            gridPadding: 16,
            cellSpacing: 12,
            cellLabelSpacing: 6,
            backgroundedCellOpacity: 0.5,
            scrim: Color.black.opacity(0.25),
            panel: PanelStyle(
                spacing: 14,
                textSpacing: 4,
                horizontalPadding: 20,
                bottomPadding: 16,
                cornerRadius: 28,
                background: Color(.systemBackground),
                shadowColor: Color.black.opacity(0.18),
                shadowRadius: 18,
                shadowOffsetY: -4,
                grabberSize: CGSize(width: 40, height: 5),
                grabberOpacity: 0.5,
                grabberTopPadding: 8,
            ),
        )
    }
}

// MARK: - Region Map

extension WhereStylesheet {
    /// Style for the region drill-in map (`RegionDaysView`): the header height
    /// and the translucent GPS-uncertainty circle drawn under each pin.
    struct RegionMapStyle: Equatable {
        /// Height of the map header.
        var height: CGFloat
        /// Fill opacity of a pin's uncertainty circle (over the region tint).
        var uncertaintyFillOpacity: Double
        /// Stroke opacity and width of that circle.
        var uncertaintyStrokeOpacity: Double
        var uncertaintyStrokeWidth: CGFloat

        static let standard = RegionMapStyle(
            height: 220,
            uncertaintyFillOpacity: 0.15,
            uncertaintyStrokeOpacity: 0.6,
            uncertaintyStrokeWidth: 1,
        )
    }
}

// MARK: - Region picker / customization

extension WhereStylesheet {
    /// Style for the primary-region picker (`RegionPickerView`) and per-region
    /// customization (`RegionAppearanceEditor`): the selectable-state map fills,
    /// the color swatch and emoji/symbol tile geometry, and the default US map
    /// framing. Generic spacing (grid gaps, section stacks) still comes from
    /// ``Spacing``. The camera is stored as raw degrees so the stylesheet stays
    /// MapKit-free; the view assembles the `MKCoordinateRegion`.
    struct RegionPickerStyle: Equatable {
        /// Corner radius of the map's rounded container.
        var mapCornerRadius: CGFloat
        /// Polygon fill opacity for a selected vs unselected state.
        var selectedFillOpacity: Double
        var unselectedFillOpacity: Double
        /// Polygon stroke opacity + width for a selected vs unselected state.
        var selectedStrokeOpacity: Double
        var unselectedStrokeOpacity: Double
        var selectedStrokeWidth: CGFloat
        var unselectedStrokeWidth: CGFloat
        /// Diameter of a color swatch and the width of its selection ring.
        var colorSwatchSize: CGFloat
        var colorSwatchSelectionRing: CGFloat
        /// Minimum grid cell width for the color swatches.
        var colorSwatchMinWidth: CGFloat
        /// Edge of an emoji/symbol tile and its minimum grid cell width.
        var glyphTileSize: CGFloat
        var glyphTileMinWidth: CGFloat
        /// Corner radius and selection stroke width of a glyph tile.
        var glyphCornerRadius: CGFloat
        var glyphSelectionStrokeWidth: CGFloat
        /// Background tint opacity of a selected glyph tile.
        var glyphSelectedBackgroundOpacity: Double
        /// Default map camera framing the contiguous US (raw degrees).
        var mapCenterLatitude: Double
        var mapCenterLongitude: Double
        var mapSpanLatitude: Double
        var mapSpanLongitude: Double

        static let standard = RegionPickerStyle(
            mapCornerRadius: 12,
            selectedFillOpacity: 0.55,
            unselectedFillOpacity: 0.12,
            selectedStrokeOpacity: 0.9,
            unselectedStrokeOpacity: 0.35,
            selectedStrokeWidth: 2,
            unselectedStrokeWidth: 1,
            colorSwatchSize: 40,
            colorSwatchSelectionRing: 3,
            colorSwatchMinWidth: 44,
            glyphTileSize: 48,
            glyphTileMinWidth: 52,
            glyphCornerRadius: 6,
            glyphSelectionStrokeWidth: 2,
            glyphSelectedBackgroundOpacity: 0.2,
            mapCenterLatitude: 39.5,
            mapCenterLongitude: -98.35,
            mapSpanLatitude: 45,
            mapSpanLongitude: 55,
        )
    }
}

// MARK: - Evidence

extension WhereStylesheet {
    /// Style for the evidence viewer (`EvidenceDetailView` + `EvidenceBlobPreview`):
    /// the rounded attachment-preview surface and the heights the inline PDF and
    /// the still-loading attachment reserve. Generic spacing (the detail header
    /// and list-row stacks) still comes from ``Spacing``.
    struct EvidenceStyle: Equatable {
        /// Corner radius of an attachment preview surface (PDF, image).
        var previewCornerRadius: CGFloat
        /// Minimum height of the inline PDF preview.
        var pdfPreviewMinHeight: CGFloat
        /// Minimum height reserved for the attachment area while its bytes load.
        var loadingMinHeight: CGFloat

        static let standard = EvidenceStyle(
            previewCornerRadius: 22,
            pdfPreviewMinHeight: 420,
            loadingMinHeight: 200,
        )
    }
}

// MARK: - Timeline

extension WhereStylesheet {
    /// Style for the presence timeline's stint rows (`PresenceTimelineList`): the
    /// leading region-tinted accent bar and the row's internal spacing.
    struct TimelineStyle: Equatable {
        /// Spacing between a row's elements (accent, emoji, labels, count).
        var rowSpacing: CGFloat
        /// The leading accent bar's dimensions.
        var accentWidth: CGFloat
        var accentHeight: CGFloat
        /// Spacing within a row's name/date label stack.
        var labelSpacing: CGFloat
        /// Minimum spacing before the trailing day count.
        var trailingMinSpacing: CGFloat
        /// Vertical padding around a row.
        var rowVerticalPadding: CGFloat

        static let standard = TimelineStyle(
            rowSpacing: 12,
            accentWidth: 4,
            accentHeight: 34,
            labelSpacing: 2,
            trailingMinSpacing: 8,
            rowVerticalPadding: 4,
        )
    }
}

// MARK: - Typography

extension WhereStylesheet {
    /// The app's bespoke display faces — the few fonts that aren't one of Apple's
    /// semantic Dynamic Type text styles. Everyday text keeps using the semantic
    /// styles directly (they already scale and adapt); this is where a future
    /// typography theme would reskin the distinctive faces. (The region card's
    /// custom fonts live on ``CardStyle``; `EntryStamp`'s size-relative fonts stay
    /// intrinsic to it.)
    struct Typography: Equatable {
        /// The oversized SF Symbol at the top of each onboarding page.
        var onboardingIcon: Font
        /// The serif region name on the Today widget's single-region hero.
        var widgetHeroRegion: Font
        /// The rounded, bold day-count number on the Year Totals widget.
        var widgetTotalNumber: Font

        static let standard = Typography(
            onboardingIcon: .system(size: 72),
            widgetHeroRegion: .system(.headline, design: .serif).weight(.semibold),
            widgetTotalNumber: .system(.body, design: .rounded, weight: .bold),
        )
    }
}

// MARK: - Motion

extension WhereStylesheet {
    /// App-level animation tokens. Views still decide *when* to apply them and
    /// honor Reduce Motion — they pick `reducedReveal` (a flatter crossfade) over
    /// `reveal`, and skip `captionFade` entirely — so these carry the "full
    /// motion" values.
    struct Motion: Equatable {
        /// The launch splash → app reveal.
        var reveal: Animation
        /// The Reduce-Motion fallback for the reveal.
        var reducedReveal: Animation
        /// One-shot fade for incidental appearance (e.g. the launch caption).
        var captionFade: Animation

        static let standard = Motion(
            reveal: .easeIn(duration: 0.18),
            reducedReveal: .easeInOut(duration: 0.2),
            captionFade: .easeOut(duration: 0.3),
        )
    }
}

// MARK: - Palette

extension WhereStylesheet {
    /// App-level colors that aren't owned by a single component — chiefly the
    /// screen backdrops. This is the primary surface a future app-wide or
    /// seasonal theme reskins. (Per-region tints stay in `RegionStyle`; adaptive
    /// system roles like `.secondary` stay inline; `.accentColor` follows the
    /// app's tint.)
    struct Palette: Equatable {
        var primary: Primary
        var splash: Splash
        var onboarding: Onboarding

        /// The Primary tab's deep "passport cover" backdrop (top → bottom).
        struct Primary: Equatable {
            var backgroundTop: Color
            var backgroundBottom: Color
        }

        /// The launch splash: dark backdrop, radial vignette, brand-tinted icon
        /// glow / radar, and the reassurance caption.
        struct Splash: Equatable {
            var background: Color
            var vignetteCenter: Color
            var vignetteEdge: Color
            var iconGlow: Color
            var caption: Color
            var captionSecondary: Color
        }

        /// The onboarding backdrop (top → bottom).
        struct Onboarding: Equatable {
            var backgroundTop: Color
            var backgroundBottom: Color
        }

        static let standard = Palette(
            primary: Primary(
                backgroundTop: Color(red: 0.07, green: 0.08, blue: 0.13),
                backgroundBottom: Color(red: 0.02, green: 0.02, blue: 0.05),
            ),
            splash: Splash(
                background: .black,
                vignetteCenter: Color(white: 0.16),
                vignetteEdge: .black,
                iconGlow: .accentColor,
                caption: .white,
                captionSecondary: Color.white.opacity(0.7),
            ),
            onboarding: Onboarding(
                backgroundTop: Color(.systemBackground),
                backgroundBottom: Color.accentColor.opacity(0.12),
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
    ///
    /// Also seeds `\.regionStyles` so descendants resolve per-region looks
    /// (`region` cards, calendar dots, widgets, snippets) from one place. The app
    /// passes `WhereSession`'s live resolver, the widget process one built from
    /// its `WidgetSnapshot`, and intents one from their services; the default
    /// empty resolver yields fallback looks (previews, the region-map viewer).
    public func whereBroadwayRoot(
        regionStyles: RegionStyleResolver = .default,
    ) -> some View {
        broadwayRoot(themes: WhereThemes.current)
            .environment(\.regionStyles, regionStyles)
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
