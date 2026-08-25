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
        let markOpacity = session.projectionMarkOpacity
        let markSizeMultiplier = session.markSizeMultiplier
        let intensityMultiplier = session.intensityMultiplier
        let geographyIntensityMultiplier = session.geographyIntensityMultiplier
        let projectionStyle = stylesheet.projection
        let descriptors = session.layerCatalog.descriptors.sorted { lhs, rhs in
            if lhs.zOrder == rhs.zOrder {
                lhs.id.rawValue < rhs.id.rawValue
            } else {
                lhs.zOrder < rhs.zOrder
            }
        }
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
                ZStack {
                    ForEach(descriptors) { descriptor in
                        if descriptor.id == .geography {
                            GeographyProjectionCanvas(
                                geography: frame.geography,
                                opacity: frame.geographyOpacity,
                                intensityMultiplier: intensityMultiplier,
                                geographyIntensityMultiplier: geographyIntensityMultiplier,
                                style: projectionStyle,
                            )
                            .equatable()
                            .zIndex(Double(descriptor.zOrder))
                        } else {
                            ProjectionMarksCanvas(
                                marks: frame.marks.filter { $0.id.layerID == descriptor.id },
                                opacity: markOpacity,
                                markSizeMultiplier: markSizeMultiplier,
                                intensityMultiplier: intensityMultiplier,
                                style: projectionStyle,
                            )
                            .zIndex(Double(descriptor.zOrder))
                        }
                    }
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
}

private struct ProjectionMarksCanvas: View {
    let marks: [ProjectedMark]
    let opacity: Double
    let markSizeMultiplier: Double
    let intensityMultiplier: Double
    let style: ThrowStylesheet.ProjectionStyle

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let markSize = max(
                style.minimumMarkSize,
                style.standardMarkSize * markSizeMultiplier,
            )
            let color = Color(white: style.markLuminance * intensityMultiplier)

            for mark in marks {
                let point = CGPoint(
                    x: origin.x + mark.point.x * side,
                    y: origin.y + mark.point.y * side,
                )
                var markContext = context
                let effectiveOpacity = mark.opacity * opacity
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
}

/// An equatable static surface whose paths change only with projected geography.
private struct GeographyProjectionCanvas: View, Equatable {
    let geography: ProjectedGeography?
    let opacity: Double
    let intensityMultiplier: Double
    let geographyIntensityMultiplier: Double
    let style: ThrowStylesheet.ProjectionStyle

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.geography?.id == rhs.geography?.id &&
            lhs.opacity == rhs.opacity &&
            lhs.intensityMultiplier == rhs.intensityMultiplier &&
            lhs.geographyIntensityMultiplier == rhs.geographyIntensityMultiplier &&
            lhs.style == rhs.style
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard let geography,
                  geography.segments.isEmpty == false,
                  geographyIntensityMultiplier > 0
            else { return }

            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            var paths: [GeographyLineKind: Path] = [:]
            for segment in geography.segments {
                paths[segment.kind, default: Path()].move(
                    to: point(segment.start, origin: origin, side: side),
                )
                paths[segment.kind, default: Path()].addLine(
                    to: point(segment.end, origin: origin, side: side),
                )
            }

            var geographyContext = context
            geographyContext.opacity = opacity
            for kind in GeographyLineKind.allCases {
                guard let path = paths[kind], path.isEmpty == false else { continue }
                let appearance = geographyAppearance(kind, style: style.geography)
                let color = Color(
                    white: style.markLuminance * intensityMultiplier *
                        geographyIntensityMultiplier * appearance.luminance,
                )
                geographyContext.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: appearance.lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: appearance.dash,
                    ),
                )
            }
        }
    }

    private func geographyAppearance(
        _ kind: GeographyLineKind,
        style: ThrowStylesheet.GeographyStyle,
    ) -> GeographyAppearance {
        switch kind {
            case .coastline:
                GeographyAppearance(
                    lineWidth: style.coastlineLineWidth,
                    luminance: style.coastlineLuminance,
                    dash: [],
                )
            case .lake:
                GeographyAppearance(
                    lineWidth: style.lakeLineWidth,
                    luminance: style.lakeLuminance,
                    dash: [],
                )
            case .river:
                GeographyAppearance(
                    lineWidth: style.riverLineWidth,
                    luminance: style.riverLuminance,
                    dash: [],
                )
            case .nationalBoundary:
                GeographyAppearance(
                    lineWidth: style.boundaryLineWidth,
                    luminance: style.nationalBoundaryLuminance,
                    dash: [],
                )
            case .disputedBoundary:
                GeographyAppearance(
                    lineWidth: style.boundaryLineWidth,
                    luminance: style.disputedBoundaryLuminance,
                    dash: style.disputedDash,
                )
            case .regionalBoundary:
                GeographyAppearance(
                    lineWidth: style.boundaryLineWidth,
                    luminance: style.regionalBoundaryLuminance,
                    dash: [],
                )
        }
    }

    private func point(
        _ point: ProjectionPoint,
        origin: CGPoint,
        side: CGFloat,
    ) -> CGPoint {
        CGPoint(
            x: origin.x + point.x * side,
            y: origin.y + point.y * side,
        )
    }
}

private struct GeographyAppearance {
    let lineWidth: CGFloat
    let luminance: Double
    let dash: [CGFloat]
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
