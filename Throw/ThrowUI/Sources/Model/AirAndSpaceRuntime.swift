import Foundation
import ThrowCore

protocol FlightsLayerRunning: Sendable {
    func frame(
        for input: FlightsLayerInput,
    ) async throws -> ProjectionLayerFrame<FlightsLayerKind>

    func reset() async
}

extension FlightsLayerRuntime: FlightsLayerRunning {}

/// One immutable snapshot of the Air & Space runtime's actor-isolated state.
struct AirAndSpaceRuntimeUpdate {
    enum SemanticPreparationState: Equatable {
        case ready
        case failed
    }

    let activationLease: ProjectionActivationLease?
    let successfulActivationLease: ProjectionActivationLease?
    let health: FeedHealth
    let flightsFrame: ProjectionLayerFrame<FlightsLayerKind>?
    let snapshot: AircraftSnapshot?
    let activePollingSignature: PollingSignature?
    let semanticPreparationState: SemanticPreparationState

    var experienceFrame: ProjectionExperienceFrame {
        .airAndSpace(AirAndSpaceExperienceFrame(
            geography: nil,
            flights: flightsFrame,
            stars: nil,
            satellites: nil,
        ))
    }
}

enum AirAndSpaceRuntimeActivationResult {
    case accepted(AirAndSpaceRuntimeUpdate)
    case superseded(current: AirAndSpaceRuntimeUpdate)
}

/// Owns aircraft polling, semantic frame construction, motion state, and route enrichment.
actor AirAndSpaceRuntime {
    private enum AcceptedPollingPublication {
        case inactive
        case active(AircraftPollingState)
    }

    /// Keeps an accepted Core token and its ordered publication cursor as one
    /// value. A revision from another activation cannot enter this state.
    private enum PollingPublicationAcceptance {
        struct ActiveCursor {
            let token: AircraftPollingActivationToken
            let latestRevision: AircraftPollingActiveUpdate.Revision?
        }

        case inactive(hasAppliedInactive: Bool)
        case awaitingActivation
        case active(ActiveCursor)

        var expectedToken: AircraftPollingActivationToken? {
            guard case let .active(cursor) = self else { return nil }
            return cursor.token
        }

        mutating func activate(_ token: AircraftPollingActivationToken) {
            self = .active(ActiveCursor(token: token, latestRevision: nil))
        }

        mutating func accept(
            _ update: AircraftPollingUpdate,
        ) -> AcceptedPollingPublication? {
            switch (self, update) {
                case let (.inactive(hasAppliedInactive), .inactive):
                    guard hasAppliedInactive == false else { return nil }
                    self = .inactive(hasAppliedInactive: true)
                    return .inactive
                case let (.active(cursor), .active(activeUpdate)):
                    guard activeUpdate.token == cursor.token,
                          cursor.latestRevision.map({ activeUpdate.revision > $0 }) ?? true
                    else { return nil }
                    self = .active(ActiveCursor(
                        token: cursor.token,
                        latestRevision: activeUpdate.revision,
                    ))
                    return .active(activeUpdate.state)
                case (.inactive, .active), (.awaitingActivation, _), (.active, .inactive):
                    return nil
            }
        }
    }

    private enum ActivationLifecycle {
        case idle
        case active(ProjectionActivationLease)
        case inactive(latestGeneration: ProjectionActivationLease.Generation)

        var activeLease: ProjectionActivationLease? {
            guard case let .active(lease) = self else { return nil }
            return lease
        }

        mutating func activate(_ lease: ProjectionActivationLease) -> Bool {
            switch self {
                case .idle:
                    self = .active(lease)
                    return true
                case let .active(currentLease):
                    guard lease.generation >= currentLease.generation else { return false }
                    self = .active(lease)
                    return true
                case let .inactive(latestGeneration):
                    guard lease.generation > latestGeneration else { return false }
                    self = .active(lease)
                    return true
            }
        }

        /// Retires an active lease when the command is at least as new.
        mutating func deactivate(upThrough lease: ProjectionActivationLease) -> Bool {
            switch self {
                case .idle:
                    self = .inactive(latestGeneration: lease.generation)
                    return false
                case let .active(activeLease):
                    guard lease.generation >= activeLease.generation else { return false }
                    self = .inactive(latestGeneration: lease.generation)
                    return true
                case let .inactive(latestGeneration):
                    guard lease.generation >= latestGeneration else { return false }
                    self = .inactive(latestGeneration: lease.generation)
                    return false
            }
        }
    }

    private let pollingCoordinator: AircraftPollingCoordinator
    private let flightsRuntime: any FlightsLayerRunning
    private let routeResolver: FlightRouteResolver
    private let routeLogger: any FlightRouteLogging
    private let dateProvider: any DateProvider
    private let sessionFailureLogger: any ThrowSessionFailureLogging
    private let updatesStream: AsyncStream<AirAndSpaceRuntimeUpdate>
    private let continuation: AsyncStream<AirAndSpaceRuntimeUpdate>.Continuation

    private var observationTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var activePollingSignature: PollingSignature?
    private var pollingPublicationAcceptance =
        PollingPublicationAcceptance.inactive(hasAppliedInactive: false)
    #if DEBUG
        private var lastObservedPollingUpdate: AircraftPollingUpdate?
    #endif
    private var activationLifecycle = ActivationLifecycle.idle
    private var successfulActivationLease: ProjectionActivationLease?
    private var lifecycleGeneration: UInt64 = 0
    private var stateGeneration: UInt64 = 0
    private var routeGeneration: UInt64 = 0
    private var labelMode: FlightLabelMode = .adaptive
    private var currentSnapshot: AircraftSnapshot?
    private var currentLayerFrame: ProjectionLayerFrame<FlightsLayerKind>?
    private var currentAvailability: MarkAvailability = .current
    private var health: FeedHealth = .idle
    private var inactiveHealth: FeedHealth = .idle
    private var semanticPreparationState: AirAndSpaceRuntimeUpdate.SemanticPreparationState = .ready

    init(
        pollingCoordinator: AircraftPollingCoordinator,
        flightsRuntime: any FlightsLayerRunning,
        routeResolver: FlightRouteResolver,
        routeLogger: any FlightRouteLogging,
        dateProvider: any DateProvider,
        sessionFailureLogger: any ThrowSessionFailureLogging,
    ) {
        self.pollingCoordinator = pollingCoordinator
        self.flightsRuntime = flightsRuntime
        self.routeResolver = routeResolver
        self.routeLogger = routeLogger
        self.dateProvider = dateProvider
        self.sessionFailureLogger = sessionFailureLogger
        let pair = AsyncStream.makeStream(
            of: AirAndSpaceRuntimeUpdate.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        updatesStream = pair.stream
        continuation = pair.continuation
    }

    deinit {
        observationTask?.cancel()
        routeTask?.cancel()
        continuation.finish()
    }

    func stateUpdates() -> AsyncStream<AirAndSpaceRuntimeUpdate> {
        startObservingIfNeeded()
        publish()
        return updatesStream
    }

    func currentUpdate() -> AirAndSpaceRuntimeUpdate {
        updateValue()
    }

    func activate(
        configuration: AircraftSourceConfiguration,
        query: AircraftQuery,
        labelMode: FlightLabelMode,
        lease: ProjectionActivationLease,
    ) async -> AirAndSpaceRuntimeActivationResult {
        guard lease.experienceID == .airAndSpace else {
            assertionFailure("Air & Space received another experience's activation lease")
            return .superseded(current: updateValue())
        }
        let previousLease = activationLifecycle.activeLease
        guard activationLifecycle.activate(lease) else {
            return .superseded(current: updateValue())
        }
        startObservingIfNeeded()
        let signature = PollingSignature(configuration: configuration, query: query)
        let activationChanged = previousLease != lease
        let sourceChanged = activePollingSignature?.configuration != configuration
        let queryChanged = activePollingSignature?.query != query
        let pollingActivationMissing = pollingPublicationAcceptance.expectedToken == nil
        let labelsChanged = self.labelMode != labelMode
        self.labelMode = labelMode

        if activationChanged || sourceChanged || queryChanged || pollingActivationMissing {
            lifecycleGeneration &+= 1
            let lifecycleGeneration = lifecycleGeneration
            stateGeneration &+= 1
            successfulActivationLease = nil
            activePollingSignature = nil
            pollingPublicationAcceptance = .awaitingActivation
            cancelRouteEnrichment()
            currentSnapshot = nil
            currentLayerFrame = nil
            currentAvailability = .current
            health = .loading
            if activationChanged || sourceChanged {
                await flightsRuntime.reset()
                guard lifecycleGeneration == self.lifecycleGeneration else {
                    return .superseded(current: updateValue())
                }
            }
            publish()
            let pollingActivation = await pollingCoordinator.activate(
                configuration: configuration,
                query: query,
                quiet: false,
            )
            guard lifecycleGeneration == self.lifecycleGeneration,
                  activationLifecycle.activeLease == lease,
                  let pollingActivation
            else { return .superseded(current: updateValue()) }
            activePollingSignature = signature
            pollingPublicationAcceptance.activate(pollingActivation)
            publish()
            let currentPollingUpdate = await pollingCoordinator.currentUpdate()
            await apply(currentPollingUpdate)
            guard lifecycleGeneration == self.lifecycleGeneration,
                  activationLifecycle.activeLease == lease,
                  activePollingSignature == signature,
                  pollingPublicationAcceptance.expectedToken == pollingActivation
            else { return .superseded(current: updateValue()) }
            return .accepted(updateValue())
        }

        if labelsChanged {
            await rebuildCurrentLayerFrame()
        }
        guard activationLifecycle.activeLease == lease,
              activePollingSignature == signature,
              pollingPublicationAcceptance.expectedToken != nil
        else { return .superseded(current: updateValue()) }
        return .accepted(updateValue())
    }

    func deactivate(
        lease: ProjectionActivationLease,
        reporting health: FeedHealth,
    ) async {
        guard lease.experienceID == .airAndSpace else {
            assertionFailure("Air & Space received another experience's deactivation lease")
            return
        }
        guard activationLifecycle.deactivate(upThrough: lease) else { return }
        lifecycleGeneration &+= 1
        let lifecycleGeneration = lifecycleGeneration
        stateGeneration &+= 1
        successfulActivationLease = nil
        activePollingSignature = nil
        pollingPublicationAcceptance = .inactive(hasAppliedInactive: false)
        inactiveHealth = health
        cancelRouteEnrichment()
        currentSnapshot = nil
        currentLayerFrame = nil
        currentAvailability = .current
        await pollingCoordinator.deactivate()
        guard lifecycleGeneration == self.lifecycleGeneration else { return }
        await flightsRuntime.reset()
        guard lifecycleGeneration == self.lifecycleGeneration else { return }
        self.health = health
        publish()
    }

    func refreshPresentation(labelMode: FlightLabelMode) async {
        guard self.labelMode != labelMode else { return }
        self.labelMode = labelMode
        await rebuildCurrentLayerFrame()
    }

    func updateVisibleContentCount(_ count: Int, lease: ProjectionActivationLease) {
        guard activationLifecycle.activeLease == lease else { return }
        switch health {
            case let .healthy(lastUpdate, oldCount) where oldCount != count:
                health = .healthy(lastUpdate: lastUpdate, visibleContentCount: count)
                publish()
            case let .retrying(lastUpdate, nextRetry, failure, oldCount) where oldCount != count:
                health = .retrying(
                    lastUpdate: lastUpdate,
                    nextRetry: nextRetry,
                    failure: failure,
                    visibleContentCount: count,
                )
                publish()
            case .idle, .loading, .healthy, .retrying, .failed, .quiet:
                break
        }
    }

    #if DEBUG
        func activeSourceKindForTesting() -> AircraftSourceKind? {
            activePollingSignature?.configuration.kind
        }

        func activePollingActivationForTesting() -> AircraftPollingActivationToken? {
            pollingPublicationAcceptance.expectedToken
        }

        func lastObservedPollingUpdateForTesting() -> AircraftPollingUpdate? {
            lastObservedPollingUpdate
        }
    #endif

    private func startObservingIfNeeded() {
        guard observationTask == nil else { return }
        observationTask = Task(name: "Throw observe Air & Space polling") {
            [pollingCoordinator, weak self] in
            let updates = await pollingCoordinator.stateUpdates()
            for await update in updates {
                guard Task.isCancelled == false else { return }
                await self?.apply(update)
            }
        }
    }

    private func apply(_ update: AircraftPollingUpdate) async {
        #if DEBUG
            lastObservedPollingUpdate = update
        #endif
        guard let acceptedPublication = pollingPublicationAcceptance.accept(update) else { return }
        let state: AircraftPollingState
        switch acceptedPublication {
            case .inactive:
                guard activePollingSignature == nil else { return }
                stateGeneration &+= 1
                health = inactiveHealth
                publish()
                return
            case let .active(activeState):
                state = activeState
        }

        stateGeneration &+= 1
        let generation = stateGeneration
        switch state {
            case .loading:
                health = .loading
                publish()
            case let .healthy(snapshot, _):
                do {
                    let layer = try await makeLayerFrame(snapshot, availability: .current)
                    guard generation == stateGeneration else { return }
                    currentSnapshot = snapshot
                    currentAvailability = .current
                    currentLayerFrame = layer
                    semanticPreparationState = .ready
                    successfulActivationLease = activationLifecycle.activeLease
                    health = .healthy(
                        lastUpdate: snapshot.fetchedAt,
                        visibleContentCount: health.visibleContentCount,
                    )
                    publish()
                    scheduleRouteEnrichment(for: snapshot)
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == stateGeneration else { return }
                    sessionFailureLogger.recordPostLaunchFailure(
                        at: .projectionPreparation,
                        error: error,
                    )
                    semanticPreparationState = .failed
                    health = .failed(.decoding)
                    publish()
                }
            case let .retrying(lastGoodSnapshot, failure, failureStartedAt, nextRetryAt):
                if let lastGoodSnapshot {
                    let availability = MarkAvailability.retrying(since: failureStartedAt)
                    do {
                        let layer = try await makeLayerFrame(
                            lastGoodSnapshot,
                            availability: availability,
                        )
                        guard generation == stateGeneration else { return }
                        currentSnapshot = lastGoodSnapshot
                        currentAvailability = availability
                        currentLayerFrame = layer
                        semanticPreparationState = .ready
                        health = .retrying(
                            lastUpdate: lastGoodSnapshot.fetchedAt,
                            nextRetry: nextRetryAt,
                            failure: failure.presentationCategory,
                            visibleContentCount: health.visibleContentCount,
                        )
                        publish()
                        scheduleRouteEnrichment(for: lastGoodSnapshot)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard generation == stateGeneration else { return }
                        sessionFailureLogger.recordPostLaunchFailure(
                            at: .projectionPreparation,
                            error: error,
                        )
                        semanticPreparationState = .failed
                        health = .failed(.decoding)
                        publish()
                    }
                } else {
                    clearSemanticState()
                    health = .retrying(
                        lastUpdate: nil,
                        nextRetry: nextRetryAt,
                        failure: failure.presentationCategory,
                        visibleContentCount: 0,
                    )
                    publish()
                }
            case let .failed(failure):
                clearSemanticState()
                health = .failed(failure.presentationCategory)
                publish()
            case .quiet:
                clearSemanticState()
                health = .quiet
                publish()
        }
    }

    private func makeLayerFrame(
        _ snapshot: AircraftSnapshot,
        availability: MarkAvailability,
    ) async throws -> ProjectionLayerFrame<FlightsLayerKind> {
        guard let observer = activePollingSignature?.query.observer else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        let routeResults: [FlightCallsign: FlightRouteResult] = if snapshot.source ==
            .flightradar24
        {
            [:]
        } else {
            await routeResolver.cachedResults(
                for: snapshot.observations,
                at: dateProvider.now(),
            )
        }
        return try await flightsRuntime.frame(
            for: FlightsLayerInput(
                snapshot: snapshot,
                observer: observer,
                labelMode: labelMode,
                routeResults: routeResults,
                availability: availability,
            ),
        )
    }

    private func rebuildCurrentLayerFrame() async {
        guard let currentSnapshot else { return }
        stateGeneration &+= 1
        let generation = stateGeneration
        do {
            let layer = try await makeLayerFrame(
                currentSnapshot,
                availability: currentAvailability,
            )
            guard generation == stateGeneration else { return }
            currentLayerFrame = layer
            semanticPreparationState = .ready
            publish()
        } catch is CancellationError {
            return
        } catch {
            guard generation == stateGeneration else { return }
            sessionFailureLogger.recordPostLaunchFailure(
                at: .projectionPreparation,
                error: error,
            )
            semanticPreparationState = .failed
            health = .failed(.decoding)
            publish()
        }
    }

    private func scheduleRouteEnrichment(for snapshot: AircraftSnapshot) {
        guard snapshot.source != .flightradar24 else {
            cancelRouteEnrichment()
            return
        }
        guard routeTask == nil else { return }
        routeGeneration &+= 1
        let generation = routeGeneration
        routeTask = Task(name: "Throw resolve Air & Space routes") { [weak self] in
            guard let self else { return }
            await resolveRoutes(for: snapshot, generation: generation)
        }
    }

    private func resolveRoutes(for snapshot: AircraftSnapshot, generation: UInt64) async {
        do {
            let result = try await routeResolver.resolveMissing(
                for: snapshot.observations,
                at: dateProvider.now(),
            )
            try Task.checkCancellation()
            guard generation == routeGeneration else { return }
            routeTask = nil
            let continuesEnrichment: Bool
            switch result {
                case .noRequestNeeded, .coolingDown:
                    continuesEnrichment = false
                case let .completed(_, hasMoreRequests):
                    routeLogger.record(FlightRouteLogEvent(outcome: .succeeded))
                    await rebuildCurrentLayerFrame()
                    continuesEnrichment = hasMoreRequests
            }
            if let currentSnapshot,
               continuesEnrichment || currentSnapshot.fetchedAt != snapshot.fetchedAt
            {
                scheduleRouteEnrichment(for: currentSnapshot)
            }
        } catch is CancellationError {
            guard generation == routeGeneration else { return }
            routeTask = nil
        } catch let error as FlightRouteLookupError {
            guard generation == routeGeneration else { return }
            routeTask = nil
            routeLogger.record(FlightRouteLogEvent(outcome: routeOutcome(for: error)))
            if let currentSnapshot, currentSnapshot.fetchedAt != snapshot.fetchedAt {
                scheduleRouteEnrichment(for: currentSnapshot)
            }
        } catch {
            guard generation == routeGeneration else { return }
            routeTask = nil
            routeLogger.record(FlightRouteLogEvent(outcome: .decodingFailed))
        }
    }

    private func cancelRouteEnrichment() {
        routeGeneration &+= 1
        routeTask?.cancel()
        routeTask = nil
    }

    private func clearSemanticState() {
        cancelRouteEnrichment()
        currentSnapshot = nil
        currentLayerFrame = nil
        currentAvailability = .current
    }

    private func routeOutcome(
        for error: FlightRouteLookupError,
    ) -> FlightRouteLogEvent.Outcome {
        switch error {
            case .provider: .providerFailed
            case .transport: .transportFailed
            case .decoding: .decodingFailed
        }
    }

    private func publish() {
        continuation.yield(updateValue())
    }

    private func updateValue() -> AirAndSpaceRuntimeUpdate {
        AirAndSpaceRuntimeUpdate(
            activationLease: activationLifecycle.activeLease,
            successfulActivationLease: successfulActivationLease,
            health: health,
            flightsFrame: currentLayerFrame,
            snapshot: currentSnapshot,
            activePollingSignature: activePollingSignature,
            semanticPreparationState: semanticPreparationState,
        )
    }
}
