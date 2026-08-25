import BroadwayCore
import SwiftUI

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
        var background: Color
        var markLuminance: Double
        var statusLuminance: Double
        var minimumMarkSize: CGFloat
        var standardMarkSize: CGFloat
        var labelOffset: CGFloat
        var correctionDuration: Double
        var modeChangeDuration: Double

        static let standard = ProjectionStyle(
            background: .black,
            markLuminance: 0.95,
            statusLuminance: 0.55,
            minimumMarkSize: 6,
            standardMarkSize: 12,
            labelOffset: 8,
            correctionDuration: 0.75,
            modeChangeDuration: 1.2,
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
