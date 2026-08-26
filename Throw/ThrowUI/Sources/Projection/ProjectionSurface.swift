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
        let effects = session.projectionMarkEffects
        let markOpacity = session.projectionMarkOpacity
        let markSizeMultiplier = session.markSizeMultiplier
        let intensityMultiplier = session.intensityMultiplier
        let airlineAccentsEnabled = session.airlineAccentsEnabled
        let geographyIntensityMultiplier = session.geographyIntensityMultiplier
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
                ZStack {
                    ForEach(frame.layers) { layer in
                        switch layer.content {
                            case let .lines(lines):
                                ProjectionLinesCanvas(
                                    layerID: layer.id,
                                    lines: lines,
                                    opacity: layer.opacity,
                                    intensityMultiplier: intensityMultiplier,
                                    geographyIntensityMultiplier: geographyIntensityMultiplier,
                                    style: projectionStyle,
                                )
                                .equatable()
                                .zIndex(Double(layer.zOrder))
                            case let .marks(marks):
                                ProjectionMarksCanvas(
                                    marks: marks,
                                    effects: effects,
                                    opacity: markOpacity * layer.opacity,
                                    markSizeMultiplier: markSizeMultiplier,
                                    intensityMultiplier: intensityMultiplier,
                                    airlineAccentsEnabled: airlineAccentsEnabled,
                                    style: projectionStyle,
                                )
                                .zIndex(Double(layer.zOrder))
                        }
                    }
                    ObserverMarkerCanvas(
                        point: session.observerMapPoint,
                        intensityMultiplier: intensityMultiplier,
                        style: projectionStyle,
                    )
                    .zIndex(Double(Int.max))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.isCalibrating == false {
                ProjectionStatusIndicator(health: session.activeExperienceHealth)
                    .padding(stylesheet.spacing.large)
            }
        }
        .opacity(session.projectionSurfaceOpacity)
        .background(stylesheet.projection.background)
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

private struct ObserverMarkerCanvas: View {
    let point: ProjectionPoint?
    let intensityMultiplier: Double
    let style: ThrowStylesheet.ProjectionStyle

    var body: some View {
        Canvas { context, size in
            guard let point else { return }
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let center = CGPoint(
                x: origin.x + point.x * side,
                y: origin.y + point.y * side,
            )
            let diameter = style.observer.diameter
            let color = Color(
                white: style.markLuminance * style.observer.luminanceMultiplier *
                    intensityMultiplier,
            )
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter,
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(color),
                lineWidth: style.observer.lineWidth,
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - 0.75,
                    y: center.y - 0.75,
                    width: 1.5,
                    height: 1.5,
                )),
                with: .color(color),
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ProjectionMarksCanvas: View {
    let marks: [ProjectedMark]
    let effects: [LayerMarkID: ProjectionMarkEffect]
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
            let detailLabelColor = Color(
                white: style.markLuminance * style.label.detail.luminanceMultiplier *
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
                )
            }

            for mark in marks {
                let effect = effects[mark.id] ?? .identity
                let point = CGPoint(
                    x: origin.x + mark.point.x * side,
                    y: origin.y + mark.point.y * side,
                )
                var markContext = context
                let prominenceOpacity = 1 +
                    (style.aircraft.secondaryOpacityMultiplier - 1) * mark.secondaryProminence
                let effectiveOpacity = mark.opacity * opacity * prominenceOpacity
                markContext.opacity = effectiveOpacity
                markContext.translateBy(x: point.x, y: point.y)
                markContext.rotate(by: .degrees(mark.orientationDegrees ?? 0))
                markContext.scaleBy(x: effect.scale, y: effect.scale)
                var renderedMarkSize = standardMarkSize
                var brandDotColor: Color?
                switch mark.glyph {
                    case let .aircraft(descriptor):
                        guard let paths = aircraftPaths[descriptor.family] else { continue }
                        renderedMarkSize = paths.size
                        if let cue = effect.activityCue {
                            drawCue(
                                cue.previous,
                                opacity: cue.previousOpacity,
                                in: &markContext,
                                markSize: paths.size,
                                color: markColor,
                            )
                            drawCue(
                                cue.current,
                                opacity: cue.currentOpacity,
                                in: &markContext,
                                markSize: paths.size,
                                color: markColor,
                            )
                        } else {
                            drawCue(
                                descriptor.activity,
                                opacity: 1,
                                in: &markContext,
                                markSize: paths.size,
                                color: markColor,
                            )
                        }
                        if let progress = effect.acquisitionProgress {
                            let diameter = paths.size * (1 + 1.4 * progress)
                            var ringContext = markContext
                            ringContext.opacity *= 0.16 * (1 - progress)
                            ringContext.stroke(
                                Path(ellipseIn: CGRect(
                                    x: -diameter / 2,
                                    y: -diameter / 2,
                                    width: diameter,
                                    height: diameter,
                                )),
                                with: .color(markColor),
                                lineWidth: 0.75,
                            )
                        }
                        markContext.fill(
                            paths.body,
                            with: .color(markColor),
                        )
                        if let pulse = effect.airportPulse {
                            let outward = pulse.direction == .outward
                            let phase = outward ? pulse.progress : 1 - pulse.progress
                            let diameter = style.activity.airportLineLength * (0.8 + 1.8 * phase)
                            var pulseContext = markContext
                            pulseContext.opacity *= 0.18 * sin(.pi * pulse.progress)
                            pulseContext.stroke(
                                Path(ellipseIn: CGRect(
                                    x: -diameter / 2,
                                    y: -diameter / 2,
                                    width: diameter,
                                    height: diameter,
                                )),
                                with: .color(markColor),
                                lineWidth: 0.75,
                            )
                        }
                        if airlineAccentsEnabled,
                           let brand = descriptor.brand,
                           let rgb = style.aircraft[brand]
                        {
                            brandDotColor = rgb.color(
                                brightness: style.markLuminance *
                                    style.aircraft.brandDotBrightnessMultiplier,
                                intensity: intensityMultiplier,
                            )
                        }
                    case let .airport(descriptor):
                        renderedMarkSize = style.activity.airportLineLength
                        markContext.opacity *= style.activity.airportOpacity *
                            (descriptor.certainty == .inferred
                                ? style.activity.inferredOpacityMultiplier
                                : 1)
                        let halfLength = style.activity.airportLineLength / 2
                        var runway = Path()
                        runway.move(to: CGPoint(x: 0, y: -halfLength))
                        runway.addLine(to: CGPoint(x: 0, y: halfLength))
                        markContext.stroke(
                            runway,
                            with: .color(markColor),
                            style: StrokeStyle(
                                lineWidth: style.activity.airportLineWidth,
                                lineCap: .round,
                            ),
                        )
                        markContext.fill(
                            Path(ellipseIn: CGRect(x: -1.5, y: -1.5, width: 3, height: 3)),
                            with: .color(markColor),
                        )
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
                    let primaryStyle = style.label[label.primaryRole]
                    let primaryLabelColor = Color(
                        white: style.markLuminance * primaryStyle.luminanceMultiplier *
                            intensityMultiplier,
                    )
                    let labelPoint = CGPoint(
                        x: point.x + renderedMarkSize / 2 + style.label.offset,
                        y: point.y,
                    )
                    var text = label.primaryRole == .detail
                        ? detailText(
                            label.primary,
                            color: detailLabelColor,
                            brandDotColor: brandDotColor,
                        )
                        : Text(verbatim: label.primary)
                        .font(primaryStyle.font)
                        .tracking(label.secondary == nil ? 0 : style.label.routeTracking)
                        .foregroundStyle(primaryLabelColor)
                    if let secondary = label.secondary {
                        let secondaryText = detailText(
                            secondary,
                            color: detailLabelColor,
                            brandDotColor: brandDotColor,
                        )
                        text = Text("\(text)\n\(secondaryText)")
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
    }

    private func detailText(
        _ value: String,
        color: Color,
        brandDotColor: Color?,
    ) -> Text {
        let valueText = Text(verbatim: value)
            .font(style.label.detail.font)
            .foregroundStyle(color)
        guard let brandDotColor else { return valueText }
        let dotText = Text(verbatim: "● ")
            .font(style.label.detail.font)
            .foregroundStyle(brandDotColor)
        return Text("\(dotText)\(valueText)")
    }

    private func drawCue(
        _ activity: FlightActivity?,
        opacity: Double,
        in context: inout GraphicsContext,
        markSize: CGFloat,
        color: Color,
    ) {
        guard let activity, activity != .overflight, opacity > 0 else { return }
        let stage: FlightActivityStage = switch activity {
            case .overflight: .inbound
            case let .arrival(_, stage, _), let .departure(_, stage, _): stage
        }
        let certaintyMultiplier = activity.certainty == .inferred
            ? style.activity.inferredOpacityMultiplier
            : 1
        var cueContext = context
        cueContext.opacity *= style.activity.confirmedOpacity * certaintyMultiplier * opacity
        let rect = CGRect(
            x: -markSize / 2,
            y: -markSize / 2,
            width: markSize,
            height: markSize,
        )
        cueContext.stroke(
            AircraftActivityCueShape(stage: stage).path(in: rect),
            with: .color(color),
            style: StrokeStyle(
                lineWidth: style.activity.cueLineWidth,
                lineCap: .round,
                lineJoin: .round,
            ),
        )
    }
}

/// An equatable static surface whose paths change only with projected geography.
private struct ProjectionLinesCanvas: View, Equatable {
    let layerID: LayerID
    let lines: ProjectedLineCollection
    let opacity: Double
    let intensityMultiplier: Double
    let geographyIntensityMultiplier: Double
    let style: ThrowStylesheet.ProjectionStyle

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layerID == rhs.layerID &&
            lhs.lines.id == rhs.lines.id &&
            lhs.opacity == rhs.opacity &&
            lhs.intensityMultiplier == rhs.intensityMultiplier &&
            lhs.geographyIntensityMultiplier == rhs.geographyIntensityMultiplier &&
            lhs.style == rhs.style
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let layerIntensity = layerID == .geography ? geographyIntensityMultiplier : 1
            guard lines.segments.isEmpty == false, layerIntensity > 0
            else { return }

            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            var paths: [ProjectionLineStyleID: Path] = [:]
            for segment in lines.segments {
                if segment.startsNewSubpath {
                    paths[segment.styleID, default: Path()].move(
                        to: point(segment.start, origin: origin, side: side),
                    )
                }
                paths[segment.styleID, default: Path()].addLine(
                    to: point(segment.end, origin: origin, side: side),
                )
            }

            var lineContext = context
            lineContext.opacity = opacity
            let geographyOrder = style.geography.renderOrder.map(
                ProjectionLineStyleID.init(geographyKind:),
            )
            let otherStyles = paths.keys
                .filter { $0.geographyKind == nil }
                .sorted { $0.rawValue < $1.rawValue }
            for styleID in geographyOrder + otherStyles {
                guard let path = paths[styleID], path.isEmpty == false else { continue }
                let appearance = style.geography[styleID.geographyKind ?? .primaryRoad]
                let color = Color(
                    white: intensityMultiplier * layerIntensity *
                        appearance.luminance,
                )
                lineContext.stroke(
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
                name: "Experience Exchange At Black",
                configurations: projectorAspectConfigurations,
                settle: .immediate,
            ) {
                let session = ThrowSession.fixture()
                session.projectionSurfaceOpacity = 0
                return ProjectionSurface(session: session, presentation: .preview)
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
                name: "Flight Activity Map",
                configurations: projectorAspectConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(
                    session: .activitySnapshotFixture(mode: .map),
                    presentation: .preview,
                )
                .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Flight Activity True Sky",
                configurations: projectorAspectConfigurations,
                settle: .immediate,
            ) {
                ProjectionSurface(
                    session: .activitySnapshotFixture(mode: .trueSky),
                    presentation: .preview,
                )
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
