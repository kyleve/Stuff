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
    private var lastPresentationSignature: ProjectionPresentationSignature?
    private var modeTransition: ModeTransition?
    private var correctionTransition: CorrectionTransition?
    private var presentationState = PresentationState()

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
        routeResults: [FlightCallsign: FlightRouteResult],
        availability: MarkAvailability,
    ) async throws -> LayerFrame {
        try await flightsRuntime.frame(
            for: FlightsLayerInput(
                snapshot: snapshot,
                observer: observer,
                labelMode: labelMode,
                routeResults: routeResults,
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
        let effects = presentationState.effects(
            layerFrame: layerFrame,
            projectedFrame: frame,
            at: generatedAt,
            observationChanged: observationChanged,
            reduceMotion: reduceMotion,
        )
        return ProjectionFrameWorkerOutput(
            frame: frame,
            geographyHealth: geographyResult.health,
            effects: effects,
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
        lastPresentationSignature = nil
        modeTransition = nil
        correctionTransition = nil
        presentationState = PresentationState()
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
        guard let previousFrame else {
            let resolvedTarget = labelResolver.resolve(target)
            lastPresentationSignature = ProjectionPresentationSignature(frame: resolvedTarget)
            return resolvedTarget
        }
        if previousFrame.mode != target.mode, modeTransition?.targetMode != target.mode {
            modeTransition = ModeTransition(
                startedAt: date,
                source: previousFrame,
                targetMode: target.mode,
            )
            correctionTransition = nil
            labelResolver = ProjectionLabelCollisionResolver()
        }
        let resolvedTarget = labelResolver.resolve(target)
        let presentationSignature = ProjectionPresentationSignature(frame: resolvedTarget)
        let presentationChanged = lastPresentationSignature != presentationSignature
        lastPresentationSignature = presentationSignature

        if let transition = modeTransition {
            // Resolve the destination layout before it can become visible.
            // Source labels fade to zero, then resolved target labels replace
            // them at black and fade back in without a visible placement jump.
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

        if observationChanged || presentationChanged {
            correctionTransition = CorrectionTransition(
                startedAt: date,
                source: previousFrame,
                interpolatesPosition: observationChanged,
            )
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
                return resolvedTarget
            }
            return morph(
                source: transition.source,
                target: resolvedTarget,
                progress: progress,
                interpolatesPosition: transition.interpolatesPosition && reduceMotion == false,
                transitionsLabels: false,
            )
        }
        return resolvedTarget
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
                let duration = if case .airport = mark.glyph {
                    AnimationDuration.anchor
                } else {
                    AnimationDuration.presence
                }
                let insertionProgress = transitionsLabels
                    ? 1
                    : min(1, progress * AnimationDuration.correction / duration)
                return ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: usesSourceLabels ? nil : mark.label,
                    secondaryProminence: mark.secondaryProminence,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * insertionProgress,
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
            let positionProgress = interpolatesPosition ? cubicEaseOut(progress) : progress
            return ProjectedMark(
                id: mark.id,
                point: interpolatesPosition
                    ? ProjectionPoint(
                        x: old.point.x + (mark.point.x - old.point.x) * positionProgress,
                        y: old.point.y + (mark.point.y - old.point.y) * positionProgress,
                    )
                    : mark.point,
                range: mark.range,
                glyph: mark.glyph,
                label: transitionedLabel.label,
                secondaryProminence: old.secondaryProminence +
                    (mark.secondaryProminence - old.secondaryProminence) * progress,
                orientationDegrees: interpolatesPosition
                    ? interpolatedAngle(
                        from: old.orientationDegrees,
                        to: mark.orientationDegrees,
                        progress: positionProgress,
                    )
                    : mark.orientationDegrees,
                opacity: old.opacity + (mark.opacity - old.opacity) * progress,
                labelOpacity: transitionedLabel.opacity * labelPhaseOpacity,
                altitudeIsApproximate: mark.altitudeIsApproximate,
            )
        }
        if transitionsLabels == false, progress < 1 {
            marks.append(contentsOf: source.marks.compactMap { mark in
                guard targetIDs.contains(mark.id) == false else { return nil }
                let duration = removalDuration(for: mark)
                let removalProgress = min(
                    1,
                    progress * AnimationDuration.correction / duration,
                )
                guard removalProgress < 1 else { return nil }
                return ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: mark.label,
                    secondaryProminence: mark.secondaryProminence,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * (1 - removalProgress),
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

    private func cubicEaseOut(_ progress: Double) -> Double {
        1 - pow(1 - progress, 3)
    }

    private func removalDuration(for mark: ProjectedMark) -> TimeInterval {
        if case let .aircraft(descriptor) = mark.glyph,
           case let .arrival(context, .approach, _) = descriptor.activity,
           context.aircraftDistance.value <= 8
        {
            return AnimationDuration.completion
        }
        if case .airport = mark.glyph { return AnimationDuration.anchor }
        return AnimationDuration.presence
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
                    secondaryProminence: mark.secondaryProminence,
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
    let interpolatesPosition: Bool
}

private struct ProjectionPresentationSignature: Equatable {
    let marks: Set<Mark>

    init(frame: ProjectionFrame) {
        marks = Set(frame.marks.map(Mark.init))
    }

    struct Mark: Hashable {
        let id: LayerMarkID
        let glyph: ProjectionGlyph
        let label: ProjectionLabel?
        let secondaryProminence: Double

        init(mark: ProjectedMark) {
            id = mark.id
            glyph = mark.glyph
            label = mark.label
            secondaryProminence = mark.secondaryProminence
        }
    }
}

private struct TransitionedLabel {
    let label: ProjectionLabel?
    let opacity: Double
}

private enum AnimationDuration {
    static let mode = 1.2
    static let correction = 0.75
    static let presence = 0.25
    static let anchor = 0.4
    static let completion = 0.5
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
    let effects: [LayerMarkID: ProjectionMarkEffect]
}

extension ProjectionFrameWorker {
    fileprivate struct PresentationState {
        private static let absenceForReplay: TimeInterval = 60
        private static let acquisitionDuration: TimeInterval = 0.9
        private static let cueDuration: TimeInterval = 0.35
        private static let completionDuration: TimeInterval = 0.5

        private struct AircraftEntry {
            var lastSemanticPresence: Date
            var absentSince: Date?
            var acquisitionStartedAt: Date?
            var activity: FlightActivity
            var previousActivity: FlightActivity?
            var activityChangedAt: Date?
            var completionStartedAt: Date?
        }

        private struct PulseEntry {
            let direction: AirportPulseDirection
            let startedAt: Date
        }

        private var aircraft: [LayerMarkID: AircraftEntry] = [:]
        private var pulses: [AirportID: PulseEntry] = [:]
        private var lastSemanticIDs: Set<LayerMarkID> = []

        mutating func effects(
            layerFrame: LayerFrame?,
            projectedFrame: ProjectionFrame,
            at date: Date,
            observationChanged: Bool,
            reduceMotion: Bool,
        ) -> [LayerMarkID: ProjectionMarkEffect] {
            let semanticAircraft = layerFrame?.marks.compactMap { mark -> (
                LayerMarkID,
                FlightActivity
            )? in
                guard case let .aircraft(descriptor) = mark.glyph else { return nil }
                return (mark.id, descriptor.activity)
            } ?? []
            let semanticIDs = Set(semanticAircraft.map(\.0))

            if observationChanged {
                for id in lastSemanticIDs.subtracting(semanticIDs) {
                    guard var entry = aircraft[id] else { continue }
                    entry.absentSince = date
                    if case let .arrival(context, .approach, _) = entry.activity,
                       context.aircraftDistance.value <= 8
                    {
                        entry.completionStartedAt = date
                        pulses[context.airport.id] = PulseEntry(direction: .inward, startedAt: date)
                    }
                    aircraft[id] = entry
                }
            }

            for (id, activity) in semanticAircraft {
                if var entry = aircraft[id] {
                    let canReplay = entry.absentSince.map {
                        date.timeIntervalSince($0) >= Self.absenceForReplay
                    } ?? false
                    if canReplay { entry.acquisitionStartedAt = date }
                    entry.absentSince = nil
                    entry.lastSemanticPresence = date
                    if entry.activity != activity {
                        entry.previousActivity = entry.activity
                        entry.activity = activity
                        entry.activityChangedAt = date
                    }
                    aircraft[id] = entry
                } else {
                    aircraft[id] = AircraftEntry(
                        lastSemanticPresence: date,
                        absentSince: nil,
                        acquisitionStartedAt: date,
                        activity: activity,
                        previousActivity: nil,
                        activityChangedAt: nil,
                        completionStartedAt: nil,
                    )
                    if observationChanged,
                       case let .departure(context, .initialClimb, _) = activity,
                       context.aircraftDistance.value <= 8
                    {
                        pulses[context.airport.id] = PulseEntry(
                            direction: .outward,
                            startedAt: date,
                        )
                    }
                }
            }
            if observationChanged { lastSemanticIDs = semanticIDs }

            var result: [LayerMarkID: ProjectionMarkEffect] = [:]
            for mark in projectedFrame.marks {
                switch mark.glyph {
                    case .aircraft:
                        guard let entry = aircraft[mark.id] else { continue }
                        let acquisition = reduceMotion ? nil : progress(
                            from: entry.acquisitionStartedAt,
                            at: date,
                            duration: Self.acquisitionDuration,
                        )
                        let cue = cueEffect(entry: entry, at: date, reduceMotion: reduceMotion)
                        let scale: Double = if reduceMotion {
                            1
                        } else if let completion = progress(
                            from: entry.completionStartedAt,
                            at: date,
                            duration: Self.completionDuration,
                        ) {
                            1 - 0.3 * completion
                        } else if case let .departure(context, .initialClimb, _) = entry.activity,
                                  context.aircraftDistance.value <= 8,
                                  let acquisition
                        {
                            0.7 + 0.3 * acquisition
                        } else {
                            1
                        }
                        result[mark.id] = ProjectionMarkEffect(
                            scale: scale,
                            acquisitionProgress: acquisition,
                            activityCue: cue,
                            airportPulse: nil,
                        )
                    case let .airport(descriptor):
                        guard reduceMotion == false,
                              let pulse = pulses[descriptor.airportID],
                              let pulseProgress = progress(
                                  from: pulse.startedAt,
                                  at: date,
                                  duration: Self.completionDuration,
                              )
                        else { continue }
                        result[mark.id] = ProjectionMarkEffect(
                            scale: 1,
                            acquisitionProgress: nil,
                            activityCue: nil,
                            airportPulse: AirportPulseEffect(
                                direction: pulse.direction,
                                progress: pulseProgress,
                            ),
                        )
                    case .star, .satellite:
                        break
                }
            }
            pulses = pulses.filter {
                date.timeIntervalSince($0.value.startedAt) < Self.completionDuration
            }
            aircraft = aircraft.filter { _, entry in
                entry.absentSince
                    .map { date.timeIntervalSince($0) < Self.absenceForReplay * 2 } ?? true
            }
            return result
        }

        private func cueEffect(
            entry: AircraftEntry,
            at date: Date,
            reduceMotion: Bool,
        ) -> ActivityCueEffect? {
            guard entry.activity != .overflight else { return nil }
            guard reduceMotion == false,
                  let transition = progress(
                      from: entry.activityChangedAt,
                      at: date,
                      duration: Self.cueDuration,
                  ),
                  let previous = entry.previousActivity
            else {
                return ActivityCueEffect(
                    previous: nil,
                    previousOpacity: 0,
                    current: entry.activity,
                    currentOpacity: 1,
                )
            }
            return ActivityCueEffect(
                previous: previous,
                previousOpacity: 1 - transition,
                current: entry.activity,
                currentOpacity: transition,
            )
        }

        private func progress(
            from start: Date?,
            at date: Date,
            duration: TimeInterval,
        ) -> Double? {
            guard let start else { return nil }
            let value = date.timeIntervalSince(start) / duration
            guard value < 0.999_999 else { return nil }
            return min(1, max(0, value))
        }
    }
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
