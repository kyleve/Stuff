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

/// Owns the single projection playlist timer and transactional View switching state.
actor ProjectionExperienceCoordinator {
    private struct RuntimeState {
        var generation: UInt64 = 0
        var successfulGeneration: UInt64?
        var health: FeedHealth = .idle
        var isRunning = false
    }

    private static let prewarmLeadSeconds = 15
    private static let readinessGraceSeconds = 30

    private let clock: any ProjectionRotationClock
    private let stateStream: AsyncStream<ProjectionExperienceCoordinatorState>
    private let stateContinuation: AsyncStream<ProjectionExperienceCoordinatorState>.Continuation
    private let actionStream: AsyncStream<ProjectionExperienceCoordinatorAction>
    private let actionContinuation: AsyncStream<ProjectionExperienceCoordinatorAction>.Continuation

    private var playlist: ProjectionPlaylist
    private var demand = ProjectionExperienceDemand(
        hasOutput: false,
        isForeground: true,
        isQuiet: false,
        isCalibrating: false,
    )
    private var activeExperienceID: ProjectionExperienceID?
    private var requestedExperienceID: ProjectionExperienceID?
    private var prewarmingExperienceID: ProjectionExperienceID?
    private var transitionGeneration: UInt64?
    private var intendedTransitionAt: Date?
    private var requestIsManual = false
    private var isPaused = false
    private var dwellEndsAt: Date?
    private var manualSelectionFailure: ThrowFailureCategory?
    private var runtimeStates: [ProjectionExperienceID: RuntimeState] = [:]
    private var nextGeneration: UInt64 = 0
    private var timerGeneration: UInt64 = 0
    private var rotationTask: Task<Void, Never>?

    init(
        playlist: ProjectionPlaylist,
        clock: any ProjectionRotationClock,
    ) {
        self.playlist = playlist
        self.clock = clock
        activeExperienceID = playlist.selectedExperienceID ?? playlist.entries.first?.experienceID
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

    func configure(_ playlist: ProjectionPlaylist) async {
        self.playlist = playlist
        manualSelectionFailure = nil
        cancelRotation()
        cancelRequestedRuntime()
        let configuredIDs = Set(playlist.entries.map(\.experienceID))
        let removedIDs = runtimeStates.keys.filter { configuredIDs.contains($0) == false }
        for id in removedIDs {
            deactivateRuntime(id)
            runtimeStates.removeValue(forKey: id)
        }
        if let activeExperienceID, configuredIDs.contains(activeExperienceID) == false {
            self.activeExperienceID = playlist.selectedExperienceID ?? playlist.entries.first?
                .experienceID
        }
        publishState()
        if demand.permitsProjection {
            await activateCurrentIfNeeded()
        }
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
           requestedExperienceID == nil,
           transitionGeneration == nil,
           dwellEndsAt == nil
        {
            await startFreshDwell()
        }

        guard id == requestedExperienceID else { return }
        if case let .failed(failure) = health {
            await rejectRequestedExperience(failure: failure)
            return
        }
        guard runtime.successfulGeneration == generation else { return }
        let now = await clock.now()
        if requestIsManual || (intendedTransitionAt.map { now >= $0 } ?? false) {
            beginTransitionIfReady()
        }
    }

    func select(_ id: ProjectionExperienceID) async {
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
            activeExperienceID = id
            manualSelectionFailure = nil
            publishState()
            return
        }
        await requestExperience(id, role: .manual, intendedTransitionAt: clock.now())
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
        if prewarmingExperienceID != nil {
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
        guard requestedExperienceID == id,
              transitionGeneration == generation,
              runtimeStates[id]?.successfulGeneration == generation
        else { return false }
        let oldID = activeExperienceID
        activeExperienceID = id
        requestedExperienceID = nil
        prewarmingExperienceID = nil
        intendedTransitionAt = nil
        requestIsManual = false
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
              transitionGeneration == generation
        else { return }
        transitionGeneration = nil
        publishState()
        await startFreshDwell()
    }

    private func activateCurrentIfNeeded() async {
        guard let activeExperienceID else { return }
        if runtimeStates[activeExperienceID]?.isRunning != true {
            activateRuntime(activeExperienceID, role: .active)
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
                try await clock.sleep(for: .seconds(Self.readinessGraceSeconds))
                await self?.expireAutomaticReadiness(timerGeneration: generation)
            } catch is CancellationError {
                return
            } catch {
                await self?.expireAutomaticReadiness(timerGeneration: generation)
            }
        }
    }

    private func beginAutomaticPrewarm(timerGeneration: UInt64) async {
        guard timerGeneration == self.timerGeneration,
              demand.permitsProjection,
              isPaused == false,
              let activeExperienceID,
              let nextID = playlist.experience(after: activeExperienceID),
              let dwellEndsAt
        else { return }
        requestExperience(nextID, role: .prewarming, intendedTransitionAt: dwellEndsAt)
    }

    private func reachAutomaticTransitionTime(timerGeneration: UInt64) {
        guard timerGeneration == self.timerGeneration else { return }
        dwellEndsAt = nil
        publishState()
        beginTransitionIfReady()
    }

    private func expireAutomaticReadiness(timerGeneration: UInt64) async {
        guard timerGeneration == self.timerGeneration,
              requestedExperienceID != nil,
              transitionGeneration == nil
        else { return }
        await rejectRequestedExperience(failure: .transport)
    }

    private func requestExperience(
        _ id: ProjectionExperienceID,
        role: ProjectionExperienceActivationRole,
        intendedTransitionAt: Date,
    ) {
        if role != .prewarming {
            cancelRotation()
        }
        cancelRequestedRuntime()
        requestedExperienceID = id
        prewarmingExperienceID = role == .prewarming ? id : nil
        self.intendedTransitionAt = intendedTransitionAt
        requestIsManual = role == .manual
        manualSelectionFailure = nil
        activateRuntime(id, role: role)
        publishState()
    }

    private func beginTransitionIfReady() {
        guard transitionGeneration == nil,
              let from = activeExperienceID,
              let to = requestedExperienceID,
              let runtime = runtimeStates[to],
              runtime.successfulGeneration == runtime.generation
        else { return }
        transitionGeneration = runtime.generation
        prewarmingExperienceID = nil
        actionContinuation.yield(
            .beginTransition(from: from, to: to, generation: runtime.generation),
        )
        publishState()
    }

    private func rejectRequestedExperience(failure: ThrowFailureCategory) async {
        let wasManual = requestIsManual
        let failedID = requestedExperienceID
        cancelRequestedRuntime()
        if wasManual {
            manualSelectionFailure = failure
        }
        publishState()

        guard wasManual == false,
              let activeExperienceID,
              let failedID,
              let nextCandidate = playlist.experience(after: failedID),
              nextCandidate != activeExperienceID
        else {
            await startFreshDwell()
            return
        }
        await requestExperience(
            nextCandidate,
            role: .prewarming,
            intendedTransitionAt: clock.now(),
        )
    }

    private func activateRuntime(
        _ id: ProjectionExperienceID,
        role: ProjectionExperienceActivationRole,
    ) {
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
    }

    private func deactivateRuntime(_ id: ProjectionExperienceID) {
        guard runtimeStates[id]?.isRunning == true else { return }
        runtimeStates[id]?.isRunning = false
        runtimeStates[id]?.successfulGeneration = nil
        runtimeStates[id]?.health = .idle
        actionContinuation.yield(.deactivate(id: id))
    }

    private func cancelRequestedRuntime() {
        if let requestedExperienceID, requestedExperienceID != activeExperienceID {
            deactivateRuntime(requestedExperienceID)
        }
        clearRequest()
    }

    private func clearRequest() {
        requestedExperienceID = nil
        prewarmingExperienceID = nil
        transitionGeneration = nil
        intendedTransitionAt = nil
        requestIsManual = false
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
            requestedExperienceID: requestedExperienceID,
            prewarmingExperienceID: prewarmingExperienceID,
            isPaused: isPaused,
            dwellEndsAt: dwellEndsAt,
            nextExperienceID: nextID,
            healthByExperience: health,
            manualSelectionFailure: manualSelectionFailure,
        )
    }
}
