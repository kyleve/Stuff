import Foundation
import ThrowCore

/// Off-main-actor projection, label layout, correction easing, and mode morphing.
actor ProjectionFrameWorker {
    private struct ExperienceState {
        var labelResolver = ProjectionLabelCollisionResolver()
        var previousFrame: ProjectionFrame?
        var lastMarkRevisions: [LayerID: Date] = [:]
        var lastPresentationSignature: ProjectionPresentationSignature?
        var modeTransition: ModeTransition?
        var correctionTransition: CorrectionTransition?
        var targetHistory = ProjectionTargetHistory()
        var motionDiagnostics = ProjectionMotionDiagnosticsAccumulator()
        var presentationState = PresentationState()
    }

    private enum FrameInput {
        case checked(ProjectionExperienceInput)
        #if DEBUG
            case testing(
                experienceID: ProjectionExperienceID,
                layerFrames: [LayerFrame],
                geographyEnabled: Bool,
                viewport: ProjectionViewport,
            )
        #endif

        var experienceID: ProjectionExperienceID {
            switch self {
                case let .checked(input): input.experienceFrame.experienceID
                #if DEBUG
                    case let .testing(experienceID, _, _, _): experienceID
                #endif
            }
        }

        var layerFrames: [LayerFrame] {
            switch self {
                case let .checked(input): input.experienceFrame.layers
                #if DEBUG
                    case let .testing(_, layerFrames, _, _): layerFrames
                #endif
            }
        }

        var geographyEnabled: Bool {
            switch self {
                case let .checked(input): input.requestsGeography
                #if DEBUG
                    case let .testing(_, _, geographyEnabled, _): geographyEnabled
                #endif
            }
        }

        var viewport: ProjectionViewport {
            switch self {
                case let .checked(input): input.viewport
                #if DEBUG
                    case let .testing(_, _, _, viewport): viewport
                #endif
            }
        }
    }

    private let engine = ProjectionEngine()
    private let geographyRuntime: GeographyLayerRuntime
    private let geographyLogger: any GeographyLogging
    private let motionLogger: any ProjectionMotionLogging
    private var loadedGeographyLayerFrame: ProjectionLayerFrame<GeographyLayerKind>?
    private var geographyLayerLoadTask: Task<Void, Never>?
    private var geographyLoadWaiters: [
        UInt64: CheckedContinuation<ProjectionLayerFrame<GeographyLayerKind>, any Error>
    ] = [:]
    #if DEBUG
        private var geographyWaiterCountObservers: [GeographyWaiterCountObserver] = []
    #endif
    private var nextGeographyWaiterID: UInt64 = 0
    private var geographyLoadGeneration: UInt64 = 0
    private var geographyLoadFailed = false
    private var staticLineProjectionCache: [StaticLineProjectionCacheKey: ProjectedLineCollection] =
        [:]
    private var lineProjectionSequence: UInt64 = 0
    private var experienceStates: [ProjectionExperienceID: ExperienceState] = [:]

    init(
        geographyRuntime: GeographyLayerRuntime,
        geographyLogger: any GeographyLogging,
        motionLogger: any ProjectionMotionLogging,
    ) {
        self.geographyRuntime = geographyRuntime
        self.geographyLogger = geographyLogger
        self.motionLogger = motionLogger
    }

    /// Compatibility initializer for focused worker tests that still build a Flights runtime.
    init(
        flightsRuntime _: FlightsLayerRuntime,
        geographyRuntime: GeographyLayerRuntime,
        geographyLogger: any GeographyLogging,
        motionLogger: any ProjectionMotionLogging,
    ) {
        self.init(
            geographyRuntime: geographyRuntime,
            geographyLogger: geographyLogger,
            motionLogger: motionLogger,
        )
    }

    func frame(
        input: ProjectionExperienceInput,
        observer: ObserverPosition,
        mapCenter: GeoCoordinate,
        calibration: ProjectionCalibration,
        generatedAt: Date,
        reduceMotion: Bool,
    ) async throws -> ProjectionFrameWorkerOutput {
        try await frame(
            input: .checked(input),
            observer: observer,
            mapCenter: mapCenter,
            calibration: calibration,
            generatedAt: generatedAt,
            reduceMotion: reduceMotion,
        )
    }

    #if DEBUG
        func frame(
            layerFrame: LayerFrame?,
            geographyEnabled: Bool,
            observer: ObserverPosition,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
            generatedAt: Date,
            reduceMotion: Bool,
        ) async throws -> ProjectionFrameWorkerOutput {
            try await frame(
                layerFrame: layerFrame,
                geographyEnabled: geographyEnabled,
                observer: observer,
                mapCenter: observer.coordinate,
                viewport: viewport,
                calibration: calibration,
                generatedAt: generatedAt,
                reduceMotion: reduceMotion,
            )
        }

        func frame(
            layerFrame: LayerFrame?,
            geographyEnabled: Bool,
            observer: ObserverPosition,
            mapCenter: GeoCoordinate,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
            generatedAt: Date,
            reduceMotion: Bool,
        ) async throws -> ProjectionFrameWorkerOutput {
            try await frame(
                experienceID: .airAndSpace,
                layerFrames: layerFrame.map { [$0] } ?? [],
                geographyEnabled: geographyEnabled,
                observer: observer,
                mapCenter: mapCenter,
                viewport: viewport,
                calibration: calibration,
                generatedAt: generatedAt,
                reduceMotion: reduceMotion,
            )
        }

        func frame(
            experienceID: ProjectionExperienceID,
            layerFrames: [LayerFrame],
            geographyEnabled: Bool,
            observer: ObserverPosition,
            mapCenter: GeoCoordinate,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
            generatedAt: Date,
            reduceMotion: Bool,
        ) async throws -> ProjectionFrameWorkerOutput {
            try await frame(
                input: .testing(
                    experienceID: experienceID,
                    layerFrames: layerFrames,
                    geographyEnabled: geographyEnabled,
                    viewport: viewport,
                ),
                observer: observer,
                mapCenter: mapCenter,
                calibration: calibration,
                generatedAt: generatedAt,
                reduceMotion: reduceMotion,
            )
        }
    #endif

    private func frame(
        input: FrameInput,
        observer: ObserverPosition,
        mapCenter: GeoCoordinate,
        calibration: ProjectionCalibration,
        generatedAt: Date,
        reduceMotion: Bool,
    ) async throws -> ProjectionFrameWorkerOutput {
        try Task.checkCancellation()
        let experienceID = input.experienceID
        let layerFrames = input.layerFrames
        let geographyEnabled = input.geographyEnabled
        let viewport = input.viewport
        var experienceState = experienceStates[experienceID] ?? ExperienceState()
        let flightsLayerFrame = layerFrames.first { $0.layerID == .flights }
        let markRevisions = Dictionary(uniqueKeysWithValues: layerFrames.compactMap { frame in
            if case .marks = frame.content { (frame.layerID, frame.observedAt) } else { nil }
        })
        let observationChanged = experienceState.lastMarkRevisions != markRevisions
        let geographyResult: GeographyProjectionResult
        do {
            geographyResult = try await projectedGeography(
                isEnabled: geographyEnabled,
                mapCenter: mapCenter,
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
        let zOrders = Dictionary(
            uniqueKeysWithValues: LayerCatalog.standard.descriptors.map { ($0.id, $0.zOrder) },
        )
        var projectedLineLayers: [ProjectedLayer] = geographyResult.projection.map {
            [
                ProjectedLayer(
                    id: .geography,
                    zOrder: zOrders[.geography] ?? 0,
                    opacity: 1,
                    content: .lines($0),
                ),
            ]
        } ?? []
        for lineFrame in layerFrames {
            guard case .lines = lineFrame.content,
                  projectedLineLayers.contains(where: { $0.id == lineFrame.layerID }) == false
            else { continue }
            let projection = try projectedLineCollection(
                for: lineFrame,
                mapCenter: mapCenter,
                viewport: viewport,
                calibration: calibration,
            )
            projectedLineLayers.append(
                ProjectedLayer(
                    id: lineFrame.layerID,
                    zOrder: zOrders[lineFrame.layerID] ?? 0,
                    opacity: 1,
                    content: .lines(projection),
                ),
            )
        }
        let target: ProjectionFrame
        switch input {
            case let .checked(input):
                target = try engine.frame(
                    input: input,
                    projectedLineLayers: projectedLineLayers,
                    layerZOrders: zOrders,
                    observer: observer,
                    mapCenter: mapCenter,
                    calibration: calibration,
                    geometry: ProjectionGeometry(width: 1, height: 1),
                    generatedAt: generatedAt,
                )
            #if DEBUG
                case .testing:
                    target = try engine.frameForTesting(
                        experienceID: experienceID,
                        layerFrames: layerFrames,
                        projectedLineLayers: projectedLineLayers,
                        layerZOrders: zOrders,
                        observer: observer,
                        mapCenter: mapCenter,
                        viewport: viewport,
                        calibration: calibration,
                        geometry: ProjectionGeometry(width: 1, height: 1),
                        generatedAt: generatedAt,
                    )
            #endif
        }
        try Task.checkCancellation()
        let frame = animate(
            target: target,
            at: generatedAt,
            observationChanged: observationChanged,
            reduceMotion: reduceMotion,
            state: &experienceState,
        )
        if let event = experienceState.motionDiagnostics.record(
            layerFrame: flightsLayerFrame,
            target: target,
            at: generatedAt,
            observationChanged: observationChanged,
        ) {
            motionLogger.record(event)
        }
        try Task.checkCancellation()
        experienceState.previousFrame = frame
        experienceState.lastMarkRevisions = markRevisions
        let effects = experienceState.presentationState.effects(
            layerFrame: flightsLayerFrame,
            projectedFrame: frame,
            at: generatedAt,
            observationChanged: observationChanged,
            reduceMotion: reduceMotion,
        )
        experienceStates[experienceID] = experienceState
        let observerPoint: ProjectionPoint? = if case let .map(mapViewport) = viewport {
            try engine.mapPoint(
                for: observer.coordinate,
                center: mapCenter,
                viewport: mapViewport,
                calibration: calibration,
                geometry: ProjectionGeometry(width: 1, height: 1),
            )
        } else {
            nil
        }
        return ProjectionFrameWorkerOutput(
            frame: frame,
            geographyHealth: geographyResult.health,
            effects: effects,
            observerPoint: observerPoint,
        )
    }

    private func projectedGeography(
        isEnabled: Bool,
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
    ) async throws -> GeographyProjectionResult {
        guard isEnabled, case .map = viewport else { return .notRequested }
        guard geographyLoadFailed == false else { return .unavailable }
        let layerFrame = try await loadGeographyLayerFrame()
        try Task.checkCancellation()
        return try .projected(
            projectedLineCollection(
                for: layerFrame.erased,
                mapCenter: mapCenter,
                viewport: viewport,
                calibration: calibration,
            ),
        )
    }

    private func projectedLineCollection(
        for layerFrame: LayerFrame,
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
    ) throws -> ProjectedLineCollection {
        let key = StaticLineProjectionCacheKey(
            layerID: layerFrame.layerID,
            revision: layerFrame.observedAt,
            mapCenter: mapCenter,
            viewport: viewport,
            calibration: calibration,
        )
        if let projection = staticLineProjectionCache[key] {
            return projection
        }
        let segments = try engine.lineSegments(
            lines: layerFrame.lines,
            mapCenter: mapCenter,
            viewport: viewport,
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1, height: 1),
        )
        try Task.checkCancellation()
        lineProjectionSequence &+= 1
        let projection = ProjectedLineCollection(
            id: ProjectionLineRevisionID(rawValue: lineProjectionSequence),
            segments: segments,
        )
        staticLineProjectionCache[key] = projection
        return projection
    }

    private func loadGeographyLayerFrame() async throws
        -> ProjectionLayerFrame<GeographyLayerKind>
    {
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
            let result: Result<ProjectionLayerFrame<GeographyLayerKind>, any Error>
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
        _ result: Result<ProjectionLayerFrame<GeographyLayerKind>, any Error>,
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
        experienceStates = [:]
    }

    func reset(experienceID: ProjectionExperienceID) {
        experienceStates.removeValue(forKey: experienceID)
    }

    func experienceBecameInactive(_ id: ProjectionExperienceID, at date: Date) {
        guard var state = experienceStates[id] else { return }
        state.presentationState.semanticFeedBecameInactive(at: date)
        experienceStates[id] = state
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
        state: inout ExperienceState,
    ) -> ProjectionFrame {
        guard let previousFrame = state.previousFrame else {
            let resolvedTarget = state.labelResolver.resolve(target)
            state.lastPresentationSignature = ProjectionPresentationSignature(
                frame: resolvedTarget,
            )
            state.targetHistory.record(resolvedTarget)
            return resolvedTarget
        }
        if previousFrame.mode != target.mode,
           state.modeTransition?.targetMode != target.mode
        {
            state.modeTransition = ModeTransition(
                startedAt: date,
                source: previousFrame,
                targetMode: target.mode,
            )
            state.correctionTransition = nil
            state.targetHistory = ProjectionTargetHistory()
            state.labelResolver = ProjectionLabelCollisionResolver()
        }
        let resolvedTarget = state.labelResolver.resolve(target)
        defer { state.targetHistory.record(resolvedTarget) }
        let presentationSignature = ProjectionPresentationSignature(frame: resolvedTarget)
        let presentationChanged = state.lastPresentationSignature != presentationSignature
        state.lastPresentationSignature = presentationSignature

        if let transition = state.modeTransition {
            // Resolve the destination layout before it can become visible.
            // Source labels fade to zero, then resolved target labels replace
            // them at black and fade back in without a visible placement jump.
            let progress = min(
                1,
                max(0, date.timeIntervalSince(transition.startedAt) / AnimationDuration.mode),
            )
            if progress >= 1 {
                state.modeTransition = nil
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
                sourceVelocities: nil,
                elapsed: date.timeIntervalSince(transition.startedAt),
            )
        }

        if observationChanged || presentationChanged {
            state.correctionTransition = CorrectionTransition(
                startedAt: date,
                source: previousFrame,
                interpolatesPosition: observationChanged,
                sourceVelocities: observationChanged
                    ? state.targetHistory.velocities(at: date)
                    : [:],
            )
        }
        if let transition = state.correctionTransition {
            let progress = min(
                1,
                max(
                    0,
                    date.timeIntervalSince(transition.startedAt) / AnimationDuration.correction,
                ),
            )
            if progress >= 1 {
                state.correctionTransition = nil
                return resolvedTarget
            }
            return morph(
                source: transition.source,
                target: resolvedTarget,
                progress: progress,
                interpolatesPosition: transition.interpolatesPosition && reduceMotion == false,
                transitionsLabels: false,
                sourceVelocities: transition.sourceVelocities,
                elapsed: date.timeIntervalSince(transition.startedAt),
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
        sourceVelocities: [LayerMarkID: ProjectedPointVelocity]?,
        elapsed: TimeInterval,
    ) -> ProjectionFrame {
        let sourceByID = source.marks.reduce(into: [LayerMarkID: ProjectedMark]()) {
            $0[$1.id] = $1
        }
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
            let positionProgress: Double = if interpolatesPosition {
                sourceVelocities == nil ? cubicEaseOut(progress) : smoothStep(progress)
            } else {
                progress
            }
            let sourcePoint: ProjectionPoint = if interpolatesPosition,
                                                  let velocity = sourceVelocities?[mark.id]
            {
                ProjectionPoint(
                    x: old.point.x + velocity.xPerSecond * elapsed,
                    y: old.point.y + velocity.yPerSecond * elapsed,
                )
            } else {
                old.point
            }
            return ProjectedMark(
                id: mark.id,
                point: interpolatesPosition
                    ? ProjectionPoint(
                        x: sourcePoint.x + (mark.point.x - sourcePoint.x) * positionProgress,
                        y: sourcePoint.y + (mark.point.y - sourcePoint.y) * positionProgress,
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
        let lineLayers = transitionedLineLayers(
            source: source,
            target: target,
            progress: progress,
            transitionsMode: transitionsLabels,
        )
        return target.replacingMarks(marks).replacingLineLayers(lineLayers)
    }

    private func cubicEaseOut(_ progress: Double) -> Double {
        1 - pow(1 - progress, 3)
    }

    private func smoothStep(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
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
        let faded = frame.replacingMarks(
            frame.marks.map { mark in
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
        .replacingLineLayers(frame.layers.compactMap { layer in
            guard case let .lines(lines) = layer.content else { return nil }
            return ProjectedLayer(
                id: layer.id,
                zOrder: layer.zOrder,
                opacity: layer.opacity * opacity,
                content: .lines(lines),
            )
        })
        return ProjectionFrame(
            experienceID: target.experienceID,
            mode: target.mode,
            generatedAt: target.generatedAt,
            layers: faded.layers,
        )
    }

    private func transitionedLineLayers(
        source: ProjectionFrame,
        target: ProjectionFrame,
        progress: Double,
        transitionsMode: Bool,
    ) -> [ProjectedLayer] {
        guard transitionsMode else {
            return target.layers.filter { layer in
                if case .lines = layer.content { true } else { false }
            }
        }
        let usesSource = progress < 0.5
        let frame = usesSource ? source : target
        let opacity = usesSource ? 1 - progress * 2 : (progress - 0.5) * 2
        return frame.layers.compactMap { layer in
            guard case let .lines(lines) = layer.content else { return nil }
            return ProjectedLayer(
                id: layer.id,
                zOrder: layer.zOrder,
                opacity: layer.opacity * opacity,
                content: .lines(lines),
            )
        }
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
    let sourceVelocities: [LayerMarkID: ProjectedPointVelocity]
}

private struct ProjectedPointVelocity {
    let xPerSecond: Double
    let yPerSecond: Double
}

private struct ProjectionTargetHistory {
    private var previous: ProjectionFrame?
    private var latest: ProjectionFrame?

    mutating func record(_ frame: ProjectionFrame) {
        previous = latest
        latest = frame
    }

    func velocities(at date: Date) -> [LayerMarkID: ProjectedPointVelocity] {
        guard let previous, let latest, previous.mode == latest.mode else { return [:] }
        let interval = latest.generatedAt.timeIntervalSince(previous.generatedAt)
        guard interval > 0, interval <= 0.25,
              date.timeIntervalSince(latest.generatedAt) <= 0.25
        else { return [:] }
        let previousByID = previous.marks.reduce(into: [LayerMarkID: ProjectionPoint]()) {
            $0[$1.id] = $1.point
        }
        return latest.marks.reduce(into: [:]) { velocities, mark in
            guard let old = previousByID[mark.id] else { return }
            velocities[mark.id] = ProjectedPointVelocity(
                xPerSecond: (mark.point.x - old.x) / interval,
                yPerSecond: (mark.point.y - old.y) / interval,
            )
        }
    }
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

private struct StaticLineProjectionCacheKey: Hashable {
    let layerID: LayerID
    let revision: Date
    let mapCenter: GeoCoordinate
    let viewport: ProjectionViewport
    let calibration: ProjectionCalibration
}

#if DEBUG
    private struct GeographyWaiterCountObserver {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }
#endif

struct ProjectionFrameWorkerOutput {
    let frame: ProjectionFrame
    let geographyHealth: GeographyLayerHealth
    let effects: [LayerMarkID: ProjectionMarkEffect]
    let observerPoint: ProjectionPoint?
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

        mutating func semanticFeedBecameInactive(at date: Date) {
            for id in lastSemanticIDs {
                guard var entry = aircraft[id] else { continue }
                entry.absentSince = entry.absentSince ?? date
                aircraft[id] = entry
            }
        }

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
