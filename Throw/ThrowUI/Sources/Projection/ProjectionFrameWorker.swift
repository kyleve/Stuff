import Foundation
#if DEBUG
    @_spi(Testing) import ThrowCore
#else
    import ThrowCore
#endif

/// Off-main-actor projection, label layout, correction easing, and mode morphing.
actor ProjectionFrameWorker {
    private struct ResetGeneration: Equatable {
        static let initial = ResetGeneration(rawValue: 0)

        private let rawValue: UInt64

        func successor() -> Self {
            precondition(rawValue < UInt64.max, "A projection worker reset must not overflow")
            return Self(rawValue: rawValue + 1)
        }
    }

    /// Proves that neither the whole worker nor one experience reset while a request was suspended.
    private struct ResetTombstone: Equatable {
        let worker: ResetGeneration
        let experience: ResetGeneration
    }

    private struct RequestCursor {
        let revision: ProjectionFrameRequest.Revision
        let generatedAt: Date

        func permits(_ request: ProjectionFrameRequest) -> Bool {
            if request.revision.rawValue != revision.rawValue {
                return request.revision.rawValue > revision.rawValue
            }
            return request.generatedAt >= generatedAt
        }
    }

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
        var requestCursor: RequestCursor?
    }

    private let engine = ProjectionEngine()
    private let geographyRuntime: GeographyLayerRuntime
    private let geographyLogger: any GeographyLogging
    private let motionLogger: any ProjectionMotionLogging
    private let sessionFailureLogger: any ThrowSessionFailureLogging
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
    private var geographyProjectionCache = StaticLineProjectionCache<GeographyLayerKind>()
    private var transitNetworkProjectionCache =
        StaticLineProjectionCache<TransitNetworkLayerKind>()
    private var experienceStates: [ProjectionExperienceID: ExperienceState] = [:]
    private var workerResetGeneration = ResetGeneration.initial
    private var experienceResetGenerations: [ProjectionExperienceID: ResetGeneration] = [:]

    init(
        geographyRuntime: GeographyLayerRuntime,
        geographyLogger: any GeographyLogging,
        motionLogger: any ProjectionMotionLogging,
        sessionFailureLogger: any ThrowSessionFailureLogging,
    ) {
        self.geographyRuntime = geographyRuntime
        self.geographyLogger = geographyLogger
        self.motionLogger = motionLogger
        self.sessionFailureLogger = sessionFailureLogger
    }

    /// Compatibility initializer for focused worker tests that still build a Flights runtime.
    init(
        flightsRuntime _: FlightsLayerRuntime,
        geographyRuntime: GeographyLayerRuntime,
        geographyLogger: any GeographyLogging,
        motionLogger: any ProjectionMotionLogging,
        sessionFailureLogger: any ThrowSessionFailureLogging,
    ) {
        self.init(
            geographyRuntime: geographyRuntime,
            geographyLogger: geographyLogger,
            motionLogger: motionLogger,
            sessionFailureLogger: sessionFailureLogger,
        )
    }

    func frame(request: ProjectionFrameRequest) async throws -> ProjectionFrameWorkerOutput {
        try await render(request: request)
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
            let context = ProjectionFrameRequest.Context(
                observer: observer,
                mapCenter: mapCenter,
                calibration: calibration,
                reduceMotion: reduceMotion,
                loggingOperation: .projectionRendering,
            )
            return try await render(request: .testing(.init(
                experienceID: experienceID,
                layerFrames: layerFrames,
                geographyEnabled: geographyEnabled,
                viewport: viewport,
                context: context,
                generatedAt: generatedAt,
                revision: .initial,
            )))
        }
    #endif

    private func render(
        request: ProjectionFrameRequest,
    ) async throws -> ProjectionFrameWorkerOutput {
        try Task.checkCancellation()
        let experienceID = request.experienceID
        let resetTombstone = currentResetTombstone(for: experienceID)
        let geographyEnabled = request.requestsGeography
        let viewport = request.viewport
        let observer = request.context.observer
        let mapCenter = request.context.mapCenter
        let calibration = request.context.calibration
        let generatedAt = request.generatedAt
        let reduceMotion = request.context.reduceMotion
        let flightsLayerFrame = request.flightsFrame
        let markRevisions = request.markRevisions
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
            sessionFailureLogger.recordPostLaunchFailure(
                at: request.context.loggingOperation,
                error: error,
            )
            geographyLoadFailed = true
            geographyResult = .unavailable
        }
        try Task.checkCancellation()
        guard resetTombstone == currentResetTombstone(for: experienceID) else {
            throw CancellationError()
        }
        var experienceState = experienceStates[experienceID] ?? ExperienceState()
        guard experienceState.requestCursor?.permits(request) ?? true else {
            throw CancellationError()
        }
        let observationChanged = experienceState.lastMarkRevisions != markRevisions
        let target: ProjectionFrame
        switch request {
            case let .airAndSpace(request):
                let projectionInput = request.input
                let projected = try engine.frame(
                    input: .airAndSpace(PreparedAirAndSpaceProjectionInput(
                        input: projectionInput,
                        geography: geographyResult.projection,
                    )),
                    observer: observer,
                    mapCenter: mapCenter,
                    calibration: calibration,
                    geometry: ProjectionGeometry(width: 1, height: 1),
                    generatedAt: generatedAt,
                )
                target = present(projected)
            case let .transit(request):
                let projectionInput = request.input
                let preparedInput = try PreparedTransitProjectionInput(
                    input: projectionInput,
                    geography: geographyResult.projection,
                ) { layerFrame in
                    try projectedTransitNetworkLayer(
                        layerFrame,
                        mapCenter: mapCenter,
                        viewport: viewport,
                        calibration: calibration,
                    )
                }
                let projected = try engine.frame(
                    input: .transit(preparedInput),
                    observer: observer,
                    mapCenter: mapCenter,
                    calibration: calibration,
                    geometry: ProjectionGeometry(width: 1, height: 1),
                    generatedAt: generatedAt,
                )
                target = present(projected)
            #if DEBUG
                case let .testing(request):
                    let layerFrames = request.layerFrames
                    var projectedLayers = geographyResult.projection.map {
                        [testingGeographyLayer($0.lines)]
                    } ?? []
                    for lineFrame in layerFrames {
                        guard case .lines = lineFrame.content,
                              projectedLayers.contains(where: { $0.id == lineFrame.layerID }) ==
                              false
                        else { continue }
                        let projectedLayer = try projectedLineLayerForTesting(
                            layerFrame: lineFrame,
                            mapCenter: mapCenter,
                            viewport: viewport,
                            calibration: calibration,
                        )
                        projectedLayers.append(projectedLayer)
                    }
                    let marks = try engine.projectedMarksForTesting(
                        layerFrames: layerFrames,
                        observer: observer,
                        mapCenter: mapCenter,
                        viewport: viewport,
                        calibration: calibration,
                        geometry: ProjectionGeometry(width: 1, height: 1),
                        generatedAt: generatedAt,
                    )
                    projectedLayers.append(contentsOf: testingMarkLayers(marks))
                    target = .testing(
                        experienceID: experienceID,
                        mode: viewport.mode,
                        generatedAt: generatedAt,
                        layers: projectedLayers,
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
        experienceState.requestCursor = RequestCursor(
            revision: request.revision,
            generatedAt: generatedAt,
        )
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
        guard let output = ProjectionFrameWorkerOutput(
            request: request,
            render: .init(
                frame: frame,
                geographyHealth: geographyResult.health,
                effects: effects,
                observerPoint: observerPoint,
            ),
        ) else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        return output
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
            projectedGeographyLineLayer(
                layerFrame,
                mapCenter: mapCenter,
                viewport: viewport,
                calibration: calibration,
            ),
        )
    }

    private func projectedGeographyLineLayer(
        _ layerFrame: ProjectionLayerFrame<GeographyLayerKind>,
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
    ) throws -> ProjectedLayerFrame<GeographyLayerKind> {
        try projectLineLayer(
            source: layerFrame,
            mapCenter: mapCenter,
            viewport: viewport,
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1, height: 1),
            engine: engine,
            cache: &geographyProjectionCache,
        )
    }

    private func projectedTransitNetworkLayer(
        _ layerFrame: ProjectionLayerFrame<TransitNetworkLayerKind>,
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
    ) throws -> ProjectedLayerFrame<TransitNetworkLayerKind> {
        try projectLineLayer(
            source: layerFrame,
            mapCenter: mapCenter,
            viewport: viewport,
            calibration: calibration,
            geometry: ProjectionGeometry(width: 1, height: 1),
            engine: engine,
            cache: &transitNetworkProjectionCache,
        )
    }

    #if DEBUG
        private func projectedLineLayerForTesting(
            layerFrame: LayerFrame,
            mapCenter: GeoCoordinate,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
        ) throws -> ProjectedLayer {
            switch layerFrame.layerID {
                case .geography:
                    let lines = try layerFrame.lines.map { line in
                        guard let kind = line.style.geographyKind else {
                            preconditionFailure("A Geography test layer must use Geography styles")
                        }
                        return try GeographicPolyline(
                            kind: kind,
                            detailLevel: line.detailLevel,
                            bounds: line.bounds,
                            coordinates: line.coordinates,
                        )
                    }
                    return try testingGeographyLayer(
                        projectedGeographyLineLayer(
                            ProjectionLayerFrame<GeographyLayerKind>(
                                observedAt: layerFrame.observedAt,
                                lines: lines,
                            ),
                            mapCenter: mapCenter,
                            viewport: viewport,
                            calibration: calibration,
                        ).lines,
                    )
                case .transitNetwork:
                    let lines = try layerFrame.lines.map { line in
                        guard let style = line.style.transitRouteStyle else {
                            preconditionFailure("A Transit test layer must use Transit styles")
                        }
                        return try ProjectionPolyline<TransitNetworkLineStyle>(
                            style: style,
                            detailLevel: line.detailLevel,
                            bounds: line.bounds,
                            coordinates: line.coordinates,
                        )
                    }
                    return try testingTransitNetworkLayer(
                        projectedTransitNetworkLayer(
                            ProjectionLayerFrame<TransitNetworkLayerKind>(
                                observedAt: layerFrame.observedAt,
                                lines: lines,
                            ),
                            mapCenter: mapCenter,
                            viewport: viewport,
                            calibration: calibration,
                        ).lines,
                    )
                case .flights, .stars, .satellites, .transitVehicles:
                    preconditionFailure("A mark layer cannot carry test line content")
            }
        }
    #endif

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
        workerResetGeneration = workerResetGeneration.successor()
        experienceStates = [:]
    }

    func reset(experienceID: ProjectionExperienceID) {
        let generation = experienceResetGenerations[experienceID] ?? .initial
        experienceResetGenerations[experienceID] = generation.successor()
        experienceStates.removeValue(forKey: experienceID)
    }

    private func currentResetTombstone(
        for experienceID: ProjectionExperienceID,
    ) -> ResetTombstone {
        ResetTombstone(
            worker: workerResetGeneration,
            experience: experienceResetGenerations[experienceID] ?? .initial,
        )
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
        precondition(
            previousFrame.hasSamePresentationExperience(as: target),
            "Projection state cannot combine production and test Views or different Views",
        )
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
        let sourceByID = source.marks.reduce(into: [LayerMarkID: PresentedMark]()) {
            $0[$1.id] = $1
        }
        let targetIDs = Set(target.marks.map(\.id))
        let usesSourceLabels = transitionsLabels && progress < 0.5
        let labelPhaseOpacity = transitionsLabels ? modeLabelOpacity(at: progress) : 1
        let presenceProgress = transitionsLabels
            ? 1
            : min(1, progress * AnimationDuration.correction / AnimationDuration.presence)
        var fieldsByID: [LayerMarkID: PresentedMarkFields] = [:]
        fieldsByID.reserveCapacity(target.marks.count + source.marks.count)
        for mark in target.marks {
            let fields: PresentedMarkFields
            guard let old = sourceByID[mark.id] else {
                let duration = if case .airport = mark.glyph {
                    AnimationDuration.anchor
                } else {
                    AnimationDuration.presence
                }
                let insertionProgress = transitionsLabels
                    ? 1
                    : min(1, progress * AnimationDuration.correction / duration)
                fields = PresentedMarkFields(
                    point: mark.point,
                    label: usesSourceLabels ? nil : mark.label,
                    secondaryProminence: mark.secondaryProminence,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * insertionProgress,
                    labelOpacity: usesSourceLabels
                        ? 0
                        : mark.labelOpacity * labelPhaseOpacity,
                )
                fieldsByID[mark.id] = fields
                continue
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
            fields = PresentedMarkFields(
                point: interpolatesPosition
                    ? ProjectionPoint(
                        x: sourcePoint.x + (mark.point.x - sourcePoint.x) * positionProgress,
                        y: sourcePoint.y + (mark.point.y - sourcePoint.y) * positionProgress,
                    )
                    : mark.point,
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
            )
            fieldsByID[mark.id] = fields
        }
        var appendedSourceIDs: Set<LayerMarkID> = []
        if transitionsLabels == false, progress < 1 {
            for mark in source.marks {
                guard targetIDs.contains(mark.id) == false else { continue }
                let duration = removalDuration(for: mark)
                let removalProgress = min(
                    1,
                    progress * AnimationDuration.correction / duration,
                )
                guard removalProgress < 1 else { continue }
                appendedSourceIDs.insert(mark.id)
                fieldsByID[mark.id] = PresentedMarkFields(
                    point: mark.point,
                    label: mark.label,
                    secondaryProminence: mark.secondaryProminence,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity * (1 - removalProgress),
                    labelOpacity: mark.labelOpacity,
                )
            }
        }
        guard transitionsLabels else {
            guard let frame = target.updatingMarkPresentation(
                fieldsByID: fieldsByID,
                retainedTargetIDs: targetIDs,
                appendedSourceIDs: appendedSourceIDs,
                sourceFrame: source,
                lineLayersFrom: target,
                lineOpacity: 1,
            ) else {
                preconditionFailure("Correction morphs must preserve the presentation case")
            }
            return frame
        }
        let usesSourceLines = progress < 0.5
        let framesHaveSameCase = target.hasSamePresentationCase(as: source)
        let lineFrame = usesSourceLines && framesHaveSameCase ? source : target
        let lineOpacity = if usesSourceLines {
            framesHaveSameCase ? 1 - progress * 2 : 0
        } else {
            (progress - 0.5) * 2
        }
        guard let frame = target.updatingMarkPresentation(
            fieldsByID: fieldsByID,
            retainedTargetIDs: targetIDs,
            appendedSourceIDs: appendedSourceIDs,
            sourceFrame: framesHaveSameCase ? source : target,
            lineLayersFrom: lineFrame,
            lineOpacity: lineOpacity,
        ) else {
            preconditionFailure("Mode morphs must use one closed presentation case")
        }
        return frame
    }

    private func cubicEaseOut(_ progress: Double) -> Double {
        1 - pow(1 - progress, 3)
    }

    private func smoothStep(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }

    private func removalDuration(for mark: PresentedMark) -> TimeInterval {
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
        return frame.faded(by: opacity, as: target)
    }

    private func modeLabelOpacity(at progress: Double) -> Double {
        if progress < 0.5 {
            1 - progress * 2
        } else {
            (progress - 0.5) * 2
        }
    }

    private func transitionLabel(
        from source: PresentedMark,
        to target: PresentedMark,
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

private func projectLineLayer<Layer: ProjectionLineLayerKind>(
    source: ProjectionLayerFrame<Layer>,
    mapCenter: GeoCoordinate,
    viewport: ProjectionViewport,
    calibration: ProjectionCalibration,
    geometry: ProjectionGeometry,
    engine: ProjectionEngine,
    cache: inout StaticLineProjectionCache<Layer>,
) throws -> ProjectedLayerFrame<Layer> {
    let key = StaticLineProjectionCache<Layer>.Key(
        revision: source.observedAt,
        mapCenter: mapCenter,
        viewport: viewport,
        calibration: calibration,
        geometry: geometry,
    )
    if let frame = cache.frame(for: key) {
        return frame
    }
    let frame = try engine.lineFrame(
        source: source,
        mapCenter: mapCenter,
        viewport: viewport,
        calibration: calibration,
        geometry: geometry,
    )
    cache.insert(frame, for: key)
    return frame
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

        init(mark: PresentedMark) {
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

#if DEBUG
    private struct GeographyWaiterCountObserver {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }
#endif

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
            layerFrame: ProjectionLayerFrame<FlightsLayerKind>?,
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
                return (presentationID(mark.id), descriptor.activity)
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
                    case .star, .satellite, .transitVehicle, .transitStop:
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
    case projected(ProjectedLayerFrame<GeographyLayerKind>)
    case unavailable

    var projection: ProjectedLayerFrame<GeographyLayerKind>? {
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
