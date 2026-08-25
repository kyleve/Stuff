import Foundation
import ThrowCore

/// Off-main-actor projection, label layout, correction easing, and mode morphing.
actor ProjectionFrameWorker {
    private let engine = ProjectionEngine()
    private let flightsRuntime: FlightsLayerRuntime
    private let geographyRuntime: GeographyLayerRuntime
    private let geographyLogger: any GeographyLogging
    private var labelResolver = ProjectionLabelCollisionResolver()
    private var geographyLayerLoadTask: Task<LayerFrame, Error>?
    private var geographyLoadFailed = false
    private var geographyProjectionCache: GeographyProjectionCache?
    private var geographyProjectionSequence: UInt64 = 0
    private var previousFrame: ProjectionFrame?
    private var lastLayerObservedAt: Date?
    private var modeTransition: ModeTransition?
    private var correctionTransition: CorrectionTransition?

    init(
        flightsRuntime: FlightsLayerRuntime,
        geographyRuntime: GeographyLayerRuntime,
        geographyLogger: any GeographyLogging,
    ) {
        self.flightsRuntime = flightsRuntime
        self.geographyRuntime = geographyRuntime
        self.geographyLogger = geographyLogger
    }

    func layerFrame(
        snapshot: AircraftSnapshot,
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
    ) async throws -> LayerFrame {
        try await flightsRuntime.frame(
            for: FlightsLayerInput(
                snapshot: snapshot,
                observer: observer,
                labelMode: labelMode,
            ),
        )
    }

    func frame(
        layerFrame: LayerFrame?,
        geographyEnabled: Bool,
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        generatedAt: Date,
        reduceMotion: Bool,
    ) async throws -> ProjectionFrameWorkerOutput {
        try Task.checkCancellation()
        let observationChanged = lastLayerObservedAt != layerFrame?.observedAt
        let geographyResult: GeographyProjectionResult
        do {
            geographyResult = try await projectedGeography(
                isEnabled: geographyEnabled,
                observer: observer,
                viewport: viewport,
                calibration: calibration,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            geographyLoadFailed = true
            geographyResult = .unavailable
        }
        try Task.checkCancellation()
        let target = try engine.frame(
            layerFrames: layerFrame.map { [$0] } ?? [],
            geography: geographyResult.projection,
            observer: observer,
            viewport: viewport,
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1, height: 1),
            generatedAt: generatedAt,
        )
        try Task.checkCancellation()
        let frame = animate(
            target: target,
            at: generatedAt,
            observationChanged: observationChanged,
            reduceMotion: reduceMotion,
        )
        try Task.checkCancellation()
        previousFrame = frame
        lastLayerObservedAt = layerFrame?.observedAt
        return ProjectionFrameWorkerOutput(
            frame: frame,
            geographyHealth: geographyResult.health,
        )
    }

    private func projectedGeography(
        isEnabled: Bool,
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
    ) async throws -> GeographyProjectionResult {
        guard isEnabled, case .map = viewport else { return .notRequested }
        guard geographyLoadFailed == false else { return .unavailable }
        let key = GeographyProjectionCacheKey(
            observer: observer,
            viewport: viewport,
            calibration: calibration,
        )
        if geographyProjectionCache?.key == key {
            guard let projection = geographyProjectionCache?.projection else {
                preconditionFailure("A matching geography cache must contain a projection")
            }
            return .projected(projection)
        }
        let loadTask: Task<LayerFrame, Error>
        if let geographyLayerLoadTask {
            loadTask = geographyLayerLoadTask
        } else {
            loadTask = Task(name: "Throw load bundled geography") {
                [geographyRuntime, geographyLogger] in
                do {
                    return try await geographyRuntime.frame(for: GeographyLayerInput())
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    geographyLogger.record(
                        GeographyLogEvent(failureCategory: geographyFailureCategory(for: error)),
                    )
                    throw error
                }
            }
            geographyLayerLoadTask = loadTask
        }
        let layerFrame = try await loadTask.value
        try Task.checkCancellation()
        let segments = try engine.geographySegments(
            lines: layerFrame.geographicLines,
            observer: observer,
            viewport: viewport,
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )
        try Task.checkCancellation()
        geographyProjectionSequence &+= 1
        let projection = ProjectedGeography(
            id: GeographyProjectionID(rawValue: geographyProjectionSequence),
            segments: segments,
        )
        geographyProjectionCache = GeographyProjectionCache(key: key, projection: projection)
        return .projected(projection)
    }

    func reset() {
        previousFrame = nil
        lastLayerObservedAt = nil
        modeTransition = nil
        correctionTransition = nil
        labelResolver = ProjectionLabelCollisionResolver()
    }

    private func animate(
        target: ProjectionFrame,
        at date: Date,
        observationChanged: Bool,
        reduceMotion: Bool,
    ) -> ProjectionFrame {
        guard let previousFrame else { return labelResolver.resolve(target) }
        if previousFrame.mode != target.mode, modeTransition?.targetMode != target.mode {
            modeTransition = ModeTransition(
                startedAt: date,
                source: previousFrame,
                targetMode: target.mode,
            )
            correctionTransition = nil
            labelResolver = ProjectionLabelCollisionResolver()
        }

        if let transition = modeTransition {
            // Resolve the destination layout before it can become visible.
            // Source labels fade to zero, then resolved target labels replace
            // them at black and fade back in without a visible placement jump.
            let resolvedTarget = labelResolver.resolve(target)
            let progress = min(1, max(0, date.timeIntervalSince(transition.startedAt) / 1.2))
            if progress >= 1 {
                modeTransition = nil
                return resolvedTarget
            }
            if reduceMotion {
                return fadeThroughBlack(
                    source: transition.source,
                    target: resolvedTarget,
                    progress: progress,
                )
            }
            return morph(
                source: transition.source,
                target: resolvedTarget,
                progress: progress,
                transitionsLabels: true,
            )
        }

        if observationChanged {
            correctionTransition = reduceMotion
                ? nil
                : CorrectionTransition(startedAt: date, source: previousFrame)
        }
        guard reduceMotion == false else {
            correctionTransition = nil
            return labelResolver.resolve(target)
        }
        if let transition = correctionTransition {
            let progress = min(1, max(0, date.timeIntervalSince(transition.startedAt) / 0.75))
            if progress >= 1 {
                correctionTransition = nil
                return labelResolver.resolve(target)
            }
            let corrected = morph(
                source: transition.source,
                target: target,
                progress: progress,
                transitionsLabels: false,
            )
            return labelResolver.resolve(corrected)
        }
        return labelResolver.resolve(target)
    }

    private func morph(
        source: ProjectionFrame,
        target: ProjectionFrame,
        progress: Double,
        transitionsLabels: Bool,
    ) -> ProjectionFrame {
        let sourceByID = Dictionary(uniqueKeysWithValues: source.marks.map { ($0.id, $0) })
        let usesSourceLabels = transitionsLabels && progress < 0.5
        let labelPhaseOpacity = transitionsLabels ? modeLabelOpacity(at: progress) : 1
        let marks = target.marks.map { mark in
            guard let old = sourceByID[mark.id] else {
                return ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: usesSourceLabels ? nil : mark.label,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity,
                    labelOpacity: usesSourceLabels ? 0 : mark.labelOpacity * labelPhaseOpacity,
                    altitudeIsApproximate: mark.altitudeIsApproximate,
                )
            }
            let label = usesSourceLabels ? old.label : mark.label
            let baseLabelOpacity = usesSourceLabels ? old.labelOpacity : mark.labelOpacity
            return ProjectedMark(
                id: mark.id,
                point: ProjectionPoint(
                    x: old.point.x + (mark.point.x - old.point.x) * progress,
                    y: old.point.y + (mark.point.y - old.point.y) * progress,
                ),
                range: mark.range,
                glyph: mark.glyph,
                label: label,
                orientationDegrees: interpolatedAngle(
                    from: old.orientationDegrees,
                    to: mark.orientationDegrees,
                    progress: progress,
                ),
                opacity: old.opacity + (mark.opacity - old.opacity) * progress,
                labelOpacity: baseLabelOpacity * labelPhaseOpacity,
                altitudeIsApproximate: mark.altitudeIsApproximate,
            )
        }
        let geography = transitionGeography(
            source: source,
            target: target,
            progress: progress,
            transitionsMode: transitionsLabels,
        )
        return ProjectionFrame(
            mode: target.mode,
            generatedAt: target.generatedAt,
            geography: geography.projection,
            geographyOpacity: geography.opacity,
            marks: marks,
        )
    }

    private func fadeThroughBlack(
        source: ProjectionFrame,
        target: ProjectionFrame,
        progress: Double,
    ) -> ProjectionFrame {
        let usesSource = progress < 0.5
        let frame = usesSource ? source : target
        let opacity = usesSource ? 1 - progress * 2 : (progress - 0.5) * 2
        return ProjectionFrame(
            mode: target.mode,
            generatedAt: target.generatedAt,
            geography: frame.geography,
            geographyOpacity: frame.geographyOpacity * opacity,
            marks: frame.marks.map { mark in
                ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: mark.label,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * opacity,
                    labelOpacity: mark.labelOpacity,
                    altitudeIsApproximate: mark.altitudeIsApproximate,
                )
            },
        )
    }

    private func transitionGeography(
        source: ProjectionFrame,
        target: ProjectionFrame,
        progress: Double,
        transitionsMode: Bool,
    ) -> GeographyTransitionFrame {
        guard transitionsMode else {
            return GeographyTransitionFrame(
                projection: target.geography,
                opacity: target.geographyOpacity,
            )
        }
        let usesSource = progress < 0.5
        let frame = usesSource ? source : target
        let opacity = usesSource ? 1 - progress * 2 : (progress - 0.5) * 2
        return GeographyTransitionFrame(
            projection: frame.geography,
            opacity: frame.geographyOpacity * opacity,
        )
    }

    private func modeLabelOpacity(at progress: Double) -> Double {
        if progress < 0.5 {
            1 - progress * 2
        } else {
            (progress - 0.5) * 2
        }
    }

    private func interpolatedAngle(
        from: Double?,
        to: Double?,
        progress: Double,
    ) -> Double? {
        guard let from, let to else { return to ?? from }
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return from + delta * progress
    }
}

private func geographyFailureCategory(
    for error: any Error,
) -> GeographyLogEvent.FailureCategory {
    guard let geographyError = error as? GeographyDataError else { return .unexpected }
    switch geographyError {
        case .resourceMissing: return .resourceMissing
        case .invalidArchive: return .invalidArchive
    }
}

private struct ModeTransition {
    let startedAt: Date
    let source: ProjectionFrame
    let targetMode: ProjectionMode
}

private struct CorrectionTransition {
    let startedAt: Date
    let source: ProjectionFrame
}

private struct GeographyProjectionCacheKey: Equatable {
    let observer: ObserverPosition
    let viewport: ProjectionViewport
    let calibration: ProjectionCalibration
}

private struct GeographyProjectionCache {
    let key: GeographyProjectionCacheKey
    let projection: ProjectedGeography
}

private struct GeographyTransitionFrame {
    let projection: ProjectedGeography?
    let opacity: Double
}

struct ProjectionFrameWorkerOutput {
    let frame: ProjectionFrame
    let geographyHealth: GeographyLayerHealth
}

private enum GeographyProjectionResult {
    case notRequested
    case projected(ProjectedGeography)
    case unavailable

    var projection: ProjectedGeography? {
        switch self {
            case .notRequested, .unavailable: nil
            case let .projected(projection): projection
        }
    }

    var health: GeographyLayerHealth {
        switch self {
            case .notRequested: .idle
            case .projected: .available
            case .unavailable: .unavailable
        }
    }
}
