import Foundation
import ThrowCore

/// Off-main-actor projection, label layout, correction easing, and mode morphing.
actor ProjectionFrameWorker {
    private let engine = ProjectionEngine()
    private let flightsRuntime: FlightsLayerRuntime
    private var labelResolver = ProjectionLabelCollisionResolver()
    private var previousFrame: ProjectionFrame?
    private var lastLayerObservedAt: Date?
    private var modeTransition: ModeTransition?
    private var correctionTransition: CorrectionTransition?

    init(flightsRuntime: FlightsLayerRuntime) {
        self.flightsRuntime = flightsRuntime
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
        layerFrame: LayerFrame,
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        generatedAt: Date,
        reduceMotion: Bool,
    ) throws -> ProjectionFrame {
        let observationChanged = lastLayerObservedAt.map { $0 != layerFrame.observedAt } ?? false
        let target = try engine.frame(
            layerFrames: [layerFrame],
            observer: observer,
            viewport: viewport,
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1, height: 1),
            generatedAt: generatedAt,
        )
        let frame = animate(
            target: target,
            at: generatedAt,
            observationChanged: observationChanged,
            reduceMotion: reduceMotion,
        )
        previousFrame = frame
        lastLayerObservedAt = layerFrame.observedAt
        return frame
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
        return ProjectionFrame(mode: target.mode, generatedAt: target.generatedAt, marks: marks)
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

private struct ModeTransition {
    let startedAt: Date
    let source: ProjectionFrame
    let targetMode: ProjectionMode
}

private struct CorrectionTransition {
    let startedAt: Date
    let source: ProjectionFrame
}
