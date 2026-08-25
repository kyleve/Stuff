import Foundation
import ThrowCore

/// Off-main-actor projection, label layout, correction easing, and mode morphing.
actor ProjectionFrameWorker {
    private let engine = ProjectionEngine()
    private let flightsRuntime: FlightsLayerRuntime
    private let geographyRuntime: GeographyLayerRuntime
    private let geographyLogger: any GeographyLogging
    private var labelResolver = ProjectionLabelCollisionResolver()
    private var loadedGeographyLayerFrame: LayerFrame?
    private var geographyLayerLoadTask: Task<Void, Never>?
    private var geographyLoadWaiters: [UInt64: CheckedContinuation<LayerFrame, any Error>] = [:]
    #if DEBUG
        private var geographyWaiterCountObservers: [GeographyWaiterCountObserver] = []
    #endif
    private var nextGeographyWaiterID: UInt64 = 0
    private var geographyLoadGeneration: UInt64 = 0
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
        routes: [FlightCallsign: FlightRoute],
        availability: MarkAvailability,
    ) async throws -> LayerFrame {
        try await flightsRuntime.frame(
            for: FlightsLayerInput(
                snapshot: snapshot,
                observer: observer,
                labelMode: labelMode,
                routes: routes,
                availability: availability,
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
        let layerFrame = try await loadGeographyLayerFrame()
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

    private func loadGeographyLayerFrame() async throws -> LayerFrame {
        if let loadedGeographyLayerFrame {
            return loadedGeographyLayerFrame
        }
        startGeographyLoadIfNeeded()
        let waiterID = nextGeographyWaiterID
        nextGeographyWaiterID &+= 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let loadedGeographyLayerFrame {
                    continuation.resume(returning: loadedGeographyLayerFrame)
                } else {
                    geographyLoadWaiters[waiterID] = continuation
                    notifyGeographyWaiterCountObservers()
                }
            }
        } onCancel: {
            Task { await self.cancelGeographyWaiter(waiterID) }
        }
    }

    private func startGeographyLoadIfNeeded() {
        guard loadedGeographyLayerFrame == nil, geographyLayerLoadTask == nil else { return }
        geographyLoadGeneration &+= 1
        let generation = geographyLoadGeneration
        geographyLayerLoadTask = Task(name: "Throw load bundled geography") {
            [geographyRuntime, geographyLogger, weak self] in
            let result: Result<LayerFrame, any Error>
            do {
                result = try await .success(
                    geographyRuntime.frame(for: GeographyLayerInput()),
                )
            } catch is CancellationError {
                result = .failure(CancellationError())
            } catch {
                geographyLogger.record(
                    GeographyLogEvent(failureCategory: geographyFailureCategory(for: error)),
                )
                result = .failure(error)
            }
            await self?.finishGeographyLoad(result, generation: generation)
        }
    }

    private func finishGeographyLoad(
        _ result: Result<LayerFrame, any Error>,
        generation: UInt64,
    ) {
        guard generation == geographyLoadGeneration else { return }
        geographyLayerLoadTask = nil
        if case let .success(frame) = result {
            loadedGeographyLayerFrame = frame
        } else if case let .failure(error) = result, !(error is CancellationError) {
            geographyLoadFailed = true
        }
        let waiters = geographyLoadWaiters
        geographyLoadWaiters = [:]
        notifyGeographyWaiterCountObservers()
        for continuation in waiters.values {
            continuation.resume(with: result)
        }
    }

    private func cancelGeographyWaiter(_ waiterID: UInt64) {
        geographyLoadWaiters.removeValue(forKey: waiterID)?.resume(
            throwing: CancellationError(),
        )
        notifyGeographyWaiterCountObservers()
        guard geographyLoadWaiters.isEmpty, loadedGeographyLayerFrame == nil else { return }
        geographyLayerLoadTask?.cancel()
        geographyLayerLoadTask = nil
        geographyLoadGeneration &+= 1
    }

    func reset() {
        previousFrame = nil
        lastLayerObservedAt = nil
        modeTransition = nil
        correctionTransition = nil
        labelResolver = ProjectionLabelCollisionResolver()
    }

    #if DEBUG
        func waitUntilGeographyLoadWaiterCount(_ expectedCount: Int) async {
            guard geographyLoadWaiters.count != expectedCount else { return }
            await withCheckedContinuation { continuation in
                geographyWaiterCountObservers.append(
                    GeographyWaiterCountObserver(
                        expectedCount: expectedCount,
                        continuation: continuation,
                    ),
                )
            }
        }
    #endif

    private func notifyGeographyWaiterCountObservers() {
        #if DEBUG
            let matching = geographyWaiterCountObservers.filter {
                $0.expectedCount == geographyLoadWaiters.count
            }
            geographyWaiterCountObservers.removeAll {
                $0.expectedCount == geographyLoadWaiters.count
            }
            for observer in matching {
                observer.continuation.resume()
            }
        #endif
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
            let progress = min(
                1,
                max(0, date.timeIntervalSince(transition.startedAt) / AnimationDuration.mode),
            )
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
                interpolatesPosition: true,
                transitionsLabels: true,
            )
        }

        if observationChanged {
            correctionTransition = CorrectionTransition(startedAt: date, source: previousFrame)
        }
        if let transition = correctionTransition {
            let progress = min(
                1,
                max(
                    0,
                    date.timeIntervalSince(transition.startedAt) / AnimationDuration.correction,
                ),
            )
            if progress >= 1 {
                correctionTransition = nil
                return labelResolver.resolve(target)
            }
            let resolvedTarget = labelResolver.resolve(target)
            return morph(
                source: transition.source,
                target: resolvedTarget,
                progress: progress,
                interpolatesPosition: reduceMotion == false,
                transitionsLabels: false,
            )
        }
        return labelResolver.resolve(target)
    }

    private func morph(
        source: ProjectionFrame,
        target: ProjectionFrame,
        progress: Double,
        interpolatesPosition: Bool,
        transitionsLabels: Bool,
    ) -> ProjectionFrame {
        let sourceByID = Dictionary(uniqueKeysWithValues: source.marks.map { ($0.id, $0) })
        let targetIDs = Set(target.marks.map(\.id))
        let usesSourceLabels = transitionsLabels && progress < 0.5
        let labelPhaseOpacity = transitionsLabels ? modeLabelOpacity(at: progress) : 1
        let presenceProgress = transitionsLabels
            ? 1
            : min(1, progress * AnimationDuration.correction / AnimationDuration.presence)
        var marks = target.marks.map { mark in
            guard let old = sourceByID[mark.id] else {
                return ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: usesSourceLabels ? nil : mark.label,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * presenceProgress,
                    labelOpacity: usesSourceLabels
                        ? 0
                        : mark.labelOpacity * labelPhaseOpacity,
                    altitudeIsApproximate: mark.altitudeIsApproximate,
                )
            }
            let transitionedLabel = transitionsLabels
                ? TransitionedLabel(
                    label: usesSourceLabels ? old.label : mark.label,
                    opacity: usesSourceLabels ? old.labelOpacity : mark.labelOpacity,
                )
                : transitionLabel(from: old, to: mark, progress: presenceProgress)
            return ProjectedMark(
                id: mark.id,
                point: interpolatesPosition
                    ? ProjectionPoint(
                        x: old.point.x + (mark.point.x - old.point.x) * progress,
                        y: old.point.y + (mark.point.y - old.point.y) * progress,
                    )
                    : mark.point,
                range: mark.range,
                glyph: mark.glyph,
                label: transitionedLabel.label,
                orientationDegrees: interpolatesPosition
                    ? interpolatedAngle(
                        from: old.orientationDegrees,
                        to: mark.orientationDegrees,
                        progress: progress,
                    )
                    : mark.orientationDegrees,
                opacity: interpolatesPosition
                    ? old.opacity + (mark.opacity - old.opacity) * progress
                    : mark.opacity,
                labelOpacity: transitionedLabel.opacity * labelPhaseOpacity,
                altitudeIsApproximate: mark.altitudeIsApproximate,
            )
        }
        if transitionsLabels == false, presenceProgress < 1 {
            marks.append(contentsOf: source.marks.compactMap { mark in
                guard targetIDs.contains(mark.id) == false else { return nil }
                return ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: mark.label,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * (1 - presenceProgress),
                    labelOpacity: mark.labelOpacity,
                    altitudeIsApproximate: mark.altitudeIsApproximate,
                )
            })
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

    private func transitionLabel(
        from source: ProjectedMark,
        to target: ProjectedMark,
        progress: Double,
    ) -> TransitionedLabel {
        guard source.label != target.label else {
            return TransitionedLabel(label: target.label, opacity: target.labelOpacity)
        }
        switch (source.label, target.label) {
            case (nil, let targetLabel?):
                return TransitionedLabel(
                    label: targetLabel,
                    opacity: target.labelOpacity * progress,
                )
            case (let sourceLabel?, nil):
                return TransitionedLabel(
                    label: progress < 1 ? sourceLabel : nil,
                    opacity: source.labelOpacity * (1 - progress),
                )
            case let (sourceLabel?, targetLabel?):
                if progress < 0.5 {
                    return TransitionedLabel(
                        label: sourceLabel,
                        opacity: source.labelOpacity * (1 - progress * 2),
                    )
                }
                return TransitionedLabel(
                    label: targetLabel,
                    opacity: target.labelOpacity * (progress - 0.5) * 2,
                )
            case (nil, nil):
                return TransitionedLabel(label: nil, opacity: 0)
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

private struct TransitionedLabel {
    let label: ProjectionLabel?
    let opacity: Double
}

private enum AnimationDuration {
    static let mode = 1.2
    static let correction = 0.75
    static let presence = 0.25
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

#if DEBUG
    private struct GeographyWaiterCountObserver {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }
#endif

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
