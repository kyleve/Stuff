import SnapshotKit
import SwiftUI
import ThrowCore

/// The sole production renderer for projector, Preview, and mirror fallback output.
public struct ProjectionSurface: View {
    private let session: ThrowSession
    private let presentation: ProjectionPresentation

    @Environment(\.throwStylesheet) private var stylesheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(session: ThrowSession, presentation: ProjectionPresentation) {
        self.session = session
        self.presentation = presentation
    }

    public var body: some View {
        let frame = session.projectionFrame
        let contentOpacity = session.projectionContentOpacity
        let markSizeMultiplier = session.markSizeMultiplier
        let intensityMultiplier = session.intensityMultiplier
        let projectionStyle = stylesheet.projection
        Group {
            if session.isCalibrating {
                CalibrationPatternView(
                    screenTopBearing: session.screenTopBearing,
                    rotation: session.screenRotation,
                    flipHorizontal: session.flipHorizontal,
                    flipVertical: session.flipVertical,
                    safeInsetPercent: session.safeInsetPercent,
                )
            } else {
                Canvas(rendersAsynchronously: true) { context, size in
                    draw(
                        frame: frame,
                        contentOpacity: contentOpacity,
                        markSizeMultiplier: markSizeMultiplier,
                        intensityMultiplier: intensityMultiplier,
                        style: projectionStyle,
                        in: &context,
                        size: size,
                    )
                }
            }
        }
        .background(stylesheet.projection.background)
        .overlay(alignment: .topTrailing) {
            if session.isCalibrating == false {
                ProjectionStatusIndicator(health: session.feedHealth)
                    .padding(stylesheet.spacing.large)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.projectionPreviewSummary))
        .accessibilityValue(session.projectionAccessibilitySummary)
        .accessibilityHidden(presentation != .preview)
        .preferredColorScheme(session.controllerColorScheme)
        .onAppear { session.updateReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, newValue in
            session.updateReduceMotion(newValue)
        }
    }

    private func draw(
        frame: ProjectionFrame,
        contentOpacity: Double,
        markSizeMultiplier: Double,
        intensityMultiplier: Double,
        style: ThrowStylesheet.ProjectionStyle,
        in context: inout GraphicsContext,
        size: CGSize,
    ) {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let markSize = max(
            style.minimumMarkSize,
            style.standardMarkSize * markSizeMultiplier,
        )
        let color = Color(
            white: style.markLuminance * intensityMultiplier,
        )

        for mark in frame.marks {
            let point = CGPoint(
                x: origin.x + mark.point.x * side,
                y: origin.y + mark.point.y * side,
            )
            var markContext = context
            let effectiveOpacity = mark.opacity * contentOpacity
            markContext.opacity = effectiveOpacity
            markContext.translateBy(x: point.x, y: point.y)
            markContext.rotate(by: .degrees(mark.orientationDegrees ?? 0))
            let rect = CGRect(
                x: -markSize / 2,
                y: -markSize / 2,
                width: markSize,
                height: markSize,
            )
            switch mark.glyph {
                case .aircraft:
                    markContext.fill(AircraftGlyphShape().path(in: rect), with: .color(color))
                case .star:
                    markContext.fill(Path(ellipseIn: rect), with: .color(color))
                case .satellite:
                    markContext.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1)
            }

            if let label = mark.label {
                let labelPoint = CGPoint(
                    x: point.x + markSize / 2 + style.labelOffset,
                    y: point.y,
                )
                let labelValue = label.secondary.map { "\(label.primary) · \($0)" }
                    ?? label.primary
                let text = Text(verbatim: labelValue)
                    .font(.caption)
                    .foregroundStyle(color)
                var labelContext = context
                labelContext.opacity = effectiveOpacity * mark.labelOpacity
                labelContext.draw(text, at: labelPoint, anchor: .leading)
            }
        }
    }
}

#if DEBUG
    extension ProjectionSurface: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Map",
                configurations: projectionConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .fixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "True Sky",
                configurations: projectionConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .trueSkySnapshotFixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Retrying With Last Good Marks",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .retryingSnapshotFixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Marks Only",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .marksOnlySnapshotFixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Callsigns",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .callsignsSnapshotFixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Dense Adaptive",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .denseAdaptiveSnapshotFixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Failed And Blank",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .failedSnapshotFixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Quiet",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(session: .quietFixture(), presentation: .externalDisplay)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Calibration",
                configurations: projectorAspectConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(
                    session: .calibrationSnapshotFixture(),
                    presentation: .calibration,
                )
                .throwBroadwayRoot()
            }
        }

        private static var projectionConfigurations: [SnapshotConfiguration] {
            [
                widescreenConfiguration,
                sixteenByTenConfiguration,
                fourByThreeConfiguration,
                SnapshotConfiguration(device: .iPhone),
            ]
        }

        private static var statusConfigurations: [SnapshotConfiguration] {
            [widescreenConfiguration]
        }

        private static var projectorAspectConfigurations: [SnapshotConfiguration] {
            [widescreenConfiguration, sixteenByTenConfiguration, fourByThreeConfiguration]
        }

        private static var widescreenConfiguration: SnapshotConfiguration {
            projectorConfiguration(name: "16x9", size: CGSize(width: 960, height: 540))
        }

        private static var sixteenByTenConfiguration: SnapshotConfiguration {
            projectorConfiguration(name: "16x10", size: CGSize(width: 960, height: 600))
        }

        private static var fourByThreeConfiguration: SnapshotConfiguration {
            projectorConfiguration(name: "4x3", size: CGSize(width: 800, height: 600))
        }

        private static func projectorConfiguration(
            name: String,
            size: CGSize,
        ) -> SnapshotConfiguration {
            SnapshotConfiguration(device: .init(name: name, size: .fixed(size)))
        }
    }

    #Preview {
        ProjectionSurface.snapshotPreviews
    }
#endif
