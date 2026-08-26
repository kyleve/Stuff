import BroadwayCore
import SwiftUI
import ThrowCore

/// Throw's trait-aware design tokens.
struct ThrowStylesheet: BStylesheet {
    var spacing = Spacing()
    var cornerRadius = CornerRadius()
    var projection = ProjectionStyle.standard
    var status = StatusStyle.standard
    var calibration = CalibrationStyle.standard

    init() {}

    init(context: SlicingContext) throws {
        let traits = context.traits
        if traits.contentSizeCategory.isAccessibilitySize {
            status.minimumRowHeight = 56
        }
        if traits.accessibility.shouldDifferentiateWithoutColor {
            status.usesShapeLabels = true
        }
        if traits.accessibility.isReduceTransparencyEnabled {
            status.cardBackground = Color(.secondarySystemBackground)
        }
        if traits.accessibility.isReduceMotionEnabled {
            projection.correctionDuration = 0
            projection.modeChangeDuration = 0
        }
        if traits.mode == .dark {
            projection.markLuminance = 0.5
        }
    }

    static let `default` = ThrowStylesheet()
}

extension ThrowStylesheet {
    struct CornerRadius: Equatable {
        var medium: CGFloat = 12
    }

    struct Spacing: Equatable {
        var xSmall: CGFloat = 4
        var small: CGFloat = 8
        var medium: CGFloat = 12
        var large: CGFloat = 16
        var xLarge: CGFloat = 24
        var xxLarge: CGFloat = 32
    }

    struct ProjectionStyle: Equatable {
        struct LabelStyle: Equatable {
            struct LineStyle: Equatable {
                var font: Font
                var luminanceMultiplier: Double
            }

            var headline: LineStyle
            var detail: LineStyle
            var routeTracking: CGFloat
            var offset: CGFloat

            subscript(role: ProjectionLabelRole) -> LineStyle {
                switch role {
                    case .headline: headline
                    case .detail: detail
                }
            }
        }

        var background: Color
        var markLuminance: Double
        var aircraft: AircraftStyle
        var activity: ActivityStyle
        var observer: ObserverStyle
        var geography: GeographyStyle
        var statusLuminance: Double
        var minimumMarkSize: CGFloat
        var standardMarkSize: CGFloat
        var label: LabelStyle
        var correctionDuration: Double
        var modeChangeDuration: Double

        static let standard = ProjectionStyle(
            background: .black,
            markLuminance: 0.95,
            aircraft: .standard,
            activity: .standard,
            observer: .standard,
            geography: .standard,
            statusLuminance: 0.55,
            minimumMarkSize: 6,
            standardMarkSize: 12,
            label: LabelStyle(
                headline: LabelStyle.LineStyle(
                    font: .system(size: 10, weight: .regular, design: .monospaced),
                    luminanceMultiplier: 0.7,
                ),
                detail: LabelStyle.LineStyle(
                    font: .system(size: 7, weight: .regular, design: .monospaced),
                    luminanceMultiplier: 0.42,
                ),
                routeTracking: -0.4,
                offset: 8,
            ),
            correctionDuration: 0.75,
            modeChangeDuration: 1.2,
        )
    }

    struct ObserverStyle: Equatable {
        var diameter: CGFloat
        var lineWidth: CGFloat
        var luminanceMultiplier: Double

        static let standard = ObserverStyle(
            diameter: 7,
            lineWidth: 0.8,
            luminanceMultiplier: 0.3,
        )
    }

    struct ActivityStyle: Equatable {
        var cueLineWidth: CGFloat
        var confirmedOpacity: Double
        var inferredOpacityMultiplier: Double
        var airportOpacity: Double
        var airportLineWidth: CGFloat
        var airportLineLength: CGFloat
        var acquisitionDuration: Double
        var cueTransitionDuration: Double
        var anchorTransitionDuration: Double
        var completionDuration: Double

        static let standard = ActivityStyle(
            cueLineWidth: 0.8,
            confirmedOpacity: 0.36,
            inferredOpacityMultiplier: 0.6,
            airportOpacity: 0.28,
            airportLineWidth: 1,
            airportLineLength: 16,
            acquisitionDuration: 0.9,
            cueTransitionDuration: 0.35,
            anchorTransitionDuration: 0.4,
            completionDuration: 0.5,
        )
    }

    struct AircraftStyle: Equatable {
        struct RGB: Equatable {
            let red: Double
            let green: Double
            let blue: Double

            init(hex: Int) {
                red = Double((hex >> 16) & 0xFF) / 255
                green = Double((hex >> 8) & 0xFF) / 255
                blue = Double(hex & 0xFF) / 255
            }

            private init(red: Double, green: Double, blue: Double) {
                self.red = red
                self.green = green
                self.blue = blue
            }

            func color(brightness: Double, intensity: Double) -> Color {
                let projected = projected(brightness: brightness, intensity: intensity)
                return Color(
                    red: projected.red,
                    green: projected.green,
                    blue: projected.blue,
                )
            }

            func projected(brightness: Double, intensity: Double) -> RGB {
                let peak = max(red, green, blue)
                guard peak > 0 else { return self }
                let multiplier = brightness * intensity / peak
                return RGB(
                    red: red * multiplier,
                    green: green * multiplier,
                    blue: blue * multiplier,
                )
            }
        }

        let secondaryOpacityMultiplier: Double
        let brandDotBrightnessMultiplier: Double
        let brandColors: [AirlineBrand: RGB]

        subscript(brand: AirlineBrand) -> RGB? {
            brandColors[brand]
        }

        static let standard = AircraftStyle(
            secondaryOpacityMultiplier: 0.35,
            brandDotBrightnessMultiplier: 0.65,
            brandColors: [
                .alaska: RGB(hex: 0x01426A),
                .allegiant: RGB(hex: 0x025DAA),
                .american: RGB(hex: 0xC3002F),
                .airCanada: RGB(hex: 0xD8292F),
                .aeromexico: RGB(hex: 0x003B5C),
                .avelo: RGB(hex: 0x552583),
                .breeze: RGB(hex: 0x00A9CE),
                .delta: RGB(hex: 0xC8102E),
                .frontier: RGB(hex: 0x008C45),
                .flair: RGB(hex: 0x7AC143),
                .hawaiian: RGB(hex: 0x5C2D91),
                .jetBlue: RGB(hex: 0x003876),
                .porter: RGB(hex: 0x00263A),
                .southwest: RGB(hex: 0x304CB2),
                .spirit: RGB(hex: 0xFFD100),
                .sunCountry: RGB(hex: 0xF15A24),
                .airTransat: RGB(hex: 0x00AEEF),
                .united: RGB(hex: 0x005DAA),
                .westJet: RGB(hex: 0x00A4B4),
                .volaris: RGB(hex: 0x6C1D7C),
                .vivaAerobus: RGB(hex: 0x00A651),
                .fedEx: RGB(hex: 0x4D148C),
                .ups: RGB(hex: 0xFFB500),
            ],
        )
    }

    /// Constant-screen-space strokes for Map geography. Luminance is relative
    /// to both the global projection intensity and Geography's own intensity.
    struct GeographyStyle: Equatable {
        struct LineStyle: Equatable {
            var lineWidth: CGFloat
            var luminance: Double
            var dash: [CGFloat]
        }

        var coastline: LineStyle
        var lake: LineStyle
        var river: LineStyle
        var nationalBoundary: LineStyle
        var disputedBoundary: LineStyle
        var regionalBoundary: LineStyle
        var countyBoundary: LineStyle
        var primaryRoad: LineStyle
        var renderOrder: [GeographyLineKind]

        subscript(kind: GeographyLineKind) -> LineStyle {
            switch kind {
                case .coastline: coastline
                case .lake: lake
                case .river: river
                case .nationalBoundary: nationalBoundary
                case .disputedBoundary: disputedBoundary
                case .regionalBoundary: regionalBoundary
                case .countyBoundary: countyBoundary
                case .primaryRoad: primaryRoad
            }
        }

        static let standard = GeographyStyle(
            coastline: LineStyle(lineWidth: 1.4, luminance: 1, dash: []),
            lake: LineStyle(lineWidth: 1, luminance: 0.9, dash: []),
            river: LineStyle(lineWidth: 0.75, luminance: 0.68, dash: []),
            nationalBoundary: LineStyle(lineWidth: 1, luminance: 0.85, dash: []),
            disputedBoundary: LineStyle(lineWidth: 1, luminance: 0.85, dash: [3, 4]),
            regionalBoundary: LineStyle(lineWidth: 0.75, luminance: 0.55, dash: []),
            countyBoundary: LineStyle(lineWidth: 0.5, luminance: 0.3, dash: [1, 3]),
            primaryRoad: LineStyle(lineWidth: 0.75, luminance: 0.45, dash: []),
            renderOrder: [
                .countyBoundary,
                .primaryRoad,
                .river,
                .regionalBoundary,
                .disputedBoundary,
                .nationalBoundary,
                .lake,
                .coastline,
            ],
        )
    }

    struct StatusStyle: Equatable {
        var minimumRowHeight: CGFloat
        var cardBackground: Color
        var healthy: Color
        var retrying: Color
        var failed: Color
        var quiet: Color
        var usesShapeLabels: Bool

        static let standard = StatusStyle(
            minimumRowHeight: 44,
            cardBackground: Color(.secondarySystemGroupedBackground),
            healthy: .green,
            retrying: .orange,
            failed: .red,
            quiet: .secondary,
            usesShapeLabels: false,
        )
    }

    struct CalibrationStyle: Equatable {
        var line: Color
        var secondaryLine: Color
        var boundaryLineWidth: CGFloat
        var gridLineWidth: CGFloat

        static let standard = CalibrationStyle(
            line: Color(white: 0.75),
            secondaryLine: Color(white: 0.35),
            boundaryLineWidth: 2,
            gridLineWidth: 1,
        )
    }
}

extension EnvironmentValues {
    var throwStylesheet: ThrowStylesheet {
        bContext.stylesheet(ThrowStylesheet.self, fallback: .default)
    }
}
