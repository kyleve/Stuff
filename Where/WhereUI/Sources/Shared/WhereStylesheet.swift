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
    var card = CardStyles.standard
    var locationCardStack = LocationCardStackStyle.standard
    var locationWelcome = LocationWelcomeStyle.standard
    var calendar = CalendarStyle.standard
    var appIcon = AppIconStyle.standard
    var timeline = TimelineStyle.standard
    var regionMap = RegionMapStyle.standard
    var regionPicker = RegionPickerStyle.standard
    var evidence = EvidenceStyle.standard
    var elsewhereCard = ElsewhereCardStyle.standard
    var locationForecast = LocationForecastStyle.standard
    var palette = Palette.standard
    var motion = Motion.standard
    var launch = LaunchStyle.standard
    var typography = Typography.standard
    var settings = SettingsStyle.standard
    var featureDiscovery = FeatureDiscoveryStyle.standard
    var passportSeal = PassportSealStyle.standard
    var privacyPassportCard = PrivacyPassportCardStyle.standard
    var openSourceStamp = StampBannerStyle.openSource
    var plannedStayWarningStamp = StampBannerStyle.plannedStayWarning
    var developerOverlay = DeveloperOverlayStyle.standard

    init() {}

    init(context: SlicingContext) throws {
        // Start from the fixed scale (property defaults), then adjust the slice
        // of tokens that should react to the current traits. Everything else
        // stays constant, so a default/system context reproduces `default`.
        let traits = context.traits
        theme = context.themes[WhereTheme.self]

        // Grow day-grid tap targets at accessibility Dynamic Type sizes.
        if traits.contentSizeCategory.isAccessibilitySize {
            calendar.day.minHeight = 56
            timeline.overview.pinsToViewport = false
            timeline.row.stacksDayCount = true
            featureDiscovery.siri.bubble.indent = 0
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
            privacyPassportCard.disclosure.fillOpacity = 0.16
        }

        if traits.accessibility.isDarkerSystemColorsEnabled {
            locationForecast.ink = .increasedContrast
            openSourceStamp.ink = .increasedContrast
            plannedStayWarningStamp.ink = .increasedContrast
        }

        // Reduce Motion stops the cards' day count rolling its digits; it
        // crossfades to the new number instead.
        if traits.accessibility.isReduceMotionEnabled {
            card.dayCount = .reducedMotion
            locationCardStack.overtake = .reducedMotion
            locationWelcome.motion = .reduced
            developerOverlay.menu.motion = .reduced
        }

        // Pale, luminosity-only ink lifts the background security print off
        // dark glass without changing its hue or saturation on touch.
        if traits.mode == .dark {
            card.securityPrint = .dark
            featureDiscovery.siri.accent = Color(white: 0.42)
        }
    }

    /// The fixed token set: the fallback used off the `View` tree (layout
    /// helpers, tests) and when no Broadway root has seeded a context.
    static let `default` = WhereStylesheet()
}

// MARK: - Location welcome

extension WhereStylesheet {
    /// Appearance and motion for the live-region welcome over Locations.
    struct LocationWelcomeStyle: Equatable {
        var maxWidth: CGFloat
        var cornerRadius: CGFloat
        var padding: CGFloat
        var contentSpacing: CGFloat
        var paperOpacity: Double
        var scrimOpacity: Double
        var glassTintOpacity: Double
        var glow: Shadow
        var lift: Shadow
        var close: Close
        var motion: Motion

        struct Shadow: Equatable {
            var opacity: Double
            var radius: CGFloat
            var offsetY: CGFloat = 0
        }

        struct Close: Equatable {
            var offset: CGSize
            var tintOpacity: Double
            var glow: Shadow
            var lift: Shadow
        }

        struct Motion: Equatable {
            var animation: Animation
            var scale: CGFloat
            var verticalOffset: CGFloat
            var usesSpatialMotion: Bool

            var transition: AnyTransition {
                let base: AnyTransition = usesSpatialMotion
                    ? .scale(scale: scale).combined(with: .offset(y: verticalOffset))
                    .combined(with: .opacity)
                    : .opacity
                return .asymmetric(
                    insertion: base.animation(animation),
                    removal: base.animation(animation),
                )
            }

            static let standard = Motion(
                animation: .spring(duration: 0.62, bounce: 0.32),
                scale: 0.78,
                verticalOffset: 34,
                usesSpatialMotion: true,
            )

            static let reduced = Motion(
                animation: .easeInOut(duration: 0.18),
                scale: 1,
                verticalOffset: 0,
                usesSpatialMotion: false,
            )
        }

        static let standard = LocationWelcomeStyle(
            maxWidth: 390,
            cornerRadius: 30,
            padding: 24,
            contentSpacing: 16,
            paperOpacity: 0.92,
            scrimOpacity: 0.28,
            glassTintOpacity: 0.2,
            glow: Shadow(opacity: 0.16, radius: 22),
            lift: Shadow(opacity: 0.18, radius: 12, offsetY: 6),
            close: Close(
                offset: CGSize(width: 8, height: -8),
                tintOpacity: 0.24,
                glow: .init(opacity: 0.28, radius: 8),
                lift: .init(opacity: 0.22, radius: 5, offsetY: 3),
            ),
            motion: .standard,
        )
    }
}

// MARK: - Location card stack

extension WhereStylesheet {
    /// Motion owned by the ranked Locations-card container. Card appearance
    /// remains in ``CardStyles``; this style describes how complete cards move
    /// when the same two regions reverse rank while the surface is visible.
    struct LocationCardStackStyle: Equatable {
        var overtake: OvertakeMotion

        /// The winner's lift, passing arc, and rubber-stamp settle. The stored
        /// primitives keep the DEBUG lab directly tunable.
        struct OvertakeMotion: Equatable {
            var duration: Double
            var bounce: Double
            var lateralArc: CGFloat
            var liftScale: CGFloat
            var rotationDegrees: Double
            var settleScale: CGFloat
            var minimumOpacity: Double
            var usesSpatialMotion: Bool

            static let durationRange = 0.3 ... 1.2
            static let bounceRange = 0.0 ... 0.5
            static let lateralArcRange: ClosedRange<CGFloat> = 0 ... 48
            static let liftScaleRange: ClosedRange<CGFloat> = 1 ... 1.08
            static let rotationRange = 0.0 ... 6.0
            static let settleScaleRange: ClosedRange<CGFloat> = 0.92 ... 1

            static let standard = OvertakeMotion(
                duration: 0.72,
                bounce: 0.18,
                lateralArc: 18,
                liftScale: 1.03,
                rotationDegrees: 1.5,
                settleScale: 0.975,
                minimumOpacity: 1,
                usesSpatialMotion: true,
            )

            /// Reduce Motion keeps the delayed data reveal but removes travel,
            /// scale, and rotation. A brief fade still emphasizes the new lead.
            static let reducedMotion = OvertakeMotion(
                duration: 0.2,
                bounce: 0,
                lateralArc: 0,
                liftScale: 1,
                rotationDegrees: 0,
                settleScale: 1,
                minimumOpacity: 0.82,
                usesSpatialMotion: false,
            )
        }

        static let standard = LocationCardStackStyle(overtake: .standard)
    }
}

// MARK: - Location forecast

extension WhereStylesheet {
    /// Passport-visa appearance for the annual estimate shared by Locations,
    /// calendars, and Estimated Time feature discovery.
    struct LocationForecastStyle: Equatable {
        var cornerRadius: CGFloat
        var padding: CGFloat
        var rowSpacing: CGFloat
        var expansionAnimation: Animation
        var surface: Surface
        var header: Header
        var row: Row
        var progress: Progress
        var controls: Controls
        var ink: Ink

        struct Surface: Equatable {
            var outlineWidth: CGFloat
            var inset: CGFloat
            var microprintGlyphSize: CGFloat
            var microprintSpacing: CGFloat
            var rosetteWobble: CGFloat
            var rosetteLineWidth: CGFloat
            var primaryRingSpacing: CGFloat
            var secondaryRingSpacing: CGFloat
            var shadowColor: Color
            var shadowRadius: CGFloat
            var shadowOffsetY: CGFloat
        }

        struct Header: Equatable {
            var contentSpacing: CGFloat
            var textSpacing: CGFloat
            var titleFont: Font
            var elapsedFont: Font
            var minimumHeight: CGFloat
        }

        struct Row: Equatable {
            var cornerRadius: CGFloat
            var padding: CGFloat
            var contentSpacing: CGFloat
            var estimateSpacing: CGFloat
            var regionFont: Font
            var estimateFont: Font
            var detailFont: Font
            var outlineWidth: CGFloat
        }

        struct Progress: Equatable {
            var height: CGFloat
            var hatchSpacing: CGFloat
            var hatchLineWidth: CGFloat
        }

        struct Controls: Equatable {
            var sectionSpacing: CGFloat
            var layoutSpacing: CGFloat
            var cornerRadius: CGFloat
            var horizontalPadding: CGFloat
            var minimumHeight: CGFloat
            var strokeWidth: CGFloat
            var font: Font
        }

        struct Ink: Equatable {
            var surfaceWashOpacity: Double
            var surfaceOutlineOpacity: Double
            var microprintOpacity: Double
            var rosettePrimaryOpacity: Double
            var rosetteSecondaryOpacity: Double
            var sealOpacity: Double
            var rowFillOpacity: Double
            var rowOutlineOpacity: Double
            var progressTrackOpacity: Double
            var progressEstimateFillOpacity: Double
            var progressHatchOpacity: Double
            var controlFillOpacity: Double
            var controlStrokeOpacity: Double

            static let standard = Ink(
                surfaceWashOpacity: 0.035,
                surfaceOutlineOpacity: 0.22,
                microprintOpacity: 0.18,
                rosettePrimaryOpacity: 0.08,
                rosetteSecondaryOpacity: 0.045,
                sealOpacity: 0.72,
                rowFillOpacity: 0.07,
                rowOutlineOpacity: 0.24,
                progressTrackOpacity: 0.1,
                progressEstimateFillOpacity: 0.2,
                progressHatchOpacity: 0.42,
                controlFillOpacity: 0.06,
                controlStrokeOpacity: 0.24,
            )

            static let increasedContrast = Ink(
                surfaceWashOpacity: 0.065,
                surfaceOutlineOpacity: 0.5,
                microprintOpacity: 0.4,
                rosettePrimaryOpacity: 0.14,
                rosetteSecondaryOpacity: 0.09,
                sealOpacity: 1,
                rowFillOpacity: 0.12,
                rowOutlineOpacity: 0.55,
                progressTrackOpacity: 0.2,
                progressEstimateFillOpacity: 0.32,
                progressHatchOpacity: 0.68,
                controlFillOpacity: 0.12,
                controlStrokeOpacity: 0.56,
            )
        }

        static let standard = LocationForecastStyle(
            cornerRadius: 22,
            padding: 16,
            rowSpacing: 12,
            expansionAnimation: .easeInOut(duration: 0.2),
            surface: Surface(
                outlineWidth: 1.25,
                inset: 9,
                microprintGlyphSize: 7,
                microprintSpacing: 10,
                rosetteWobble: 5,
                rosetteLineWidth: 0.75,
                primaryRingSpacing: 10,
                secondaryRingSpacing: 16,
                shadowColor: Color.black.opacity(0.08),
                shadowRadius: 10,
                shadowOffsetY: 3,
            ),
            header: Header(
                contentSpacing: 10,
                textSpacing: 2,
                titleFont: .system(.headline, design: .serif),
                elapsedFont: .footnote,
                minimumHeight: 50,
            ),
            row: Row(
                cornerRadius: 14,
                padding: 10,
                contentSpacing: 6,
                estimateSpacing: 2,
                regionFont: .system(.title3, design: .serif),
                estimateFont: .system(.headline, design: .rounded),
                detailFont: .footnote,
                outlineWidth: 0.75,
            ),
            progress: Progress(
                height: 8,
                hatchSpacing: 6,
                hatchLineWidth: 1,
            ),
            controls: Controls(
                sectionSpacing: 8,
                layoutSpacing: 6,
                cornerRadius: 12,
                horizontalPadding: 10,
                minimumHeight: 44,
                strokeWidth: 1,
                font: .subheadline,
            ),
            ink: .standard,
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
        /// Visa-style endorsement for an annual estimate on a primary card.
        var estimateSticker = EstimateSticker.standard
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

        struct EstimateSticker: Equatable {
            var labelTypography: CardStyle.Typography
            var valueTypography: CardStyle.Typography
            var contentOpacity: Double
            var scale: CGFloat
            var cornerRadius: CGFloat
            var horizontalPadding: CGFloat
            var verticalPadding: CGFloat
            var rotationDegrees: Double
            var fillOpacity: Double
            var outlineOpacity: Double
            var outlineWidth: CGFloat
            var innerInset: CGFloat
            var innerOutlineWidth: CGFloat
            var innerDash: [CGFloat]

            static let standard = EstimateSticker(
                labelTypography: .init(
                    size: .semantic(.caption),
                    weight: .semibold,
                    design: .default,
                ),
                valueTypography: .init(
                    size: .semantic(.headline),
                    weight: .semibold,
                    design: .default,
                ),
                contentOpacity: 0.92,
                scale: 0.8,
                cornerRadius: 8,
                horizontalPadding: 10,
                verticalPadding: 7,
                rotationDegrees: -2,
                fillOpacity: 0.08,
                outlineOpacity: 0.58,
                outlineWidth: 1,
                innerInset: 3,
                innerOutlineWidth: 1,
                innerDash: [3, 2],
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
                animation: .easeOut(duration: 0.3),
            )

            /// The Reduce-Motion pairing.
            static let reducedMotion = DayCountStyle(
                revealDelay: .milliseconds(500),
                morph: .crossFade,
                animation: .easeInOut(duration: 0.2),
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
                cornerRadius: 28,
                padding: 22,
                contentSpacing: 16,
                progressBarHeight: 10,
                entryStamp: .standard(size: 88, showsArcText: true),
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
                    design: .rounded,
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
                        fillOpacity: 0.13,
                        stroke: .init(opacity: 0.28, width: 1.5),
                    ),
                    stamp: .init(
                        center: CGPoint(x: 0.5, y: 0.5),
                        extent: CGSize(width: 0.78, height: 0.78),
                        scale: 0.88,
                        fillOpacity: 0.78,
                        stroke: nil,
                    ),
                    securityBorder: .init(
                        inset: 9,
                        glyphSize: 8,
                        spacing: 11,
                        opacity: 0.22,
                    ),
                ),
                sheen: CardStyle.Sheen(
                    intensity: 1,
                    staticGlintIntensity: 0.25,
                    // A phone held upright: the glint sits near the lower edge
                    // instead of washing out the card's central content.
                    staticPose: .init(roll: 0, pitch: -1),
                ),
                rosette: CardStyle.Rosette(
                    wobble: 2,
                    lineWidth: 1,
                    primaryRingSpacing: 13.5,
                    secondaryRingSpacing: 9.5,
                ),
                glow: CardStyle.Shadow(opacity: 0.75, radius: 12),
                lift: CardStyle.Shadow(opacity: 0.6, radius: 34, offsetY: 18),
            ),
            compact: CardStyle(
                cornerRadius: 22,
                padding: 16,
                contentSpacing: 10,
                progressBarHeight: 6,
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
                    design: .rounded,
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
                    intensity: 0.5,
                    staticGlintIntensity: 0.5,
                    // Preserve the compact card's existing neutral treatment.
                    staticPose: .init(roll: 0, pitch: 0),
                ),
                rosette: CardStyle.Rosette(
                    wobble: 2,
                    lineWidth: 1,
                    primaryRingSpacing: 13,
                    secondaryRingSpacing: 11,
                ),
                glow: CardStyle.Shadow(opacity: 0.55, radius: 6),
                lift: CardStyle.Shadow(opacity: 0.4, radius: 17, offsetY: 9),
            ),
            watermarkOpacity: 0.08,
            glassTintOpacity: 0.18,
            nameOpacity: 0.8,
            rosetteFill: RosetteFill(primary: 0.12, secondary: 0.08),
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
                cornerRadius: 28,
                plain: MonthStyle.Card(
                    fill: Color.primary.opacity(0.03),
                    border: Color.primary.opacity(0.12),
                    borderWidth: 2,
                    foreground: .primary,
                ),
                current: MonthStyle.Card(
                    fill: Color.accentColor.opacity(0.08),
                    border: Color.accentColor.opacity(0.7),
                    borderWidth: 3,
                    foreground: Color.primary.mix(
                        with: .accentColor,
                        by: 0.25,
                        in: .perceptual,
                    ),
                ),
                footerDividerSpacing: 8,
                footerSpacing: 4,
                footerRowSpacing: 6,
                unfocusedRowOpacity: 0.55,
            ),
            dotSize: 6,
            regionBand: RegionBand(
                opacity: 0.16,
                cornerRadius: 14,
                continuationRadius: 3,
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

        static let standard = EvidenceStyle(
            previewCornerRadius: 22,
            pdfPreviewMinHeight: 420,
            loadingMinHeight: 200,
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
            var nodeEmojiFont: Font
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
            var transitionHeight: CGFloat
            var joinedBaseHeight: CGFloat
            var joinedVerticalPadding: CGFloat
            var joinedLabelSpacing: CGFloat
            var joinedCountHorizontalPadding: CGFloat
            var joinedCountVerticalPadding: CGFloat
        }

        static let standard = TimelineStyle(
            overview: Overview(
                spacing: 12,
                padding: 16,
                cornerRadius: 24,
                background: Color.primary.opacity(0.035),
                border: Color.primary.opacity(0.1),
                borderWidth: 1,
                yearFont: .system(.title2, design: .serif).bold(),
                pinsToViewport: true,
            ),
            ribbon: Ribbon(
                monthLabelSpacing: 6,
                height: 18,
                track: Color.primary.opacity(0.07),
                border: Color.primary.opacity(0.12),
                borderWidth: 1,
                regionSpacing: 8,
                regionLabelSpacing: 4,
                separatesRegions: false,
            ),
            rail: Rail(
                lineWidth: 4,
                toCardSpacing: 10,
                nodeSize: 42,
                nodeEmojiFont: .system(size: 20),
                nodeFillOpacity: 0.18,
                nodeStrokeWidth: 2,
            ),
            row: Row(
                spacing: 12,
                labelSpacing: 3,
                gap: 8,
                baseHeight: 64,
                yearScaleHeight: 320,
                horizontalPadding: 14,
                verticalPadding: 12,
                cornerRadius: 18,
                fillOpacity: 0.09,
                borderOpacity: 0.24,
                borderWidth: 1,
                countHorizontalPadding: 10,
                countVerticalPadding: 6,
                countFillOpacity: 0.16,
                stacksDayCount: false,
            ),
            planned: Planned(
                fillOpacity: 0.035,
                borderOpacity: 0.14,
                hatchOpacity: 0.16,
                hatchSpacing: 8,
                hatchLineWidth: 1,
                labelOpacity: 0.7,
                transitionHeight: 16,
                joinedBaseHeight: 32,
                joinedVerticalPadding: 8,
                joinedLabelSpacing: 5,
                joinedCountHorizontalPadding: 8,
                joinedCountVerticalPadding: 4,
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
                    animation: animation.delay(Double(max(0, order)) * delay),
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
            reveal: .easeIn(duration: 0.16),
            reducedReveal: .easeInOut(duration: 0.2),
            captionFade: .easeOut(duration: 0.3),
            staggeredReveal: StaggeredReveal(
                animation: .easeOut(duration: 0.35),
                verticalOffset: 16,
                delay: 0.08,
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

        static let standard = LaunchStyle(
            minimumSplashDuration: .milliseconds(800),
            captionDelay: .milliseconds(1200),
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
            var badgeSize: CGFloat
            var symbolPointSize: CGFloat
            var badgeTintOpacity: Double
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
                badgeSize: 76,
                symbolPointSize: 34,
                badgeTintOpacity: 0.14,
                contentMaxWidth: 560,
                spacing: 14,
                verticalPadding: 24,
            ),
            marketingPanel: MarketingPanel(
                cornerRadius: 20,
                maxWidth: 680,
                padding: 16,
                contentSpacing: 12,
                rowVerticalInset: 6,
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
                opacity: 0.12,
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
                    cornerRadius: 20,
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
                accent: Color(white: 0.28),
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
                    home: Widgets.Wallpapers.Gradient(top: .indigo, bottom: .cyan),
                    lock: Widgets.Wallpapers.Gradient(top: .purple, bottom: .blue),
                ),
                lockWidgetHeight: 76,
            ),
        )
    }
}

// MARK: - Settings passport artwork

extension WhereStylesheet {
    /// Geometry shared only by the repeated passport seal artwork.
    struct PassportSealStyle: Equatable {
        var size: CGFloat
        var rotationDegrees: Double
        var outerLineWidth: CGFloat
        var innerLineWidth: CGFloat
        var innerInset: CGFloat
        var dashLength: CGFloat
        var dashSpacing: CGFloat
        var symbolFont: Font

        static let standard = PassportSealStyle(
            size: 52,
            rotationDegrees: -8,
            outerLineWidth: 2,
            innerLineWidth: 1,
            innerInset: 7,
            dashLength: 3,
            dashSpacing: 3,
            symbolFont: .title3,
        )
    }

    /// Appearance for the reflective privacy statement in Settings.
    struct PrivacyPassportCardStyle: Equatable {
        var cornerRadius: CGFloat
        var padding: CGFloat
        var sectionSpacing: CGFloat
        var headerSpacing: CGFloat
        var titleFont: Font
        var detailFont: Font
        var rosette: Rosette
        var reflectiveSurface: ReflectiveSurface
        var disclosure: Disclosure
        var outlineOpacity: Double
        var outlineWidth: CGFloat

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
            var intensity: Double
            var staticGlintIntensity: Double
            var staticPose: Pose

            struct Pose: Equatable {
                var roll: Double
                var pitch: Double
            }
        }

        struct Disclosure: Equatable {
            var rowSpacing: CGFloat
            var cornerRadius: CGFloat
            var padding: CGFloat
            var contentSpacing: CGFloat
            var textSpacing: CGFloat
            var iconSize: CGFloat
            var symbolFont: Font
            var titleFont: Font
            var detailFont: Font
            var statusFont: Font
            var statusHorizontalPadding: CGFloat
            var statusVerticalPadding: CGFloat
            var fillOpacity: Double
            var strokeOpacity: Double
            var strokeWidth: CGFloat
            var statusFillOpacity: Double
        }

        static let standard = PrivacyPassportCardStyle(
            cornerRadius: 20,
            padding: 16,
            sectionSpacing: 12,
            headerSpacing: 12,
            titleFont: .headline,
            detailFont: .subheadline,
            rosette: Rosette(
                wobble: 5,
                lineWidth: 0.75,
                primaryRingSpacing: 10,
                secondaryRingSpacing: 16,
                primaryOpacity: 0.1,
                secondaryOpacity: 0.06,
            ),
            reflectiveSurface: ReflectiveSurface(
                backgroundTop: Color(red: 0.08, green: 0.18, blue: 0.34),
                backgroundBottom: Color(red: 0.02, green: 0.07, blue: 0.16),
                accent: Color(red: 0.88, green: 0.72, blue: 0.32),
                intensity: 0.28,
                staticGlintIntensity: 0.28,
                staticPose: .init(roll: 0.3, pitch: -0.15),
            ),
            disclosure: Disclosure(
                rowSpacing: 8,
                cornerRadius: 12,
                padding: 10,
                contentSpacing: 10,
                textSpacing: 3,
                iconSize: 32,
                symbolFont: .subheadline,
                titleFont: .subheadline,
                detailFont: .footnote,
                statusFont: .footnote,
                statusHorizontalPadding: 8,
                statusVerticalPadding: 4,
                fillOpacity: 0.08,
                strokeOpacity: 0.18,
                strokeWidth: 0.75,
                statusFillOpacity: 0.14,
            ),
            outlineOpacity: 0.32,
            outlineWidth: 1,
        )
    }

    /// Appearance for a flat, single-ink stamp banner.
    struct StampBannerStyle: Equatable {
        var tint: Color
        var padding: CGFloat
        var contentSpacing: CGFloat
        var titleFont: Font
        var detailFont: Font
        var outlineWidth: CGFloat
        var rosette: Rosette
        var ink: Ink

        struct Rosette: Equatable {
            var wobble: CGFloat
            var lineWidth: CGFloat
            var primaryRingSpacing: CGFloat
            var secondaryRingSpacing: CGFloat
        }

        struct Ink: Equatable {
            var outlineOpacity: Double
            var primaryRosetteOpacity: Double
            var secondaryRosetteOpacity: Double
            var sealOpacity: Double
            var titleOpacity: Double
            var detailOpacity: Double
            var accessoryOpacity: Double

            static let standard = Ink(
                outlineOpacity: 0.72,
                primaryRosetteOpacity: 0.1,
                secondaryRosetteOpacity: 0.06,
                sealOpacity: 0.9,
                titleOpacity: 1,
                detailOpacity: 0.68,
                accessoryOpacity: 0.86,
            )

            static let increasedContrast = Ink(
                outlineOpacity: 1,
                primaryRosetteOpacity: 0.16,
                secondaryRosetteOpacity: 0.1,
                sealOpacity: 1,
                titleOpacity: 1,
                detailOpacity: 0.9,
                accessoryOpacity: 1,
            )
        }

        static let openSource = StampBannerStyle(
            tint: .accentColor,
            padding: 16,
            contentSpacing: 12,
            titleFont: .headline,
            detailFont: .subheadline,
            outlineWidth: 1.5,
            rosette: Rosette(
                wobble: 5,
                lineWidth: 0.75,
                primaryRingSpacing: 10,
                secondaryRingSpacing: 16,
            ),
            ink: .standard,
        )

        static let plannedStayWarning = StampBannerStyle(
            tint: .orange,
            padding: 16,
            contentSpacing: 12,
            titleFont: .headline,
            detailFont: .subheadline,
            outlineWidth: 1.5,
            rosette: Rosette(
                wobble: 5,
                lineWidth: 0.75,
                primaryRingSpacing: 10,
                secondaryRingSpacing: 16,
            ),
            ink: .standard,
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
                backgroundTop: Color(.systemBackground),
                backgroundBottom: Color.accentColor.opacity(0.12),
            ),
        )
    }
}

// MARK: - Themes

/// The Where app's Broadway themes, seeded at the root by `whereBroadwayRoot()`.
/// Carries the selected presentation identity independently from system traits.
/// Both identities currently resolve through the same tokens.
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
