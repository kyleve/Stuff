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
        let airlineAccentsEnabled = session.airlineAccentsEnabled
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
                                airlineAccentsEnabled: airlineAccentsEnabled,
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
    let airlineAccentsEnabled: Bool
    let style: ThrowStylesheet.ProjectionStyle

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let standardMarkSize = max(
                style.minimumMarkSize,
                style.standardMarkSize * markSizeMultiplier,
            )
            let markColor = Color(white: style.markLuminance * intensityMultiplier)
            let primaryLabelColor = Color(
                white: style.markLuminance * style.label.primaryLuminanceMultiplier *
                    intensityMultiplier,
            )
            let secondaryLabelColor = Color(
                white: style.markLuminance * style.label.secondaryLuminanceMultiplier *
                    intensityMultiplier,
            )

            var aircraftPaths: [AircraftVisualFamily: AircraftPaths] = [:]
            for family in AircraftVisualFamily.allCases {
                let markSize = max(
                    style.minimumMarkSize,
                    standardMarkSize * family.sizeMultiplier,
                )
                let rect = CGRect(
                    x: -markSize / 2,
                    y: -markSize / 2,
                    width: markSize,
                    height: markSize,
                )
                aircraftPaths[family] = AircraftPaths(
                    size: markSize,
                    body: AircraftGlyphShape(family: family).path(in: rect),
                    accent: AircraftAccentShape(family: family).path(in: rect),
                )
            }

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
                var renderedMarkSize = standardMarkSize
                switch mark.glyph {
                    case let .aircraft(descriptor):
                        guard let paths = aircraftPaths[descriptor.family] else { continue }
                        renderedMarkSize = paths.size
                        markContext.fill(
                            paths.body,
                            with: .color(markColor),
                        )
                        if airlineAccentsEnabled,
                           let brand = descriptor.brand,
                           let rgb = style.aircraft[brand]
                        {
                            markContext.fill(
                                paths.accent,
                                with: .color(rgb.color(
                                    markLuminance: style.markLuminance,
                                    intensity: intensityMultiplier,
                                )),
                            )
                        }
                    case .star:
                        let rect = CGRect(
                            x: -standardMarkSize / 2,
                            y: -standardMarkSize / 2,
                            width: standardMarkSize,
                            height: standardMarkSize,
                        )
                        markContext.fill(Path(ellipseIn: rect), with: .color(markColor))
                    case .satellite:
                        let rect = CGRect(
                            x: -standardMarkSize / 2,
                            y: -standardMarkSize / 2,
                            width: standardMarkSize,
                            height: standardMarkSize,
                        )
                        markContext.stroke(
                            Path(ellipseIn: rect),
                            with: .color(markColor),
                            lineWidth: 1,
                        )
                }

                if let label = mark.label {
                    let labelPoint = CGPoint(
                        x: point.x + renderedMarkSize / 2 + style.label.offset,
                        y: point.y,
                    )
                    var text = Text(verbatim: label.primary)
                        .font(style.label.primaryFont)
                        .foregroundStyle(primaryLabelColor)
                    if let secondary = label.secondary {
                        text = text + Text(verbatim: "\n\(secondary)")
                            .font(style.label.secondaryFont)
                            .foregroundStyle(secondaryLabelColor)
                    }
                    var labelContext = context
                    labelContext.opacity = effectiveOpacity * mark.labelOpacity
                    labelContext.draw(text, at: labelPoint, anchor: .leading)
                }
            }
        }
    }

    private struct AircraftPaths {
        let size: CGFloat
        let body: Path
        let accent: Path
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
                if segment.startsNewSubpath {
                    paths[segment.kind, default: Path()].move(
                        to: point(segment.start, origin: origin, side: side),
                    )
                }
                paths[segment.kind, default: Path()].addLine(
                    to: point(segment.end, origin: origin, side: side),
                )
            }

            var geographyContext = context
            geographyContext.opacity = opacity
            for kind in style.geography.renderOrder {
                guard let path = paths[kind], path.isEmpty == false else { continue }
                let appearance = style.geography[kind]
                let color = Color(
                    white: intensityMultiplier * geographyIntensityMultiplier *
                        appearance.luminance,
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
                name: "Map Dark",
                configurations: [darkWidescreenConfiguration],
                settle: .immediate,
            ) {
                ProjectionSurface(session: .fixture(), presentation: .preview)
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Airline Accents Off",
                configurations: statusConfigurations,
                settle: .immediate,
            ) {
                let session = ThrowSession.fixture()
                session.airlineAccentsEnabled = false
                return ProjectionSurface(session: session, presentation: .preview)
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

        private static var darkWidescreenConfiguration: SnapshotConfiguration {
            SnapshotConfiguration(
                colorScheme: .dark,
                device: .init(name: "16x9", size: .fixed(CGSize(width: 960, height: 540))),
            )
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
