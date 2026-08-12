import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI
import WhereCore

/// The Where app's design tokens, resolved as a Broadway ``BStylesheet``.
///
/// Most tokens are the fixed geometry migrated from the former `UIConstants`; a
/// slice derives from the ``BContext`` traits handed to `init(context:)` (e.g.
/// larger tap targets at accessibility Dynamic Type sizes, a flatter card under
/// Reduce Transparency). Views read the active tokens from the environment via
/// `@Environment(\.stylesheet)` (seeded by `.broadwayRoot` at the app root);
/// callers off the `View` tree (layout helpers, tests) use ``default``.
struct WhereStylesheet: BStylesheet {
    var theme = WhereTheme.standard
    var spacing = Spacing()
    var size = Size()
    var seal = SealStyle.standard
    var locations = LocationsStyle.standard
    var card = CardStyles.standard
    var calendar = CalendarStyle.standard
    var appIcon = AppIconStyle.standard
    var timeline = TimelineStyle.standard
    var regionMap = RegionMapStyle.standard
    var regionPicker = RegionPickerStyle.standard
    var evidence = EvidenceStyle.standard
    var recordPreparation = RecordPreparationStyle.standard
    var homeWidget = HomeWidgetStyle.standard
    var recordSnippet = RecordSnippetStyle.standard
    var elsewhereCard = ElsewhereCardStyle.standard
    var locationForecast = LocationForecastStyle.standard
    var palette = Palette.standard
    var motion = Motion.standard
    var launch = LaunchStyle.standard
    var onboarding = OnboardingStyle.standard
    var year = YearStyle.standard
    var typography = Typography.standard
    var settings = SettingsStyle.standard
    var featureDiscovery = FeatureDiscoveryStyle.standard
    var passportCard = PassportCardStyle.standard
    var developerOverlay = DeveloperOverlayStyle.standard

    init() {}

    init(context: SlicingContext) throws {
        // Start from the fixed scale (property defaults), then adjust the slice
        // of tokens that should react to the current traits. Everything else
        // stays constant, so a default/system context reproduces `default`.
        let traits = context.traits
        theme = context.themes[WhereTheme.self]

        switch theme {
            case .standard:
                applyQuietGlassTheme()
            case .alternate:
                break
        }

        // Grow day-grid tap targets at accessibility Dynamic Type sizes.
        if traits.contentSizeCategory.isAccessibilitySize {
            calendar.day.minHeight = 56
            timeline.overview.pinsToViewport = false
            timeline.row.stacksDayCount = true
            featureDiscovery.siri.bubble.indent = 0
            homeWidget.stacksHeader = true
            recordSnippet.stacksHero = true
        }

        // Give every region a consistently labeled ribbon band when tint
        // alone is not an acceptable differentiator.
        if traits.accessibility.shouldDifferentiateWithoutColor {
            timeline.overview.pinsToViewport = false
            timeline.ribbon.separatesRegions = true
        }

        // Reduce Transparency flattens the cards: drop the decorative rim-glow
        // layer (the translucent halo) on both card variants.
        if traits.accessibility.isReduceTransparencyEnabled {
            card.regular.glow.radius = 0
            card.compact.glow.radius = 0
            card.constellation.haloOpacity = 0
        }

        if traits.accessibility.isDarkerSystemColorsEnabled {
            homeWidget.borderOpacity = 0.3
            homeWidget.ruleOpacity = 0.56
            recordSnippet.borderOpacity = 0.32
            featureDiscovery.marketingPanel.borderOpacity = 0.32
            featureDiscovery.backgroundPattern.opacity = 0.18
        }

        // Reduce Motion stops the cards' day count rolling its digits; it
        // crossfades to the new number instead.
        if traits.accessibility.isReduceMotionEnabled {
            card.dayCount = .reducedMotion
            onboarding.motion = .reduced
            year.motion = .reduced
            developerOverlay.menu.motion = .reduced
        }

        // Pale, luminosity-only ink lifts the background security print off
        // dark glass without changing its hue or saturation on touch.
        if traits.mode == .dark {
            card.securityPrint = .dark
            palette = theme == .standard ? .glassDark : .dark
            featureDiscovery.siri.accent = palette.brand.mineral
            featureDiscovery.widgets.wallpapers.home = .init(
                top: palette.brand.canvas,
                bottom: palette.brand.raisedPaper,
            )
        }
    }

    /// Resolve the complete Quiet Glass baseline before accessibility and
    /// appearance traits refine it. Components keep one view hierarchy; this
    /// swaps their authored material, type, geometry, and ornament together.
    private mutating func applyQuietGlassTheme() {
        palette = .glass

        locations.titleFont = .largeTitle.weight(.semibold)
        locations.eyebrowFont = .caption.weight(.semibold)
        locations.summaryFont = .subheadline
        locations.surfaceBorderOpacity = 0.08
        locations.surfaceBorderWidth = 0.5
        locations.featuredMinimumHeight = 286
        locations.standardMinimumHeight = 238

        card.regular.cornerRadius = 26
        card.regular.regionNameTypography = .init(
            size: .fixed(36),
            weight: .semibold,
            design: .default,
        )
        card.regular.regionNameTracking = -0.25
        card.regular.sheen.intensity = 0.15
        card.regular.sheen.staticGlintIntensity = 0.04
        card.regular.glow = .init(opacity: 0, radius: 0)
        card.regular.lift = .init(opacity: 0.09, radius: 14, offsetY: 7)
        card.compact.cornerRadius = 22
        card.compact.regionNameTypography = .init(
            size: .semantic(.title3),
            weight: .semibold,
            design: .default,
        )
        card.compact.sheen.intensity = 0.1
        card.compact.glow = .init(opacity: 0, radius: 0)
        card.glassTintOpacity = 0.09
        card.nameOpacity = 1
        card.watermarkOpacity = 0.035
        card.rosetteFill = .init(primary: 0, secondary: 0)
        if var regionShape = card.regular.regionShape {
            regionShape.watermark.fillOpacity = 0.045
            if var stroke = regionShape.watermark.stroke {
                stroke.opacity = 0.09
                regionShape.watermark.stroke = stroke
            }
            regionShape.securityBorder.opacity = 0
            card.regular.regionShape = regionShape
        }

        calendar.month.cornerRadius = 22
        calendar.month.ruleOpacity = 0
        calendar.month.plain.fill = Color.white.opacity(0.08)
        calendar.month.plain.border = Color.primary.opacity(0.08)
        calendar.month.plain.borderWidth = 0.5
        calendar.month.current.fill = Color.accentColor.opacity(0.045)
        calendar.month.current.border = Color.accentColor.opacity(0.2)
        calendar.month.current.borderWidth = 0.75
        calendar.regionBand.opacity = 0.075

        timeline.overview.cornerRadius = 22
        timeline.overview.background = Color.white.opacity(0.08)
        timeline.overview.border = Color.primary.opacity(0.08)
        timeline.overview.borderWidth = 0.5
        timeline.overview.yearFont = .title2.bold()
        timeline.row.cornerRadius = 20
        timeline.row.borderOpacity = 0.08
        timeline.row.borderWidth = 0.5

        typography.editorialTitle = .largeTitle.bold()
        homeWidget.eyebrowFont = .caption2.weight(.semibold)
        homeWidget.heroNameFont = .title2.weight(.semibold)
        homeWidget.rowNameFont = .caption.weight(.semibold)
        homeWidget.ruleOpacity = 0.18
        homeWidget.borderOpacity = 0.08
        recordSnippet.cornerRadius = 22
        recordSnippet.titleFont = .title3.weight(.semibold)
        recordSnippet.borderOpacity = 0.08
        recordSnippet.ruleOpacity = 0.12
        elsewhereCard.cornerRadius = 26

        year.cover.cornerRadius = 32
        year.cover.titleFont = .largeTitle.weight(.semibold)
        year.cover.figureEditorialFont = .title2.weight(.semibold)
        year.cover.borderOpacity = 0.14
        passportCard.cornerRadius = 24
        passportCard.rosette.primaryOpacity = 0
        passportCard.rosette.secondaryOpacity = 0
        passportCard.glassTintOpacity = 0.08
        passportCard.accentGlow = .init(opacity: 0, radius: 0)
        passportCard.reflectiveSurface.intensity = 0.06

        evidence.archive.titleFont = .title2.weight(.semibold)
        evidence.archive.rowTitleFont = .headline.weight(.semibold)
        evidence.archive.borderOpacity = 0.08
        evidence.compose.titleFont = .title3.weight(.semibold)
        recordPreparation.cornerRadius = 26
        recordPreparation.titleFont = .title2.weight(.semibold)
        recordPreparation.borderOpacity = 0.12
        featureDiscovery.backgroundPattern.opacity = 0
        featureDiscovery.marketingPanel.cornerRadius = 22
        featureDiscovery.marketingPanel.borderOpacity = 0.08
        featureDiscovery.siri.card.cornerRadius = 22
        featureDiscovery.siri.bubble.cornerRadius = 20
        featureDiscovery.widgets.frame.cornerRadius = 22
        featureDiscovery.siri.accent = palette.brand.mineral
        featureDiscovery.widgets.wallpapers.home = .init(
            top: palette.brand.canvas,
            bottom: palette.brand.raisedPaper,
        )
    }

    /// The fixed token set: the fallback used off the `View` tree (layout
    /// helpers, tests) and when no Broadway root has seeded a context.
    static let `default` = WhereStylesheet()
}

// MARK: - Location forecast

extension WhereStylesheet {
    /// Geometry for the annual-estimate panel shared by the Locations tab and
    /// region-focused calendars.
    struct LocationForecastStyle: Equatable {
        var cornerRadius: CGFloat
        var padding: CGFloat
        var rowSpacing: CGFloat
        var estimateSpacing: CGFloat
        var collapsedLabelColor: Color
        var borderColor: Color
        var borderWidth: CGFloat
        var shadowColor: Color
        var shadowRadius: CGFloat
        var shadowOffsetY: CGFloat
        var expansionAnimation: Animation

        static let standard = LocationForecastStyle(
            cornerRadius: 22,
            padding: 16,
            rowSpacing: 12,
            estimateSpacing: 3,
            collapsedLabelColor: Color.primary.opacity(0.5),
            borderColor: Color.primary.opacity(0.06),
            borderWidth: 0.5,
            shadowColor: Color.black.opacity(0.06),
            shadowRadius: 8,
            shadowOffsetY: 2,
            expansionAnimation: .easeInOut(duration: 0.2),
        )
    }
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

// MARK: - Brand seal

extension WhereStylesheet {
    /// Drawing proportions for the W-and-meridian mark shared by launch,
    /// onboarding, annual records, privacy surfaces, and lightweight widgets.
    struct SealStyle: Equatable {
        var outerRingWidth: CGFloat
        var innerRingWidth: CGFloat
        var innerRingInset: CGFloat
        var meridianWidth: CGFloat
        var meridianOpacity: Double
        var letterScale: CGFloat
        var waypointScale: CGFloat
        var waypointOffset: CGSize

        static let standard = SealStyle(
            outerRingWidth: 2,
            innerRingWidth: 0.75,
            innerRingInset: 7,
            meridianWidth: 0.75,
            meridianOpacity: 0.34,
            letterScale: 0.42,
            waypointScale: 0.075,
            waypointOffset: CGSize(width: 0.23, height: -0.2),
        )
    }
}

// MARK: - Locations folio

extension WhereStylesheet {
    /// Editorial hierarchy for the Locations masthead and ranked folio stack.
    struct LocationsStyle: Equatable {
        var horizontalInset: CGFloat
        var topInset: CGFloat
        var mastheadSpacing: CGFloat
        var titleFont: Font
        var eyebrowFont: Font
        var summaryFont: Font
        var ruleWidth: CGFloat
        var cardSpacing: CGFloat
        var featuredMinimumHeight: CGFloat
        var standardMinimumHeight: CGFloat
        var recordIndexFont: Font
        var recordLabelFont: Font
        var surfaceBorderOpacity: Double
        var surfaceBorderWidth: CGFloat

        static let standard = LocationsStyle(
            horizontalInset: 18,
            topInset: 18,
            mastheadSpacing: 12,
            titleFont: .system(.largeTitle, design: .serif).weight(.semibold),
            eyebrowFont: .caption2.weight(.semibold),
            summaryFont: .subheadline,
            ruleWidth: 44,
            cardSpacing: 18,
            featuredMinimumHeight: 300,
            standardMinimumHeight: 248,
            recordIndexFont: .caption.weight(.semibold).monospacedDigit(),
            recordLabelFont: .caption2.weight(.semibold),
            surfaceBorderOpacity: 0.12,
            surfaceBorderWidth: 0.75,
        )
    }
}

// MARK: - Developer overlay

extension WhereStylesheet {
    /// Appearance and motion for the DEBUG-only developer launcher, accordion,
    /// and selected-tool HUD.
    struct DeveloperOverlayStyle: Equatable {
        var edgeInset: CGFloat
        var presentationAnimation: Animation
        var floatingWindow: FloatingWindow
        var panel: Panel
        var menu: Menu

        /// Persisted floating-window constraints used by the overlay model's pure
        /// layout functions.
        struct FloatingWindow: Equatable {
            var maxWidth: CGFloat
            var maxHeight: CGFloat
            var heightFraction: CGFloat
            var minSize: CGSize
            var maxContentInsetFraction: CGFloat

            static let standard = FloatingWindow(
                maxWidth: 420,
                maxHeight: 620,
                heightFraction: 0.62,
                minSize: CGSize(width: 260, height: 320),
                maxContentInsetFraction: 0.8,
            )
        }

        /// Chrome around a selected tool.
        struct Panel: Equatable {
            var cornerRadius: CGFloat
            var fullScreenInset: CGFloat
            var shadowOpacity: Double
            var shadowRadius: CGFloat
            var shadowOffsetY: CGFloat
            var controlHorizontalPadding: CGFloat
            var controlVerticalPadding: CGFloat
            var dragHandleSize: CGSize
            var dragHandleMinHeight: CGFloat
            var resizeGripSize: CGFloat
            var resizeIconSize: CGFloat
            var resizeGripClearance: CGFloat
        }

        /// Geometry and staggered reveal for the lightweight route menu.
        struct Menu: Equatable {
            var maxWidth: CGFloat
            var launcherSpacing: CGFloat
            var rowSpacing: CGFloat
            var horizontalPadding: CGFloat
            var verticalPadding: CGFloat
            var minRowHeight: CGFloat
            var cornerRadius: CGFloat
            var subtitleSpacing: CGFloat
            var iconWidth: CGFloat
            var motion: MenuMotion
        }

        /// One resolved menu-motion treatment. Reduce Motion swaps this entire
        /// value so the spatial move/scale and stagger disappear together.
        struct MenuMotion: Equatable {
            var animation: Animation
            var stagger: Double
            var scale: CGFloat
            var usesSpatialMotion: Bool

            func transition(from edge: Edge, index: Int, itemCount: Int) -> AnyTransition {
                let base: AnyTransition = usesSpatialMotion
                    ? .move(edge: edge).combined(with: .scale(scale: scale))
                    .combined(with: .opacity)
                    : .opacity
                let insertion = animation.delay(stagger * Double(index))
                let removalIndex = max(itemCount - index - 1, 0)
                let removal = animation.delay(stagger * Double(removalIndex))
                return .asymmetric(
                    insertion: base.animation(insertion),
                    removal: base.animation(removal),
                )
            }

            static let standard = MenuMotion(
                animation: .spring(duration: 0.42, bounce: 0.2),
                stagger: 0.04,
                scale: 0.86,
                usesSpatialMotion: true,
            )

            static let reduced = MenuMotion(
                animation: .easeInOut(duration: 0.18),
                stagger: 0,
                scale: 1,
                usesSpatialMotion: false,
            )
        }

        static let standard = DeveloperOverlayStyle(
            edgeInset: 16,
            presentationAnimation: .snappy(duration: 0.3),
            floatingWindow: .standard,
            panel: Panel(
                cornerRadius: 22,
                fullScreenInset: 12,
                shadowOpacity: 0.3,
                shadowRadius: 20,
                shadowOffsetY: 6,
                controlHorizontalPadding: 16,
                controlVerticalPadding: 10,
                dragHandleSize: CGSize(width: 40, height: 5),
                dragHandleMinHeight: 28,
                resizeGripSize: 44,
                resizeIconSize: 13,
                resizeGripClearance: 40,
            ),
            menu: Menu(
                maxWidth: 310,
                launcherSpacing: 10,
                rowSpacing: 8,
                horizontalPadding: 14,
                verticalPadding: 10,
                minRowHeight: 44,
                cornerRadius: 18,
                subtitleSpacing: 2,
                iconWidth: 24,
                motion: .standard,
            ),
        )
    }
}

// MARK: - Card

extension WhereStylesheet {
    /// The complete visual spec for a `RegionSummaryCard`. Bundling every value
    /// the card's appearance depends on into one type — with a `.regular` variant
    /// (the big Locations cards) and a `.compact` variant (the Elsewhere list) —
    /// lets the view read a single resolved `CardStyle` instead of branching on a
    /// `compact` flag across ~30 tokens. Non-varying generic spacing (the inner
    /// header/number stacks) still comes from ``Spacing``.
    struct CardStyle: Equatable {
        /// Which card the stylesheet vends: the Locations cards use `.regular`,
        /// the Elsewhere list `.compact`.
        enum Variant {
            case regular
            case compact
        }

        var cornerRadius: CGFloat
        var padding: CGFloat
        /// Spacing between the card's stacked rows (header, hero number, bar).
        var contentSpacing: CGFloat
        var progressBarHeight: CGFloat
        var entryStamp: EntryStamp
        var regionNameTypography: Typography
        var regionNameTracking: CGFloat
        var heroNumberTypography: Typography
        var dayUnitTypography: Typography
        /// Point size of the oversized region glyph watermarked behind the card.
        var watermarkFontSize: CGFloat
        /// Offset of that watermark toward the bottom-trailing corner.
        var watermarkOffset: CGSize
        /// RegionKit silhouette artwork for the regular card. `nil` keeps the
        /// compact card on its simpler SF Symbol watermark and stamp glyph.
        var regionShape: RegionShape?
        /// Light-sheen strength plus the deterministic pose used until a
        /// live motion sample arrives (and whenever motion must stay static).
        var sheen: Sheen
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

        /// A card text treatment kept as structured data so the DEBUG card
        /// designer can round-trip it without trying to inspect an opaque
        /// SwiftUI `Font` value.
        struct Typography: Equatable {
            var size: Size
            var weight: Weight
            var design: Design

            var font: Font {
                switch size {
                    case let .fixed(points):
                        .system(size: points, weight: weight.fontWeight, design: design.fontDesign)
                    case let .semantic(textStyle):
                        .system(textStyle.fontTextStyle, design: design.fontDesign)
                            .weight(weight.fontWeight)
                }
            }

            enum Size: Equatable {
                case fixed(CGFloat)
                case semantic(TextStyle)
            }

            enum TextStyle: String, CaseIterable, Codable {
                case caption2
                case caption
                case footnote
                case subheadline
                case callout
                case body
                case headline
                case title3
                case title2
                case title
                case largeTitle

                var fontTextStyle: Font.TextStyle {
                    switch self {
                        case .caption2: .caption2
                        case .caption: .caption
                        case .footnote: .footnote
                        case .subheadline: .subheadline
                        case .callout: .callout
                        case .body: .body
                        case .headline: .headline
                        case .title3: .title3
                        case .title2: .title2
                        case .title: .title
                        case .largeTitle: .largeTitle
                    }
                }
            }

            enum Weight: String, CaseIterable, Codable {
                case ultraLight
                case thin
                case light
                case regular
                case medium
                case semibold
                case bold
                case heavy
                case black

                var fontWeight: Font.Weight {
                    switch self {
                        case .ultraLight: .ultraLight
                        case .thin: .thin
                        case .light: .light
                        case .regular: .regular
                        case .medium: .medium
                        case .semibold: .semibold
                        case .bold: .bold
                        case .heavy: .heavy
                        case .black: .black
                    }
                }
            }

            enum Design: String, CaseIterable, Codable {
                case `default`
                case serif
                case rounded
                case monospaced

                var fontDesign: Font.Design {
                    switch self {
                        case .default: .default
                        case .serif: .serif
                        case .rounded: .rounded
                        case .monospaced: .monospaced
                    }
                }
            }
        }

        /// Geometry, ink strength, and typography for the circular passport
        /// impression. The compact style omits `arc` where its text cannot read.
        struct EntryStamp: Equatable {
            var size: CGFloat
            var outerRing: Ring
            var innerRing: DashedRing
            var content: Content
            var arc: Arc?
            var rotationDegrees: Double

            struct Ring: Equatable {
                var opacity: Double
                var lineWidthFraction: CGFloat
            }

            struct DashedRing: Equatable {
                var opacity: Double
                var lineWidthFraction: CGFloat
                var dash: Dash
                var insetFraction: CGFloat

                struct Dash: Equatable {
                    var lengthFraction: CGFloat
                    var spacingFraction: CGFloat
                }
            }

            struct Content: Equatable {
                var spacingFraction: CGFloat
                var artworkExtent: CGSize
                var symbolFont: Typography
                var yearFont: Typography
                var opacity: Double
            }

            struct Arc: Equatable {
                var radiusFraction: CGFloat
                var font: Typography
                var opacity: Double
                var maximumSweepDegrees: Double
                var sweepDegreesPerCharacter: Double
            }

            struct Typography: Equatable {
                var sizeFraction: CGFloat
                var weight: Font.Weight
                var design: Font.Design

                func font(for size: CGFloat) -> Font {
                    .system(size: size * sizeFraction, weight: weight, design: design)
                }
            }

            static func standard(size: CGFloat, showsArcText: Bool) -> EntryStamp {
                EntryStamp(
                    size: size,
                    outerRing: .init(opacity: 0.7, lineWidthFraction: 0.035),
                    innerRing: .init(
                        opacity: 0.45,
                        lineWidthFraction: 0.012,
                        dash: .init(lengthFraction: 0.05, spacingFraction: 0.035),
                        insetFraction: 0.13,
                    ),
                    content: .init(
                        spacingFraction: 0.02,
                        artworkExtent: CGSize(width: 0.42, height: 0.28),
                        symbolFont: .init(sizeFraction: 0.26, weight: .regular, design: .default),
                        yearFont: .init(sizeFraction: 0.15, weight: .bold, design: .serif),
                        opacity: 0.85,
                    ),
                    arc: showsArcText ? .init(
                        radiusFraction: 0.37,
                        font: .init(sizeFraction: 0.1, weight: .semibold, design: .serif),
                        opacity: 0.7,
                        maximumSweepDegrees: 250,
                        sweepDegreesPerCharacter: 17,
                    ) : nil,
                    rotationDegrees: -8,
                )
            }
        }

        /// Styles for the repeated region silhouette: one large security
        /// watermark, one stamp seal, and a microprinted inset border.
        struct RegionShape: Equatable {
            var watermark: Artwork
            var stamp: Artwork
            var securityBorder: SecurityBorder

            /// Projection geometry and ink treatment for one silhouette.
            struct Artwork: Equatable {
                var center: CGPoint
                var extent: CGSize
                var scale: CGFloat
                var fillOpacity: Double
                var stroke: Stroke?

                struct Stroke: Equatable {
                    var opacity: Double
                    var width: CGFloat
                }
            }

            /// The inset ring of tiny tangent-aligned region silhouettes.
            struct SecurityBorder: Equatable {
                var inset: CGFloat
                var glyphSize: CGFloat
                var spacing: CGFloat
                var opacity: Double
            }
        }

        struct Sheen: Equatable {
            var intensity: Double
            /// Strength of only the white glint while the pose is
            /// static; the grayscale wash keeps `intensity` so the card retains
            /// dimensional light without fading toward white.
            var staticGlintIntensity: Double
            var staticPose: Pose

            struct Pose: Equatable {
                var roll: Double
                var pitch: Double
            }
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
        /// Opacity of the estimated progress rendered behind recorded days.
        var estimatedProgressOpacity: Double = 0.3
        /// Fill opacities of the two security-print rosettes.
        var rosetteFill: RosetteFill
        /// How the region tint is prepared for decorative security printing.
        var securityPrint: SecurityPrint
        /// How the day count changes while the card is on screen; resolves to
        /// ``DayCountStyle/reducedMotion`` under Reduce Motion.
        var dayCount: DayCountStyle
        /// Static GPS pinpricks plotted inside the regular card's region
        /// watermark. Point selection and drawing geometry travel together so
        /// accessibility slicing cannot leave half a glow treatment behind.
        var constellation: Constellation

        struct Constellation: Equatable {
            var gridResolution: Int
            var maximumPointCount: Int
            var coreDiameter: CGFloat
            var coreOpacity: Double
            var coreWhiteMix: Double
            var haloRadius: CGFloat
            var haloOpacity: Double

            static let standard = Constellation(
                gridResolution: 48,
                maximumPointCount: 96,
                coreDiameter: 2.5,
                coreOpacity: 0.92,
                coreWhiteMix: 0.72,
                haloRadius: 6,
                haloOpacity: 0.32,
            )
        }

        /// Fill opacity of the bold and faint security-print rosettes.
        struct RosetteFill: Equatable {
            var primary: Double
            var secondary: Double
        }

        /// Keeps security artwork region-tinted on pale glass and mixes it
        /// toward white on dark glass so normal compositing remains legible
        /// while the system energizes the glass on touch.
        struct SecurityPrint: Equatable {
            var whiteMix: Double
            /// Applies to the rosettes, watermark, and microprint only; the
            /// prominent entry stamp always uses normal compositing.
            var backgroundBlendMode: BlendMode

            func tint(_ regionTint: Color) -> Color {
                guard whiteMix > 0 else { return regionTint }
                return regionTint.mix(
                    with: .white,
                    by: whiteMix,
                    in: .perceptual,
                )
            }

            static let standard = SecurityPrint(
                whiteMix: 0,
                backgroundBlendMode: .normal,
            )
            static let dark = SecurityPrint(
                whiteMix: 0.65,
                backgroundBlendMode: .luminosity,
            )
        }

        /// How a card's day count changes when it updates with the card on screen
        /// — a passive sample lands, a manual day commits, a remote import
        /// arrives — and the number showing goes stale.
        ///
        /// The two halves are one token because they only work together: a
        /// `ContentTransition` morphs *only* inside an animation transaction, so
        /// the transition is inert without the animation, and Reduce Motion
        /// changes both (the digits stop rolling, and the curve becomes a plain
        /// fade). The animation also sweeps the ambient bar, which reads the same
        /// count, in the same beat.
        struct DayCountStyle: Equatable {
            /// How long the visible card surface holds its previous count before
            /// the animation and its coordinated haptic begin.
            var revealDelay: Duration
            /// Which way the count changes.
            var morph: Morph
            /// The animation that runs it.
            var animation: Animation

            enum Morph: Equatable {
                /// The digits roll from the old count to the new one.
                case rollingDigits
                /// The old count fades into the new one, with nothing travelling
                /// across the card.
                case crossFade
            }

            /// The count `Text`'s content transition. Takes the count because the
            /// roll reads it for a direction — a day added spins the digits up, a
            /// correction spins them down.
            func transition(days: Int) -> ContentTransition {
                switch morph {
                    case .rollingDigits: .numericText(value: Double(days))
                    case .crossFade: .opacity
                }
            }

            static let standard = DayCountStyle(
                revealDelay: .milliseconds(500),
                morph: .rollingDigits,
                // Long enough for the digits to read as rolling, short enough
                // that a card tapped mid-roll doesn't feel held up.
                animation: .smooth(duration: 0.36),
            )

            /// The Reduce-Motion pairing.
            static let reducedMotion = DayCountStyle(
                revealDelay: .milliseconds(500),
                morph: .crossFade,
                animation: .easeInOut(duration: 0.18),
            )
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
                cornerRadius: 20,
                padding: 22,
                contentSpacing: 16,
                progressBarHeight: 3,
                entryStamp: .standard(size: 76, showsArcText: true),
                // Fixed point size (not a Dynamic Type text style) for precise
                // control against the entry stamp: the longest common headline
                // names ("California" / "New York") fit, and any over-long one
                // tightens then scales via `minimumScaleFactor`.
                regionNameTypography: .init(
                    size: .fixed(38),
                    weight: .semibold,
                    design: .serif,
                ),
                regionNameTracking: -0.5,
                heroNumberTypography: .init(
                    size: .fixed(40),
                    weight: .bold,
                    design: .default,
                ),
                dayUnitTypography: .init(
                    size: .semantic(.title3),
                    weight: .medium,
                    design: .default,
                ),
                watermarkFontSize: 150,
                watermarkOffset: CGSize(width: 20, height: 12),
                regionShape: CardStyle.RegionShape(
                    watermark: .init(
                        center: CGPoint(x: 0.7, y: 0.57),
                        extent: CGSize(width: 0.72, height: 0.78),
                        scale: 0.88,
                        fillOpacity: 0.065,
                        stroke: .init(opacity: 0.13, width: 0.75),
                    ),
                    stamp: .init(
                        center: CGPoint(x: 0.5, y: 0.5),
                        extent: CGSize(width: 0.78, height: 0.78),
                        scale: 0.88,
                        fillOpacity: 0.68,
                        stroke: nil,
                    ),
                    securityBorder: .init(
                        inset: 9,
                        glyphSize: 8,
                        spacing: 11,
                        opacity: 0.1,
                    ),
                ),
                sheen: CardStyle.Sheen(
                    intensity: 0.24,
                    staticGlintIntensity: 0.07,
                    // A phone held upright: the glint sits near the lower edge
                    // instead of washing out the card's central content.
                    staticPose: .init(roll: 0, pitch: -1),
                ),
                rosette: CardStyle.Rosette(
                    wobble: 2,
                    lineWidth: 0.75,
                    primaryRingSpacing: 13.5,
                    secondaryRingSpacing: 9.5,
                ),
                glow: CardStyle.Shadow(opacity: 0.04, radius: 3),
                lift: CardStyle.Shadow(opacity: 0.11, radius: 18, offsetY: 8),
            ),
            compact: CardStyle(
                cornerRadius: 18,
                padding: 16,
                contentSpacing: 10,
                progressBarHeight: 3,
                entryStamp: .standard(size: 52, showsArcText: false),
                regionNameTypography: .init(
                    size: .semantic(.title3),
                    weight: .semibold,
                    design: .serif,
                ),
                regionNameTracking: 0,
                heroNumberTypography: .init(
                    size: .semantic(.title),
                    weight: .bold,
                    design: .default,
                ),
                dayUnitTypography: .init(
                    size: .semantic(.subheadline),
                    weight: .medium,
                    design: .default,
                ),
                watermarkFontSize: 96,
                watermarkOffset: CGSize(width: 12, height: 10),
                regionShape: nil,
                sheen: CardStyle.Sheen(
                    intensity: 0.16,
                    staticGlintIntensity: 0.06,
                    // Preserve the compact card's existing neutral treatment.
                    staticPose: .init(roll: 0, pitch: 0),
                ),
                rosette: CardStyle.Rosette(
                    wobble: 2,
                    lineWidth: 1,
                    primaryRingSpacing: 13,
                    secondaryRingSpacing: 11,
                ),
                glow: CardStyle.Shadow(opacity: 0.03, radius: 2),
                lift: CardStyle.Shadow(opacity: 0.08, radius: 10, offsetY: 4),
            ),
            watermarkOpacity: 0.06,
            glassTintOpacity: 0.04,
            nameOpacity: 0.9,
            rosetteFill: RosetteFill(primary: 0.055, secondary: 0.03),
            securityPrint: .standard,
            dayCount: .standard,
            constellation: .standard,
        )
    }
}

// MARK: - Calendar

extension WhereStylesheet {
    /// Style for the year calendar (`CalendarContentView`): `month` covers one month
    /// section, and the remaining properties cover the day cells shared across
    /// every month. Grouping the component's appearance here (rather than reading
    /// scattered generic tokens) keeps its full spec in one place and gives a
    /// future theme a single surface to reskin.
    struct CalendarStyle: Equatable {
        /// Vertical spacing between month sections in the scroll.
        var monthSpacing: CGFloat
        var month: MonthStyle
        /// Diameter of a region-presence dot in the month footer tally.
        var dotSize: CGFloat
        /// The subtle "stay" pill drawn behind contiguous same-region days.
        var regionBand: RegionBand
        /// Geometry and colors of a single day cell (the number chip, its region
        /// dots, the today/unresolved markers, and the evidence badge).
        var day: DayStyle

        /// Style for one month section: the header/grid/footer stack, its
        /// current-month highlight, and the tally footer.
        struct MonthStyle: Equatable {
            /// Spacing between the month header, day grid, and footer.
            var sectionSpacing: CGFloat
            /// Spacing between day cells in the grid (both axes).
            var gridSpacing: CGFloat
            var padding: CGFloat
            var cornerRadius: CGFloat
            var ruleSpacing: CGFloat
            var ruleOpacity: Double
            /// Card treatment for a past month — the plain wash + rim.
            var plain: Card
            /// Card treatment for the current month — a bluer accent wash and a
            /// heavier accent border so it stands out from the plain months.
            var current: Card
            /// Extra space below the footer's divider, so the tally rows don't
            /// butt right up against it.
            var footerDividerSpacing: CGFloat
            /// Spacing between footer rows.
            var footerSpacing: CGFloat
            /// Spacing within a footer row (dot ↔ label).
            var footerRowSpacing: CGFloat
            /// Opacity of an unfocused footer row while a region is focused.
            var unfocusedRowOpacity: Double

            /// One month card's fill + border, so the same treatment can be
            /// applied by state: `plain` for past months, `current` for
            /// the current one. The grid picks a `Card` and reads both from it,
            /// rather than ternary-ing each property against `isCurrentMonth`.
            struct Card: Equatable {
                /// Wash behind the month, so each reads as its own card.
                var fill: Color
                /// Border around the card (a touch darker than `fill`).
                var border: Color
                var borderWidth: CGFloat
                /// Base foreground inherited by the month's neutral primary and
                /// secondary text. Explicit semantic colors (today, unresolved,
                /// and region tints) still override it.
                var foreground: Color
            }
        }

        /// Geometry and colors of a single day cell: the number chip, its region
        /// dots beneath the number, the today/unresolved markers behind the
        /// number, and the evidence badge in the corner.
        struct DayStyle: Equatable {
            /// Min height (tap target) of a day cell — grows at accessibility
            /// Dynamic Type sizes.
            var minHeight: CGFloat
            /// Edge of the rounded day-number chip.
            var numberSize: CGFloat
            /// Vertical gap between the day number and its dots — small so the
            /// dots tuck up close beneath the date.
            var numberDotSpacing: CGFloat
            /// Diameter of a region-presence dot under a day number (a touch
            /// larger than the footer dots so days scan easily).
            var dotSize: CGFloat
            /// How far adjacent day dots overlap on a multi-region day, so
            /// several regions read as an overlapping cluster.
            var dotOverlap: CGFloat
            /// Background-colored rim on each dot of an overlapping cluster, so
            /// the overlap reads as distinct coins rather than a merged blob.
            var dotStrokeWidth: CGFloat
            /// Spacing between region dots on a single-region day (unused for the
            /// overlapping multi-region cluster).
            var contentSpacing: CGFloat
            /// Fill behind today's day number, and the color of that number.
            var todayMarker: Color
            var todayNumberColor: Color
            /// Fill behind a day that needs attention (unresolved), and its
            /// number.
            var unresolvedMarker: Color
            var unresolvedNumberColor: Color
            /// The small badge marking a day that carries evidence.
            var evidenceBadge: EvidenceBadge
        }

        /// The subtle region-tinted pill drawn behind a run of contiguous days
        /// sharing the same region(s), so a "stay" reads as one connected shape.
        /// The run's true ends get `cornerRadius`; where a run spills onto the
        /// next (or from the previous) week row, that edge gets the smaller
        /// `continuationRadius` to imply it carries on.
        struct RegionBand: Equatable {
            /// Opacity of the region tint — kept low so it sits behind the dots.
            var opacity: Double
            /// Height of the narrow enamel register behind each occupied day.
            var height: CGFloat
            /// Radius at a run's true start/end.
            var cornerRadius: CGFloat
            /// Radius at a week-boundary edge where the run continues.
            var continuationRadius: CGFloat
            /// Padding between the day content (number + dots) and the pill's
            /// top/bottom edges, so the pill doesn't butt against the dots.
            var verticalInset: CGFloat
            /// Lower-opacity fill plus a diagonal pattern for future days the
            /// user has planned but not yet recorded.
            var planned: Planned

            struct Planned: Equatable {
                var fillOpacity: Double
                var hatchOpacity: Double
                var hatchSpacing: CGFloat
                var hatchLineWidth: CGFloat
            }
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
        /// spacing/size tokens and inline colors in `CalendarContentView`.
        static let standard = CalendarStyle(
            monthSpacing: 16,
            month: MonthStyle(
                sectionSpacing: 8,
                gridSpacing: 6,
                padding: 16,
                cornerRadius: 14,
                ruleSpacing: 32,
                ruleOpacity: 0.028,
                plain: MonthStyle.Card(
                    fill: Color.primary.opacity(0.012),
                    border: Color.primary.opacity(0.14),
                    borderWidth: 0.75,
                    foreground: .primary,
                ),
                current: MonthStyle.Card(
                    fill: Color.primary.opacity(0.035),
                    border: Color.primary.opacity(0.32),
                    borderWidth: 1,
                    foreground: .primary,
                ),
                footerDividerSpacing: 8,
                footerSpacing: 4,
                footerRowSpacing: 6,
                unfocusedRowOpacity: 0.55,
            ),
            dotSize: 6,
            regionBand: RegionBand(
                opacity: 0.11,
                height: 10,
                cornerRadius: 5,
                continuationRadius: 1.5,
                verticalInset: 4,
                planned: RegionBand.Planned(
                    fillOpacity: 0.07,
                    hatchOpacity: 0.32,
                    hatchSpacing: 6,
                    hatchLineWidth: 1,
                ),
            ),
            day: DayStyle(
                minHeight: 44,
                numberSize: 26,
                numberDotSpacing: 0,
                dotSize: 8,
                dotOverlap: 2,
                dotStrokeWidth: 1.5,
                contentSpacing: 2,
                todayMarker: .accentColor,
                todayNumberColor: .white,
                unresolvedMarker: Color.red.opacity(0.15),
                unresolvedNumberColor: .red,
                evidenceBadge: EvidenceBadge(
                    iconSize: 8,
                    padding: 2,
                    offset: CGSize(width: 3, height: -2),
                ),
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
        var archive: Archive
        var compose: Compose

        struct Archive: Equatable {
            var cornerRadius: CGFloat
            var padding: CGFloat
            var rowSpacing: CGFloat
            var indexWidth: CGFloat
            var borderOpacity: Double
            var headerSealSize: CGFloat
            var eyebrowFont: Font
            var titleFont: Font
            var rowTitleFont: Font
            var indexFont: Font
        }

        struct Compose: Equatable {
            var sealSize: CGFloat
            var eyebrowFont: Font
            var titleFont: Font
        }

        static let standard = EvidenceStyle(
            previewCornerRadius: 22,
            pdfPreviewMinHeight: 420,
            loadingMinHeight: 200,
            archive: Archive(
                cornerRadius: 16,
                padding: 16,
                rowSpacing: 12,
                indexWidth: 30,
                borderOpacity: 0.16,
                headerSealSize: 48,
                eyebrowFont: .caption2.weight(.semibold),
                titleFont: .system(.title2, design: .serif).weight(.semibold),
                rowTitleFont: .system(.headline, design: .serif).weight(.semibold),
                indexFont: .caption2.weight(.semibold).monospacedDigit(),
            ),
            compose: Compose(
                sealSize: 44,
                eyebrowFont: .caption2.weight(.semibold),
                titleFont: .system(.title3, design: .serif).weight(.semibold),
            ),
        )
    }
}

// MARK: - Record preparation

extension WhereStylesheet {
    /// Style for composed-record preparation and its determinate export state.
    struct RecordPreparationStyle: Equatable {
        var cornerRadius: CGFloat
        var padding: CGFloat
        var sectionSpacing: CGFloat
        var sealSize: CGFloat
        var borderOpacity: Double
        var eyebrowFont: Font
        var titleFont: Font
        var figureFont: Font
        var statusFont: Font
        var metadataLabelFont: Font
        var metadataValueFont: Font

        static let standard = RecordPreparationStyle(
            cornerRadius: 22,
            padding: 22,
            sectionSpacing: 18,
            sealSize: 58,
            borderOpacity: 0.42,
            eyebrowFont: .caption2.weight(.semibold),
            titleFont: .system(.title2, design: .serif).weight(.semibold),
            figureFont: .subheadline.weight(.semibold).monospacedDigit(),
            statusFont: .headline,
            metadataLabelFont: .caption.weight(.medium),
            metadataValueFont: .subheadline,
        )
    }
}

// MARK: - Timeline

extension WhereStylesheet {
    /// Style for the presence timeline's calendar-proportional overview ribbon
    /// and the connected journey rows below it.
    struct TimelineStyle: Equatable {
        var overview: Overview
        var ribbon: Ribbon
        var rail: Rail
        var row: Row
        var planned: Planned

        struct Overview: Equatable {
            var spacing: CGFloat
            var padding: CGFloat
            var cornerRadius: CGFloat
            var background: Color
            var border: Color
            var borderWidth: CGFloat
            var yearFont: Font
            /// Keep the compact overview visible while the journey scrolls.
            var pinsToViewport: Bool
        }

        struct Ribbon: Equatable {
            var monthLabelSpacing: CGFloat
            var height: CGFloat
            var track: Color
            var border: Color
            var borderWidth: CGFloat
            var regionSpacing: CGFloat
            var regionLabelSpacing: CGFloat
            /// Split the overview into labeled region bands instead of
            /// relying on tint to distinguish a combined track.
            var separatesRegions: Bool
        }

        /// The route, marker, and space between the marker and row card.
        struct Rail: Equatable {
            var lineWidth: CGFloat
            var toCardSpacing: CGFloat
            var nodeSize: CGFloat
            var nodeSymbolFont: Font
            var nodeEmojiFont: Font
            var charmOffset: CGSize
            var nodeFillOpacity: Double
            var nodeStrokeWidth: CGFloat
        }

        /// Spacing and surface treatment within each journey row.
        struct Row: Equatable {
            var spacing: CGFloat
            var labelSpacing: CGFloat
            var gap: CGFloat
            /// Every row reserves room for its content, then adds this full-year
            /// scale multiplied by `stintDays / daysInYear`.
            var baseHeight: CGFloat
            var yearScaleHeight: CGFloat
            var horizontalPadding: CGFloat
            var verticalPadding: CGFloat
            var cornerRadius: CGFloat
            var fillOpacity: Double
            var borderOpacity: Double
            var borderWidth: CGFloat
            var countHorizontalPadding: CGFloat
            var countVerticalPadding: CGFloat
            var countFillOpacity: Double
            var durationScaleHeight: CGFloat
            /// Accessibility Dynamic Type stacks the count beneath the labels.
            var stacksDayCount: Bool
        }

        /// The future planned-stay treatment appended after recorded journey
        /// rows. Its lighter fill and hatch distinguish intent from history.
        struct Planned: Equatable {
            var fillOpacity: Double
            var borderOpacity: Double
            var hatchOpacity: Double
            var hatchSpacing: CGFloat
            var hatchLineWidth: CGFloat
            var labelOpacity: Double
        }

        static let standard = TimelineStyle(
            overview: Overview(
                spacing: 12,
                padding: 16,
                cornerRadius: 14,
                background: Color.primary.opacity(0.012),
                border: Color.primary.opacity(0.14),
                borderWidth: 0.75,
                yearFont: .system(.title2, design: .serif).bold(),
                pinsToViewport: true,
            ),
            ribbon: Ribbon(
                monthLabelSpacing: 6,
                height: 10,
                track: Color.primary.opacity(0.055),
                border: Color.primary.opacity(0.16),
                borderWidth: 0.75,
                regionSpacing: 8,
                regionLabelSpacing: 4,
                separatesRegions: false,
            ),
            rail: Rail(
                lineWidth: 1.5,
                toCardSpacing: 10,
                nodeSize: 28,
                nodeSymbolFont: .system(size: 12, weight: .semibold),
                nodeEmojiFont: .system(size: 9),
                charmOffset: CGSize(width: 9, height: 9),
                nodeFillOpacity: 0.07,
                nodeStrokeWidth: 1,
            ),
            row: Row(
                spacing: 12,
                labelSpacing: 3,
                gap: 6,
                baseHeight: 68,
                yearScaleHeight: 0,
                horizontalPadding: 14,
                verticalPadding: 12,
                cornerRadius: 12,
                fillOpacity: 0,
                borderOpacity: 0.14,
                borderWidth: 0.75,
                countHorizontalPadding: 0,
                countVerticalPadding: 0,
                countFillOpacity: 0,
                durationScaleHeight: 3,
                stacksDayCount: false,
            ),
            planned: Planned(
                fillOpacity: 0.035,
                borderOpacity: 0.14,
                hatchOpacity: 0.16,
                hatchSpacing: 8,
                hatchLineWidth: 1,
                labelOpacity: 0.7,
            ),
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
        /// Editorial headline used for the first-run promise and ledger covers.
        var editorialTitle: Font
        /// Precise tabular figures used where counts are the primary content.
        var instrumentNumber: Font
        static let standard = Typography(
            onboardingIcon: .system(size: 34, weight: .regular),
            editorialTitle: .system(.largeTitle, design: .serif).bold(),
            instrumentNumber: .system(.largeTitle, design: .default).bold().monospacedDigit(),
        )
    }
}

// MARK: - Lightweight records

extension WhereStylesheet {
    /// The inexpensive paper record used by home-screen widgets. WidgetKit owns
    /// the outer shape; these tokens keep the extension, snapshots, and Settings
    /// examples on the same hierarchy without introducing card effects.
    struct HomeWidgetStyle: Equatable {
        var headerSealSize: CGFloat
        var headerSpacing: CGFloat
        var contentSpacing: CGFloat
        var rowSpacing: CGFloat
        var routeMarkerSize: CGFloat
        var routeSymbolPointSize: CGFloat
        var ruleHeight: CGFloat
        var ruleOpacity: Double
        var borderOpacity: Double
        var eyebrowFont: Font
        var dateFont: Font
        var heroNameFont: Font
        var rowNameFont: Font
        var totalNumberFont: Font
        var charmFont: Font
        var stacksHeader: Bool

        static let standard = HomeWidgetStyle(
            headerSealSize: 20,
            headerSpacing: 7,
            contentSpacing: 10,
            rowSpacing: 6,
            routeMarkerSize: 22,
            routeSymbolPointSize: 10,
            ruleHeight: 1,
            ruleOpacity: 0.34,
            borderOpacity: 0.14,
            eyebrowFont: .caption2.weight(.semibold),
            dateFont: .caption2.weight(.medium).monospacedDigit(),
            heroNameFont: .system(.title2, design: .serif).weight(.semibold),
            rowNameFont: .system(.caption, design: .serif).weight(.semibold),
            totalNumberFont: .system(.body, design: .default, weight: .bold).monospacedDigit(),
            charmFont: .caption2,
            stacksHeader: false,
        )
    }

    /// A compact archival surface for Siri, Spotlight, and Shortcuts results.
    /// It shares the house materials with widgets while owning roomier snippet
    /// geometry and an accessibility restack.
    struct RecordSnippetStyle: Equatable {
        var cornerRadius: CGFloat
        var padding: CGFloat
        var contentSpacing: CGFloat
        var sealSize: CGFloat
        var routeMarkerSize: CGFloat
        var routeSymbolPointSize: CGFloat
        var borderOpacity: Double
        var ruleOpacity: Double
        var titleFont: Font
        var numberFont: Font
        var captionFont: Font
        var charmFont: Font
        var stacksHero: Bool

        static let standard = RecordSnippetStyle(
            cornerRadius: 18,
            padding: 16,
            contentSpacing: 12,
            sealSize: 28,
            routeMarkerSize: 28,
            routeSymbolPointSize: 12,
            borderOpacity: 0.16,
            ruleOpacity: 0.22,
            titleFont: .system(.title3, design: .serif).weight(.semibold),
            numberFont: .system(.largeTitle, design: .default).bold().monospacedDigit(),
            captionFont: .subheadline,
            charmFont: .caption2,
            stacksHero: false,
        )
    }
}

// MARK: - Elsewhere entry card

extension WhereStylesheet {
    /// The compact entry card at the bottom of the Locations tab that links to
    /// the Elsewhere list. A small self-contained group (it doesn't borrow the
    /// passport `CardStyle`, which is a different, heavier component).
    struct ElsewhereCardStyle: Equatable {
        /// Corner radius of the glass card.
        var cornerRadius: CGFloat
        /// Inset of the card's contents from its edge.
        var padding: CGFloat
        /// Point size of the leading globe glyph.
        var iconPointSize: CGFloat

        static let standard = ElsewhereCardStyle(
            cornerRadius: 22,
            padding: 18,
            iconPointSize: 28,
        )
    }
}

// MARK: - Motion

extension WhereStylesheet {
    /// The small timing vocabulary shared by components. A component owns the
    /// transition these timings drive; this group only keeps the app's physical
    /// cadence consistent.
    struct Motion: Equatable {
        var response: Animation
        var settle: Animation
        var reveal: Animation
        var ceremonial: Animation
        var reduced: Animation
        /// One-shot fade for incidental appearance (e.g. the launch caption).
        var captionFade: Animation
        /// The reusable staged entrance used by marketing-style screens.
        var staggeredReveal: StaggeredReveal

        struct StaggeredReveal: Equatable {
            var animation: Animation
            var verticalOffset: CGFloat
            var delay: TimeInterval

            func presentation(
                isRevealed: Bool,
                motionIsStatic: Bool,
                order: Int,
            ) -> Presentation {
                guard !motionIsStatic else { return .visible }
                return Presentation(
                    opacity: isRevealed ? 1 : 0,
                    verticalOffset: isRevealed ? 0 : verticalOffset,
                    animation: animation.delay(Double(min(2, max(0, order))) * delay),
                )
            }

            struct Presentation: Equatable {
                var opacity: Double
                var verticalOffset: CGFloat
                var animation: Animation?

                static let visible = Presentation(
                    opacity: 1,
                    verticalOffset: 0,
                    animation: nil,
                )
            }
        }

        static let standard = Motion(
            response: .smooth(duration: 0.18),
            settle: .smooth(duration: 0.36),
            reveal: .easeOut(duration: 0.42),
            ceremonial: .smooth(duration: 0.62),
            reduced: .easeInOut(duration: 0.18),
            captionFade: .easeOut(duration: 0.28),
            staggeredReveal: StaggeredReveal(
                animation: .easeOut(duration: 0.42),
                verticalOffset: 10,
                delay: 0.05,
            ),
        )
    }
}

// MARK: - Launch

extension WhereStylesheet {
    /// Timings for the launch splash (`LaunchSplashView`) and how long it lingers
    /// before the app reveals. Kept as tokens so the durations aren't hardcoded
    /// across the splash view and the `LifecycleContainer` seam.
    struct LaunchStyle: Equatable {
        /// The least time the splash stays up before the app reveals, passed to
        /// `LifecycleContainer`. Optimized launches finish near-instantly, so
        /// without this the splash (and its reveal) would flash past unseen.
        var minimumSplashDuration: Duration
        /// How long the splash lingers before the "getting things ready" caption
        /// fades in, so a normal fast launch never flashes it.
        var captionDelay: Duration
        var revealAnimation: Animation
        var reducedRevealAnimation: Animation
        var sealSize: CGFloat
        var coverInset: CGFloat
        var coverCornerRadius: CGFloat

        static let standard = LaunchStyle(
            minimumSplashDuration: .milliseconds(800),
            captionDelay: .milliseconds(1200),
            revealAnimation: .smooth(duration: 0.62),
            reducedRevealAnimation: .easeInOut(duration: 0.18),
            sealSize: 132,
            coverInset: 22,
            coverCornerRadius: 28,
        )
    }
}

// MARK: - Onboarding

extension WhereStylesheet {
    /// The first-run flow's quiet document treatment and directional phase motion.
    struct OnboardingStyle: Equatable {
        var brandMarkSize: CGFloat
        var primaryButtonCornerRadius: CGFloat
        var primaryButtonVerticalPadding: CGFloat
        var primaryButtonPressedScale: CGFloat
        var motion: MotionMode

        enum MotionMode: Equatable {
            case standard
            case reduced

            var animation: Animation {
                switch self {
                    case .standard: .smooth(duration: 0.4)
                    case .reduced: .easeInOut(duration: 0.18)
                }
            }

            func transition(isForward: Bool) -> AnyTransition {
                switch self {
                    case .standard:
                        .asymmetric(
                            insertion: .move(edge: isForward ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: isForward ? .leading : .trailing)
                                .combined(with: .opacity),
                        )
                    case .reduced:
                        .opacity
                }
            }
        }

        static let standard = OnboardingStyle(
            brandMarkSize: 72,
            primaryButtonCornerRadius: 18,
            primaryButtonVerticalPadding: 14,
            primaryButtonPressedScale: 0.99,
            motion: .standard,
        )
    }
}

// MARK: - Year

extension WhereStylesheet {
    /// Motion for switching between the calendar and timeline lenses.
    struct YearStyle: Equatable {
        var motion: MotionMode
        var cover: Cover

        struct Cover: Equatable {
            var cornerRadius: CGFloat
            var horizontalPadding: CGFloat
            var verticalPadding: CGFloat
            var minimumHeight: CGFloat
            var sealSize: CGFloat
            var titleFont: Font
            var eyebrowFont: Font
            var figureNumberFont: Font
            var figureEditorialFont: Font
            var figureLabelFont: Font
            var figureSpacing: CGFloat
            var borderOpacity: Double
            var borderWidth: CGFloat
            var actionHorizontalPadding: CGFloat
            var actionVerticalPadding: CGFloat
        }

        enum MotionMode: Equatable {
            case standard
            case reduced

            var contentAnimation: Animation {
                switch self {
                    case .standard: .smooth(duration: 0.36)
                    case .reduced: .easeInOut(duration: 0.18)
                }
            }

            var contentTransition: AnyTransition {
                switch self {
                    case .standard:
                        .opacity.combined(with: .scale(scale: 0.985))
                    case .reduced:
                        .opacity
                }
            }
        }

        static let standard = YearStyle(
            motion: .standard,
            cover: Cover(
                cornerRadius: 28,
                horizontalPadding: 26,
                verticalPadding: 30,
                minimumHeight: 570,
                sealSize: 72,
                titleFont: .system(.largeTitle, design: .serif).weight(.semibold),
                eyebrowFont: .caption2.weight(.semibold),
                figureNumberFont: .title2.weight(.semibold).monospacedDigit(),
                figureEditorialFont: .system(.title2, design: .serif).weight(.semibold),
                figureLabelFont: .caption.weight(.medium),
                figureSpacing: 18,
                borderOpacity: 0.32,
                borderWidth: 0.75,
                actionHorizontalPadding: 18,
                actionVerticalPadding: 11,
            ),
        )
    }
}

// MARK: - Settings

extension WhereStylesheet {
    /// Appearance + motion for the Settings list. Geometry only — per-section
    /// icon colors live on `SettingsDestination`, and the flash tint (accent) /
    /// restored grouped-row background (a system role) / white-or-black glyph
    /// stay inline, per the "no adaptive/accent colors in the sheet" rule.
    struct SettingsStyle: Equatable {
        /// Edge of the colored rounded-square icon chip on each top-level row.
        var iconSize: CGFloat
        /// Corner radius of that chip (continuous corners for the squircle look).
        var iconCornerRadius: CGFloat
        /// Point size of the SF Symbol glyph inside the chip.
        var iconSymbolSize: CGFloat
        /// The animation used for both the scroll and the flash fade.
        var flashAnimation: Animation
        /// How long the row stays highlighted before it fades back.
        var flashDuration: Duration
        /// A short wait after the push lands before scrolling, so the row is laid
        /// out and the scroll reliably lands on it.
        var scrollSettleDelay: Duration

        static let standard = SettingsStyle(
            iconSize: 29,
            iconCornerRadius: 7,
            iconSymbolSize: 15,
            flashAnimation: .easeInOut(duration: 0.4),
            flashDuration: .seconds(1),
            scrollSettleDelay: .milliseconds(350),
        )
    }
}

// MARK: - Feature discovery

extension WhereStylesheet {
    /// Appearance for the Siri conversation cards and the miniature widget
    /// surfaces in Settings' feature explorer.
    struct FeatureDiscoveryStyle: Equatable {
        var marketingHeader: MarketingHeader
        var marketingPanel: MarketingPanel
        var backgroundPattern: BackgroundPattern
        var estimatedTime: EstimatedTime
        var siri: Siri
        var widgets: Widgets

        struct MarketingHeader: Equatable {
            var sealSize: CGFloat
            var featureBadgeSize: CGFloat
            var featureSymbolPointSize: CGFloat
            var contentMaxWidth: CGFloat
            var spacing: CGFloat
            var verticalPadding: CGFloat
        }

        struct MarketingPanel: Equatable {
            var cornerRadius: CGFloat
            var maxWidth: CGFloat
            var padding: CGFloat
            var contentSpacing: CGFloat
            var rowVerticalInset: CGFloat
            var borderOpacity: Double
        }

        struct BackgroundPattern: Equatable {
            var contourSpacing: CGFloat
            var primaryDistortion: CGFloat
            var secondaryDistortion: CGFloat
            var horizontalScale: CGFloat
            var centerXRatio: CGFloat
            var centerYRatio: CGFloat
            var phaseStep: CGFloat
            var lineWidth: CGFloat
            var opacity: Double
        }

        struct EstimatedTime: Equatable {
            var timelineHeight: CGFloat
            var timelineSpacing: CGFloat
            var calculationSpacing: CGFloat
            var segmentCornerRadius: CGFloat
            var legendDotSize: CGFloat
        }

        struct Siri: Equatable {
            var card: Card
            var bubble: Bubble
            var speakerIcon: SpeakerIcon
            var accent: Color

            struct Card: Equatable {
                var cornerRadius: CGFloat
                var maxWidth: CGFloat
                var padding: CGFloat
                var spacing: CGFloat
                var rowVerticalInset: CGFloat
            }

            struct Bubble: Equatable {
                var cornerRadius: CGFloat
                var horizontalPadding: CGFloat
                var verticalPadding: CGFloat
                var indent: CGFloat
            }

            struct SpeakerIcon: Equatable {
                var containerSize: CGFloat
                var symbolPointSize: CGFloat
            }
        }

        struct Widgets: Equatable {
            var device: Device
            var frame: Frame
            var wallpapers: Wallpapers
            var lockWidgetHeight: CGFloat

            struct Device: Equatable {
                var cornerRadius: CGFloat
                var contentMaxWidth: CGFloat
                var regularContentWidth: CGFloat
                var dynamicTypeLimit: DynamicTypeSize
                var padding: CGFloat
                var spacing: CGFloat
            }

            struct Frame: Equatable {
                var cornerRadius: CGFloat
                var padding: CGFloat
            }

            struct Wallpapers: Equatable {
                var home: Gradient
                var lock: Gradient

                struct Gradient: Equatable {
                    var top: Color
                    var bottom: Color
                }
            }

            func contentWidth(in containerWidth: CGFloat) -> CGFloat {
                let availableWidth = max(0, containerWidth - device.padding * 2)
                if availableWidth > device.contentMaxWidth {
                    return device.regularContentWidth
                }
                return min(availableWidth, device.contentMaxWidth)
            }
        }

        static let standard = FeatureDiscoveryStyle(
            marketingHeader: MarketingHeader(
                sealSize: 76,
                featureBadgeSize: 28,
                featureSymbolPointSize: 13,
                contentMaxWidth: 560,
                spacing: 14,
                verticalPadding: 24,
            ),
            marketingPanel: MarketingPanel(
                cornerRadius: 16,
                maxWidth: 680,
                padding: 16,
                contentSpacing: 12,
                rowVerticalInset: 6,
                borderOpacity: 0.16,
            ),
            backgroundPattern: BackgroundPattern(
                contourSpacing: 30,
                primaryDistortion: 13,
                secondaryDistortion: 6,
                horizontalScale: 1.22,
                centerXRatio: 0.18,
                centerYRatio: 0.46,
                phaseStep: 0.31,
                lineWidth: 0.9,
                opacity: 0.08,
            ),
            estimatedTime: EstimatedTime(
                timelineHeight: 18,
                timelineSpacing: 3,
                calculationSpacing: 8,
                segmentCornerRadius: 5,
                legendDotSize: 10,
            ),
            siri: Siri(
                card: Siri.Card(
                    cornerRadius: 16,
                    maxWidth: 680,
                    padding: 16,
                    spacing: 12,
                    rowVerticalInset: 6,
                ),
                bubble: Siri.Bubble(
                    cornerRadius: 16,
                    horizontalPadding: 12,
                    verticalPadding: 10,
                    indent: 34,
                ),
                speakerIcon: Siri.SpeakerIcon(
                    containerSize: 28,
                    symbolPointSize: 12,
                ),
                accent: Palette.Brand.standard.mineral,
            ),
            widgets: Widgets(
                device: Widgets.Device(
                    cornerRadius: 28,
                    contentMaxWidth: 560,
                    regularContentWidth: 320,
                    dynamicTypeLimit: .xLarge,
                    padding: 14,
                    spacing: 12,
                ),
                frame: Widgets.Frame(
                    cornerRadius: 18,
                    padding: 12,
                ),
                wallpapers: Widgets.Wallpapers(
                    home: Widgets.Wallpapers.Gradient(
                        top: Palette.Brand.standard.canvas,
                        bottom: Palette.Brand.standard.raisedPaper,
                    ),
                    lock: Widgets.Wallpapers.Gradient(top: .purple, bottom: .blue),
                ),
                lockWidgetHeight: 76,
            ),
        )
    }
}

// MARK: - Passport card

extension WhereStylesheet {
    /// Appearance for compact passport statements in Settings.
    struct PassportCardStyle: Equatable {
        var cornerRadius: CGFloat
        var padding: CGFloat
        var contentSpacing: CGFloat
        var titleFont: Font
        var detailFont: Font
        var seal: Seal
        var rosette: Rosette
        var reflectiveSurface: ReflectiveSurface
        var glassTintOpacity: Double
        var accentGlow: Shadow
        var liftShadow: Shadow

        struct Seal: Equatable {
            var size: CGFloat
            var rotationDegrees: Double
            var outerLineWidth: CGFloat
            var innerLineWidth: CGFloat
            var innerInset: CGFloat
            var dashLength: CGFloat
            var dashSpacing: CGFloat
            var symbolFont: Font
        }

        struct Rosette: Equatable {
            var wobble: CGFloat
            var lineWidth: CGFloat
            var primaryRingSpacing: CGFloat
            var secondaryRingSpacing: CGFloat
            var primaryOpacity: Double
            var secondaryOpacity: Double
        }

        struct ReflectiveSurface: Equatable {
            var backgroundTop: Color
            var backgroundBottom: Color
            var accent: Color
            var glowOpacity: Double
            var intensity: Double
            var staticGlintIntensity: Double
            var staticPose: Pose

            struct Pose: Equatable {
                var roll: Double
                var pitch: Double
            }
        }

        struct Shadow: Equatable {
            var opacity: Double
            var radius: CGFloat
            var offsetY: CGFloat = 0
        }

        static let standard = PassportCardStyle(
            cornerRadius: 20,
            padding: 16,
            contentSpacing: 12,
            titleFont: .headline,
            detailFont: .subheadline,
            seal: Seal(
                size: 52,
                rotationDegrees: -8,
                outerLineWidth: 2,
                innerLineWidth: 1,
                innerInset: 7,
                dashLength: 3,
                dashSpacing: 3,
                symbolFont: .title3,
            ),
            rosette: Rosette(
                wobble: 5,
                lineWidth: 0.75,
                primaryRingSpacing: 10,
                secondaryRingSpacing: 16,
                primaryOpacity: 0.06,
                secondaryOpacity: 0.035,
            ),
            reflectiveSurface: ReflectiveSurface(
                backgroundTop: Color(red: 0.07, green: 0.14, blue: 0.25),
                backgroundBottom: Color(red: 0.025, green: 0.055, blue: 0.11),
                accent: Color(red: 0.72, green: 0.56, blue: 0.27),
                glowOpacity: 0.035,
                intensity: 0.1,
                staticGlintIntensity: 0.06,
                staticPose: .init(roll: 0.3, pitch: -0.15),
            ),
            glassTintOpacity: 0.03,
            accentGlow: Shadow(opacity: 0.05, radius: 4),
            liftShadow: Shadow(opacity: 0.1, radius: 9, offsetY: 4),
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
        var brand: Brand
        var primary: Primary
        var splash: Splash
        var onboarding: Onboarding

        /// Current-appearance house colors. They are resolved by Broadway so
        /// views consume semantic ink and paper roles rather than raw hues.
        struct Brand: Equatable {
            var canvas: Color
            var raisedPaper: Color
            var ink: Color
            var midnight: Color
            var onMidnight: Color
            var brass: Color
            var oxblood: Color
            var forest: Color
            var mineral: Color

            static let standard = Brand(
                canvas: Color(red: 0.965, green: 0.95, blue: 0.91),
                raisedPaper: Color(red: 0.99, green: 0.98, blue: 0.95),
                ink: Color(red: 0.08, green: 0.09, blue: 0.1),
                midnight: Color(red: 0.055, green: 0.105, blue: 0.18),
                onMidnight: Color(red: 0.99, green: 0.98, blue: 0.95),
                brass: Color(red: 0.62, green: 0.46, blue: 0.2),
                oxblood: Color(red: 0.42, green: 0.18, blue: 0.23),
                forest: Color(red: 0.18, green: 0.34, blue: 0.27),
                mineral: Color(red: 0.28, green: 0.4, blue: 0.48),
            )

            static let dark = Brand(
                canvas: Color(red: 0.045, green: 0.052, blue: 0.065),
                raisedPaper: Color(red: 0.085, green: 0.1, blue: 0.125),
                ink: Color(red: 0.94, green: 0.91, blue: 0.84),
                midnight: Color(red: 0.055, green: 0.105, blue: 0.18),
                onMidnight: Color(red: 0.96, green: 0.94, blue: 0.89),
                brass: Color(red: 0.7, green: 0.56, blue: 0.3),
                oxblood: Color(red: 0.58, green: 0.32, blue: 0.37),
                forest: Color(red: 0.3, green: 0.49, blue: 0.39),
                mineral: Color(red: 0.38, green: 0.53, blue: 0.62),
            )
        }

        /// The Primary tab's deep "passport cover" backdrop (top → bottom).
        struct Primary: Equatable {
            var backgroundTop: Color
            var backgroundBottom: Color
        }

        /// The launch splash: an adaptive backdrop (follows light/dark) with a
        /// subtle radial vignette and a brand-tinted icon glow / radar. The
        /// reassurance caption uses inline adaptive roles (`.primary` /
        /// `.secondary`), per the "adaptive system roles stay inline" rule.
        struct Splash: Equatable {
            var background: Color
            var vignetteCenter: Color
            var vignetteEdge: Color
            var iconGlow: Color
        }

        /// The onboarding backdrop (top → bottom).
        struct Onboarding: Equatable {
            var backgroundTop: Color
            var backgroundBottom: Color
        }

        static let standard = Palette(
            brand: .standard,
            primary: Primary(
                backgroundTop: Color(red: 0.07, green: 0.08, blue: 0.13),
                backgroundBottom: Color(red: 0.02, green: 0.02, blue: 0.05),
            ),
            splash: Splash(
                // Adaptive so the splash follows the app's light/dark mode. The
                // vignette runs from a slightly-elevated center to the base
                // background, giving a soft "spotlight" in dark and a near-flat
                // clean backdrop in light (the two are close there).
                background: Color(.systemBackground),
                vignetteCenter: Color(.secondarySystemBackground),
                vignetteEdge: Color(.systemBackground),
                iconGlow: .accentColor,
            ),
            onboarding: Onboarding(
                backgroundTop: Brand.standard.raisedPaper,
                backgroundBottom: Brand.standard.canvas,
            ),
        )

        static let dark = Palette(
            brand: .dark,
            primary: Primary(
                backgroundTop: Color(red: 0.055, green: 0.065, blue: 0.09),
                backgroundBottom: Brand.dark.canvas,
            ),
            splash: Splash(
                background: Brand.dark.canvas,
                vignetteCenter: Brand.dark.raisedPaper,
                vignetteEdge: Brand.dark.canvas,
                iconGlow: Brand.dark.mineral,
            ),
            onboarding: Onboarding(
                backgroundTop: Brand.dark.raisedPaper,
                backgroundBottom: Brand.dark.canvas,
            ),
        )

        static let glass = Palette(
            brand: Brand(
                canvas: Color(red: 0.94, green: 0.955, blue: 0.97),
                raisedPaper: Color(red: 0.985, green: 0.99, blue: 1),
                ink: Color(red: 0.08, green: 0.1, blue: 0.13),
                midnight: Color(red: 0.9, green: 0.925, blue: 0.95),
                onMidnight: Color(red: 0.08, green: 0.1, blue: 0.13),
                brass: Color(red: 0.3, green: 0.43, blue: 0.54),
                oxblood: Color(red: 0.46, green: 0.25, blue: 0.31),
                forest: Color(red: 0.2, green: 0.38, blue: 0.31),
                mineral: Color(red: 0.25, green: 0.43, blue: 0.56),
            ),
            primary: Primary(
                backgroundTop: Color(red: 0.97, green: 0.98, blue: 0.99),
                backgroundBottom: Color(red: 0.91, green: 0.94, blue: 0.97),
            ),
            splash: Splash(
                background: Color(red: 0.94, green: 0.955, blue: 0.97),
                vignetteCenter: Color(red: 0.99, green: 0.995, blue: 1),
                vignetteEdge: Color(red: 0.91, green: 0.935, blue: 0.96),
                iconGlow: Color(red: 0.25, green: 0.43, blue: 0.56),
            ),
            onboarding: Onboarding(
                backgroundTop: Color(red: 0.985, green: 0.99, blue: 1),
                backgroundBottom: Color(red: 0.91, green: 0.94, blue: 0.97),
            ),
        )

        static let glassDark = Palette(
            brand: Brand(
                canvas: Color(red: 0.055, green: 0.065, blue: 0.08),
                raisedPaper: Color(red: 0.105, green: 0.12, blue: 0.145),
                ink: Color(red: 0.93, green: 0.95, blue: 0.98),
                midnight: Color(red: 0.075, green: 0.09, blue: 0.115),
                onMidnight: Color(red: 0.93, green: 0.95, blue: 0.98),
                brass: Color(red: 0.48, green: 0.63, blue: 0.74),
                oxblood: Color(red: 0.64, green: 0.39, blue: 0.45),
                forest: Color(red: 0.36, green: 0.56, blue: 0.47),
                mineral: Color(red: 0.46, green: 0.64, blue: 0.76),
            ),
            primary: Primary(
                backgroundTop: Color(red: 0.09, green: 0.105, blue: 0.13),
                backgroundBottom: Color(red: 0.045, green: 0.055, blue: 0.07),
            ),
            splash: Splash(
                background: Color(red: 0.055, green: 0.065, blue: 0.08),
                vignetteCenter: Color(red: 0.105, green: 0.12, blue: 0.145),
                vignetteEdge: Color(red: 0.045, green: 0.055, blue: 0.07),
                iconGlow: Color(red: 0.46, green: 0.64, blue: 0.76),
            ),
            onboarding: Onboarding(
                backgroundTop: Color(red: 0.105, green: 0.12, blue: 0.145),
                backgroundBottom: Color(red: 0.045, green: 0.055, blue: 0.07),
            ),
        )
    }
}

// MARK: - Themes

/// The Where app's Broadway themes, seeded at the root by `whereBroadwayRoot()`.
/// Carries the selected presentation identity independently from system traits.
/// Standard maps to Quiet Glass while Alternate maps to the editorial Folio.
enum WhereThemes {
    static func current(theme: WhereTheme) -> BThemes {
        var themes = BThemes()
        themes[WhereTheme.self] = theme
        return themes
    }
}

extension WhereTheme: BTheme {
    public static let defaultValue = WhereTheme.standard
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
    /// directly — it already gets it through `WhereUI`, and a second copy would
    /// split Broadway's type-keyed environment metadata (see the root
    /// `AGENTS.md` "Targets" note).
    ///
    /// Also seeds `\.regionStyles` so descendants resolve per-region looks
    /// (`region` cards, calendar dots, widgets, snippets) from one place. The app
    /// passes `WhereSession`'s live resolver, the widget process one built from
    /// its `WidgetSnapshot`, and intents one from their services; the default
    /// empty resolver yields fallback looks (previews, the region-map viewer).
    /// The root also owns and injects the region-outline `Path` cache so cards
    /// share render artifacts without a process-global UI singleton.
    public func whereBroadwayRoot(
        theme: WhereTheme = .standard,
        regionStyles: RegionStyleResolver = .default,
    ) -> some View {
        modifier(WhereBroadwayRootModifier(theme: theme, regionStyles: regionStyles))
    }
}

/// Owns UI render resources once per Where root and injects them alongside the
/// Broadway/design context. Keeping the path cache here shares it across cards
/// without introducing a process-global UI singleton.
private struct WhereBroadwayRootModifier: ViewModifier {
    let theme: WhereTheme
    let regionStyles: RegionStyleResolver
    @State private var regionOutlinePathCache = RegionOutlinePathCache()

    func body(content: Content) -> some View {
        content
            .broadwayRoot(themes: WhereThemes.current(theme: theme))
            .environment(\.regionStyles, regionStyles)
            .environment(\.regionOutlinePathCache, regionOutlinePathCache)
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
