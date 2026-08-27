import Foundation
import ThrowCore

public protocol ProjectionRotationClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemProjectionRotationClock: ProjectionRotationClock {
    public init() {}

    public func now() async -> Date {
        Date()
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct ProjectionExperienceDemand: Equatable {
    let hasOutput: Bool
    let isForeground: Bool
    let isQuiet: Bool
    let isCalibrating: Bool

    var permitsProjection: Bool {
        hasOutput && isForeground && isQuiet == false && isCalibrating == false
    }
}

enum ProjectionExperienceActivationRole: Equatable {
    case active
    case prewarming
    case manual
}

enum ProjectionExperienceCoordinatorAction: Equatable {
    case activate(
        id: ProjectionExperienceID,
        generation: UInt64,
        role: ProjectionExperienceActivationRole,
    )
    case deactivate(id: ProjectionExperienceID)
    case beginTransition(
        from: ProjectionExperienceID,
        to: ProjectionExperienceID,
        generation: UInt64,
    )
}

struct ProjectionExperienceCoordinatorState: Equatable {
    let activeExperienceID: ProjectionExperienceID?
    let requestedExperienceID: ProjectionExperienceID?
    let prewarmingExperienceID: ProjectionExperienceID?
    let isPaused: Bool
    let dwellEndsAt: Date?
    let nextExperienceID: ProjectionExperienceID?
    let healthByExperience: [ProjectionExperienceID: FeedHealth]
    let manualSelectionFailure: ThrowFailureCategory?
}

/// One playlist value and its logical session order, independent of task scheduling order.
struct ProjectionPlaylistConfiguration {
    struct Revision: Comparable {
        static let initial = Revision(rawValue: 0)

        let rawValue: UInt64

        func successor() -> Revision {
            precondition(rawValue < UInt64.max, "A playlist revision must not overflow")
            return Revision(rawValue: rawValue + 1)
        }

        static func < (lhs: Revision, rhs: Revision) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let playlist: ProjectionPlaylist
    let revision: Revision
}

/// Owns the single projection playlist timer and transactional View switching state.
actor ProjectionExperienceCoordinator {
    /// Keeps the active identity valid for the current playlist.
    private struct PlaylistRuntimeState {
        private(set) var playlist: ProjectionPlaylist
        private(set) var activeExperienceID: ProjectionExperienceID?

        init(playlist: ProjectionPlaylist) {
            self.playlist = playlist
            activeExperienceID = playlist.selectedExperienceID
        }

        mutating func configure(_ playlist: ProjectionPlaylist) {
            let previousActiveExperienceID = activeExperienceID
            self.playlist = playlist
            if let previousActiveExperienceID,
               playlist.entry(for: previousActiveExperienceID) != nil
            {
                activeExperienceID = previousActiveExperienceID
            } else {
                activeExperienceID = playlist.selectedExperienceID
            }
        }

        mutating func select(_ id: ProjectionExperienceID) -> Bool {
            guard playlist.entry(for: id) != nil else { return false }
            activeExperienceID = id
            return true
        }
    }

    private struct RuntimeState {
        var generation: UInt64 = 0
        var successfulGeneration: UInt64?
        var health: FeedHealth = .idle
        var isRunning = false
    }

    private struct ExperienceRequest {
        enum Timing {
            case manual(deadline: Date)
            case automatic(intendedTransitionAt: Date, deadline: Date)
        }

        let id: ProjectionExperienceID
        let generation: UInt64
        let timing: Timing

        var isManual: Bool {
            switch timing {
                case .manual:
                    true
                case .automatic:
                    false
            }
        }

        var deadline: Date {
            switch timing {
                case let .manual(deadline), let .automatic(_, deadline):
                    deadline
            }
        }

        func canTransition(at date: Date) -> Bool {
            switch timing {
                case .manual:
                    true
                case let .automatic(intendedTransitionAt, _):
                    date >= intendedTransitionAt
            }
        }
    }

    private enum RequestState {
        case awaiting(ExperienceRequest)
        case transitioning(ExperienceRequest)
        case committed(ExperienceRequest)

        var request: ExperienceRequest {
            switch self {
                case let .awaiting(request), let .transitioning(request), let .committed(request):
                    request
            }
        }

        var requestedExperienceID: ProjectionExperienceID? {
            switch self {
                case let .awaiting(request), let .transitioning(request):
                    request.id
                case .committed:
                    nil
            }
        }

        var prewarmingExperienceID: ProjectionExperienceID? {
            guard case let .awaiting(request) = self,
                  request.isManual == false
            else { return nil }
            return request.id
        }
    }

    private static let prewarmLeadSeconds = 15
    private static let readinessGraceSeconds = 30

    private let clock: any ProjectionRotationClock
    private let stateStream: AsyncStream<ProjectionExperienceCoordinatorState>
    private let stateContinuation: AsyncStream<ProjectionExperienceCoordinatorState>.Continuation
    private let actionStream: AsyncStream<ProjectionExperienceCoordinatorAction>
    private let actionContinuation: AsyncStream<ProjectionExperienceCoordinatorAction>.Continuation

    private var playlistState: PlaylistRuntimeState
    private var playlistConfigurationRevision = ProjectionPlaylistConfiguration.Revision.initial
    private var demand = ProjectionExperienceDemand(
        hasOutput: false,
        isForeground: true,
        isQuiet: false,
        isCalibrating: false,
    )
    private var requestState: RequestState?
    private var isPaused = false
    private var dwellEndsAt: Date?
    private var manualSelectionFailure: ThrowFailureCategory?
    private var runtimeStates: [ProjectionExperienceID: RuntimeState] = [:]
    private var nextGeneration: UInt64 = 0
    private var timerGeneration: UInt64 = 0
    private var rotationTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?

    init(
        playlist: ProjectionPlaylist,
        clock: any ProjectionRotationClock,
    ) {
        playlistState = PlaylistRuntimeState(playlist: playlist)
        self.clock = clock
        let states = AsyncStream.makeStream(
            of: ProjectionExperienceCoordinatorState.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        stateStream = states.stream
        stateContinuation = states.continuation
        let actions = AsyncStream.makeStream(
            of: ProjectionExperienceCoordinatorAction.self,
            bufferingPolicy: .bufferingOldest(32),
        )
        actionStream = actions.stream
        actionContinuation = actions.continuation
    }

    deinit {
        rotationTask?.cancel()
        readinessTask?.cancel()
        stateContinuation.finish()
        actionContinuation.finish()
    }

    func stateUpdates() -> AsyncStream<ProjectionExperienceCoordinatorState> {
        publishState()
        return stateStream
    }

    func actions() -> AsyncStream<ProjectionExperienceCoordinatorAction> {
        actionStream
    }

    func activationGeneration(for id: ProjectionExperienceID) -> UInt64? {
        runtimeStates[id]?.generation
    }

    func currentState() -> ProjectionExperienceCoordinatorState {
        stateValue()
    }

    #if DEBUG
        func runningExperienceIDsForTesting() -> Set<ProjectionExperienceID> {
            Set(runtimeStates.compactMap { id, state in state.isRunning ? id : nil })
        }
    #endif

    func configure(_ configuration: ProjectionPlaylistConfiguration) async {
        guard configuration.revision > playlistConfigurationRevision else { return }
        playlistConfigurationRevision = configuration.revision
        let playlist = configuration.playlist
        playlistState.configure(playlist)
        manualSelectionFailure = nil
        cancelRotation()
        cancelRequestedRuntime()
        let configuredIDs = Set(playlist.entries.map(\.experienceID))
        let removedIDs = runtimeStates.keys.filter { configuredIDs.contains($0) == false }
        for id in removedIDs {
            deactivateRuntime(id)
            runtimeStates.removeValue(forKey: id)
        }
        publishState()
        if demand.permitsProjection {
            await activateCurrentIfNeeded()
        }
    }

    func currentPlaylist() -> ProjectionPlaylist {
        playlist
    }

    func reconcile(demand: ProjectionExperienceDemand) async {
        let lostOutput = self.demand.hasOutput && demand.hasOutput == false
        self.demand = demand
        guard demand.permitsProjection else {
            cancelRotation()
            cancelRequestedRuntime()
            let runningIDs = runtimeStates.keys.filter { runtimeStates[$0]?.isRunning == true }
            for id in runningIDs {
                deactivateRuntime(id)
            }
            if lostOutput {
                isPaused = false
            }
            dwellEndsAt = nil
            publishState()
            return
        }
        await activateCurrentIfNeeded()
    }

    func reportRuntimeUpdate(
        id: ProjectionExperienceID,
        generation: UInt64,
        successfulGeneration: UInt64?,
        health: FeedHealth,
    ) async {
        guard var runtime = runtimeStates[id], runtime.generation == generation else { return }
        runtime.health = health
        if successfulGeneration == generation {
            runtime.successfulGeneration = generation
        }
        runtimeStates[id] = runtime
        publishState()

        if id == activeExperienceID,
           runtime.successfulGeneration == generation,
           requestState == nil,
           dwellEndsAt == nil
        {
            await startFreshDwell()
        }

        guard case let .awaiting(request) = requestState,
              id == request.id,
              generation == request.generation
        else { return }
        if case let .failed(failure) = health {
            await rejectRequestedExperience(failure: failure)
            return
        }
        guard runtime.successfulGeneration == generation else { return }
        let now = await clock.now()
        if request.canTransition(at: now) {
            beginTransitionIfReady()
        }
    }

    func select(_ id: ProjectionExperienceID) async {
        let now = await clock.now()
        guard playlist.entry(for: id) != nil else {
            manualSelectionFailure = .sourceNotValidated
            publishState()
            return
        }
        if id == activeExperienceID {
            manualSelectionFailure = nil
            cancelRequestedRuntime()
            await startFreshDwell()
            return
        }
        guard demand.permitsProjection else {
            guard playlistState.select(id) else {
                assertionFailure("The selected experience must be in the playlist")
                return
            }
            manualSelectionFailure = nil
            publishState()
            return
        }
        requestExperience(id, role: .manual, intendedTransitionAt: nil, now: now)
    }

    func selectNext() async {
        guard let activeExperienceID,
              let id = playlist.experience(after: activeExperienceID)
        else { return }
        await select(id)
    }

    func selectPrevious() async {
        guard let activeExperienceID,
              let id = playlist.experience(before: activeExperienceID)
        else { return }
        await select(id)
    }

    func pause() {
        guard playlist.rotatesAutomatically, isPaused == false else { return }
        isPaused = true
        cancelRotation()
        if requestState?.prewarmingExperienceID != nil {
            cancelRequestedRuntime()
        }
        publishState()
    }

    func resume() async {
        guard isPaused else { return }
        isPaused = false
        publishState()
        await startFreshDwell()
    }

    /// Commits the active identity while the caller holds the surface at black.
    func commitTransition(
        to id: ProjectionExperienceID,
        generation: UInt64,
    ) -> Bool {
        guard case let .transitioning(request) = requestState,
              request.id == id,
              request.generation == generation,
              runtimeStates[id]?.successfulGeneration == generation
        else { return false }
        let oldID = activeExperienceID
        guard playlistState.select(id) else {
            assertionFailure("The transition target must be in the playlist")
            return false
        }
        requestState = .committed(request)
        manualSelectionFailure = nil
        if let oldID, oldID != id {
            deactivateRuntime(oldID)
        }
        publishState()
        return true
    }

    /// The caller invokes this only after the committed surface completes its fade-in.
    func completeTransition(
        to id: ProjectionExperienceID,
        generation: UInt64,
    ) async {
        guard activeExperienceID == id,
              case let .committed(request) = requestState,
              request.id == id,
              request.generation == generation
        else { return }
        clearRequest()
        publishState()
        await startFreshDwell()
    }

    private func activateCurrentIfNeeded() async {
        guard let activeExperienceID else { return }
        if runtimeStates[activeExperienceID]?.isRunning != true {
            _ = activateRuntime(activeExperienceID, role: .active)
        } else if runtimeStates[activeExperienceID]?.successfulGeneration != nil,
                  dwellEndsAt == nil
        {
            await startFreshDwell()
        }
    }

    private func startFreshDwell() async {
        cancelRotation()
        guard demand.permitsProjection,
              isPaused == false,
              playlist.rotatesAutomatically,
              let activeExperienceID,
              runtimeStates[activeExperienceID]?.successfulGeneration != nil,
              let entry = playlist.entry(for: activeExperienceID)
        else {
            dwellEndsAt = nil
            publishState()
            return
        }
        timerGeneration &+= 1
        let generation = timerGeneration
        let now = await clock.now()
        let dwellSeconds = entry.dwellDuration.seconds
        dwellEndsAt = now.addingTimeInterval(TimeInterval(dwellSeconds))
        publishState()
        rotationTask = Task(name: "Throw projection experience rotation") {
            [clock, weak self] in
            do {
                try await clock.sleep(
                    for: .seconds(dwellSeconds - Self.prewarmLeadSeconds),
                )
                await self?.beginAutomaticPrewarm(timerGeneration: generation)
                try await clock.sleep(for: .seconds(Self.prewarmLeadSeconds))
                await self?.reachAutomaticTransitionTime(timerGeneration: generation)
            } catch is CancellationError {
                return
            } catch {
                await self?.handleRotationClockFailure(timerGeneration: generation)
            }
        }
    }

    private func beginAutomaticPrewarm(timerGeneration: UInt64) async {
        let now = await clock.now()
        guard timerGeneration == self.timerGeneration,
              demand.permitsProjection,
              isPaused == false,
              let activeExperienceID,
              let nextID = playlist.experience(after: activeExperienceID),
              let dwellEndsAt
        else { return }
        requestExperience(
            nextID,
            role: .prewarming,
            intendedTransitionAt: dwellEndsAt,
            now: now,
        )
    }

    private func reachAutomaticTransitionTime(timerGeneration: UInt64) {
        guard timerGeneration == self.timerGeneration else { return }
        dwellEndsAt = nil
        publishState()
        beginTransitionIfReady()
    }

    private func requestExperience(
        _ id: ProjectionExperienceID,
        role: ProjectionExperienceActivationRole,
        intendedTransitionAt: Date?,
        now: Date,
    ) {
        if role != .prewarming {
            cancelRotation()
        }
        cancelRequestedRuntime()
        manualSelectionFailure = nil
        let generation = activateRuntime(id, role: role)
        let timing: ExperienceRequest.Timing = if let intendedTransitionAt {
            .automatic(
                intendedTransitionAt: intendedTransitionAt,
                deadline: intendedTransitionAt.addingTimeInterval(
                    TimeInterval(Self.readinessGraceSeconds),
                ),
            )
        } else {
            .manual(
                deadline: now.addingTimeInterval(TimeInterval(Self.readinessGraceSeconds)),
            )
        }
        let request = ExperienceRequest(id: id, generation: generation, timing: timing)
        requestState = .awaiting(request)
        scheduleReadinessDeadline(for: request, now: now)
        publishState()
    }

    private func beginTransitionIfReady() {
        guard case let .awaiting(request) = requestState,
              let from = activeExperienceID,
              let runtime = runtimeStates[request.id],
              runtime.generation == request.generation,
              runtime.successfulGeneration == runtime.generation
        else { return }
        readinessTask?.cancel()
        readinessTask = nil
        requestState = .transitioning(request)
        actionContinuation.yield(
            .beginTransition(from: from, to: request.id, generation: runtime.generation),
        )
        publishState()
    }

    private func rejectRequestedExperience(failure: ThrowFailureCategory) async {
        let now = await clock.now()
        guard let request = requestState?.request else { return }
        let wasManual = request.isManual
        let failedID = request.id
        cancelRequestedRuntime()
        if wasManual {
            manualSelectionFailure = failure
        }
        publishState()

        guard wasManual == false,
              let activeExperienceID,
              let nextCandidate = playlist.experience(after: failedID),
              nextCandidate != activeExperienceID
        else {
            await startFreshDwell()
            return
        }
        requestExperience(
            nextCandidate,
            role: .prewarming,
            intendedTransitionAt: now,
            now: now,
        )
    }

    private func handleRotationClockFailure(timerGeneration: UInt64) async {
        guard timerGeneration == self.timerGeneration else { return }
        assertionFailure("Projection rotation clock failed")
        if requestState != nil {
            await rejectRequestedExperience(failure: .transport)
        } else {
            cancelRotation()
            publishState()
        }
    }

    private func activateRuntime(
        _ id: ProjectionExperienceID,
        role: ProjectionExperienceActivationRole,
    ) -> UInt64 {
        nextGeneration &+= 1
        var state = runtimeStates[id] ?? RuntimeState()
        state.generation = nextGeneration
        state.successfulGeneration = nil
        state.health = .loading
        state.isRunning = true
        runtimeStates[id] = state
        actionContinuation.yield(
            .activate(id: id, generation: nextGeneration, role: role),
        )
        return nextGeneration
    }

    private func deactivateRuntime(_ id: ProjectionExperienceID) {
        guard runtimeStates[id]?.isRunning == true else { return }
        runtimeStates[id]?.isRunning = false
        runtimeStates[id]?.successfulGeneration = nil
        runtimeStates[id]?.health = .idle
        actionContinuation.yield(.deactivate(id: id))
    }

    private func cancelRequestedRuntime() {
        if let requestedExperienceID = requestState?.requestedExperienceID,
           requestedExperienceID != activeExperienceID
        {
            deactivateRuntime(requestedExperienceID)
        }
        clearRequest()
    }

    private func clearRequest() {
        readinessTask?.cancel()
        readinessTask = nil
        requestState = nil
    }

    private func scheduleReadinessDeadline(
        for request: ExperienceRequest,
        now: Date,
    ) {
        readinessTask?.cancel()
        let delay = max(0, request.deadline.timeIntervalSince(now))
        readinessTask = Task(name: "Throw projection experience readiness") {
            [clock, weak self] in
            do {
                try await clock.sleep(for: .seconds(delay))
                await self?.expireReadiness(
                    id: request.id,
                    generation: request.generation,
                )
            } catch is CancellationError {
                return
            } catch {
                await self?.expireReadiness(
                    id: request.id,
                    generation: request.generation,
                )
            }
        }
    }

    private func expireReadiness(
        id: ProjectionExperienceID,
        generation: UInt64,
    ) async {
        guard case let .awaiting(request) = requestState,
              request.id == id,
              request.generation == generation
        else { return }
        await rejectRequestedExperience(failure: .transport)
    }

    private func cancelRotation() {
        timerGeneration &+= 1
        rotationTask?.cancel()
        rotationTask = nil
        dwellEndsAt = nil
    }

    private func publishState() {
        stateContinuation.yield(stateValue())
    }

    private func stateValue() -> ProjectionExperienceCoordinatorState {
        let health = runtimeStates.mapValues(\.health)
        let nextID = activeExperienceID.flatMap(playlist.experience(after:))
        return ProjectionExperienceCoordinatorState(
            activeExperienceID: activeExperienceID,
            requestedExperienceID: requestState?.requestedExperienceID,
            prewarmingExperienceID: requestState?.prewarmingExperienceID,
            isPaused: isPaused,
            dwellEndsAt: dwellEndsAt,
            nextExperienceID: nextID,
            healthByExperience: health,
            manualSelectionFailure: manualSelectionFailure,
        )
    }

    private var playlist: ProjectionPlaylist {
        playlistState.playlist
    }

    private var activeExperienceID: ProjectionExperienceID? {
        playlistState.activeExperienceID
    }
}
