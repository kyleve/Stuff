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

/// The coordinator-issued identity of one logical experience activation.
struct ProjectionActivationLease: Equatable, Hashable {
    struct Generation: Comparable, Hashable {
        static let initial = Generation(rawValue: 0)

        let rawValue: UInt64

        func successor() -> Generation {
            precondition(rawValue < UInt64.max, "An activation generation must not overflow")
            return Generation(rawValue: rawValue + 1)
        }

        static func < (lhs: Generation, rhs: Generation) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let experienceID: ProjectionExperienceID
    let generation: Generation
}

/// Rejects lifecycle commands older than the newest lease observed for one experience.
struct ProjectionActivationLeaseTracker {
    private enum Lifecycle {
        case idle
        case active(ProjectionActivationLease)
        case inactive(latestGeneration: ProjectionActivationLease.Generation)
    }

    let experienceID: ProjectionExperienceID
    private var lifecycle = Lifecycle.idle

    var activeLease: ProjectionActivationLease? {
        guard case let .active(lease) = lifecycle else { return nil }
        return lease
    }

    mutating func activate(_ lease: ProjectionActivationLease) -> Bool {
        guard lease.experienceID == experienceID else { return false }
        switch lifecycle {
            case .idle:
                lifecycle = .active(lease)
                return true
            case let .active(currentLease):
                guard lease.generation >= currentLease.generation else { return false }
                lifecycle = .active(lease)
                return true
            case let .inactive(latestGeneration):
                guard lease.generation > latestGeneration else { return false }
                lifecycle = .active(lease)
                return true
        }
    }

    mutating func deactivate(_ lease: ProjectionActivationLease) -> Bool {
        guard lease.experienceID == experienceID else { return false }
        switch lifecycle {
            case .idle:
                lifecycle = .inactive(latestGeneration: lease.generation)
                return true
            case let .active(activeLease):
                guard lease.generation >= activeLease.generation else { return false }
                lifecycle = .inactive(latestGeneration: lease.generation)
                return true
            case let .inactive(latestGeneration):
                guard lease.generation >= latestGeneration else { return false }
                lifecycle = .inactive(latestGeneration: lease.generation)
                return true
        }
    }

    mutating func synchronize(with authoritativeLease: ProjectionActivationLease?) {
        if let authoritativeLease {
            _ = activate(authoritativeLease)
        } else if case let .active(activeLease) = lifecycle {
            lifecycle = .inactive(latestGeneration: activeLease.generation)
        }
    }
}

enum ProjectionActivationLeaseRenewal: Equatable {
    case replaced(from: ProjectionActivationLease, to: ProjectionActivationLease)
    case retired(lease: ProjectionActivationLease)
    case superseded(
        expected: ProjectionActivationLease,
        current: ProjectionActivationLease,
    )
}

enum ProjectionExperienceCoordinatorAction: Equatable {
    case activate(
        lease: ProjectionActivationLease,
        role: ProjectionExperienceActivationRole,
    )
    case deactivate(lease: ProjectionActivationLease)
    case beginTransition(
        from: ProjectionExperienceID,
        to: ProjectionActivationLease,
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

    init(playlist: ProjectionPlaylist) {
        let activeExperienceID = playlist.selectedExperienceID
        self.init(
            activeExperienceID: activeExperienceID,
            requestedExperienceID: nil,
            prewarmingExperienceID: nil,
            isPaused: false,
            dwellEndsAt: nil,
            nextExperienceID: activeExperienceID.flatMap(playlist.experience(after:)),
            healthByExperience: [:],
            manualSelectionFailure: nil,
        )
    }

    init(
        activeExperienceID: ProjectionExperienceID?,
        requestedExperienceID: ProjectionExperienceID?,
        prewarmingExperienceID: ProjectionExperienceID?,
        isPaused: Bool,
        dwellEndsAt: Date?,
        nextExperienceID: ProjectionExperienceID?,
        healthByExperience: [ProjectionExperienceID: FeedHealth],
        manualSelectionFailure: ThrowFailureCategory?,
    ) {
        self.activeExperienceID = activeExperienceID
        self.requestedExperienceID = requestedExperienceID
        self.prewarmingExperienceID = prewarmingExperienceID
        self.isPaused = isPaused
        self.dwellEndsAt = dwellEndsAt
        self.nextExperienceID = nextExperienceID
        self.healthByExperience = healthByExperience
        self.manualSelectionFailure = manualSelectionFailure
    }

    func updatingHealth(_ health: FeedHealth, for id: ProjectionExperienceID) -> Self {
        var healthByExperience = healthByExperience
        healthByExperience[id] = health
        return Self(
            activeExperienceID: activeExperienceID,
            requestedExperienceID: requestedExperienceID,
            prewarmingExperienceID: prewarmingExperienceID,
            isPaused: isPaused,
            dwellEndsAt: dwellEndsAt,
            nextExperienceID: nextExperienceID,
            healthByExperience: healthByExperience,
            manualSelectionFailure: manualSelectionFailure,
        )
    }
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
        var lease: ProjectionActivationLease?
        var successfulLease: ProjectionActivationLease?
        var preparedLease: ProjectionActivationLease?
        var health: FeedHealth = .idle
        var isRunning = false
    }

    private struct ExperienceRequest {
        enum Timing {
            case manual(deadline: Date)
            case automatic(intendedTransitionAt: Date, deadline: Date)
        }

        let lease: ProjectionActivationLease
        let timing: Timing

        var id: ProjectionExperienceID {
            lease.experienceID
        }

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
    private var nextGeneration = ProjectionActivationLease.Generation.initial
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
            bufferingPolicy: .unbounded,
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

    func activationLease(for id: ProjectionExperienceID) -> ProjectionActivationLease? {
        guard let state = runtimeStates[id], state.isRunning else { return nil }
        return state.lease
    }

    /// Retires one exact running lease for a projection-context replacement.
    /// The active View receives a coordinator-minted successor in the same actor turn.
    func renewActivationLease(
        _ expectedLease: ProjectionActivationLease,
    ) -> ProjectionActivationLeaseRenewal {
        let id = expectedLease.experienceID
        guard let runtime = runtimeStates[id] else {
            return .retired(lease: expectedLease)
        }
        guard let currentLease = runtime.lease else {
            assertionFailure("A coordinator runtime must retain its last minted lease")
            return .retired(lease: expectedLease)
        }
        guard currentLease == expectedLease else {
            return .superseded(expected: expectedLease, current: currentLease)
        }

        let requestUsesExpectedLease = requestState?.request.lease == expectedLease
        if requestUsesExpectedLease {
            clearRequest()
            manualSelectionFailure = nil
        }
        if requestUsesExpectedLease || activeExperienceID == id {
            cancelRotation()
        }
        guard runtime.isRunning else {
            publishState()
            return .retired(lease: expectedLease)
        }
        deactivateRuntime(id)

        guard demand.permitsProjection, activeExperienceID == id else {
            publishState()
            return .retired(lease: expectedLease)
        }
        let replacementLease = activateRuntime(id, role: .active)
        publishState()
        return .replaced(from: expectedLease, to: replacementLease)
    }

    func currentState() -> ProjectionExperienceCoordinatorState {
        stateValue()
    }

    #if DEBUG
        func runningExperienceIDsForTesting() -> Set<ProjectionExperienceID> {
            Set(runtimeStates.compactMap { id, state in state.isRunning ? id : nil })
        }

        func emitActionForTesting(_ action: ProjectionExperienceCoordinatorAction) {
            emitAction(action)
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
        lease: ProjectionActivationLease,
        successfulLease: ProjectionActivationLease?,
        health: FeedHealth,
    ) async {
        let id = lease.experienceID
        guard var runtime = runtimeStates[id],
              runtime.isRunning,
              runtime.lease == lease
        else { return }
        runtime.health = health
        if successfulLease == lease {
            runtime.successfulLease = lease
        }
        runtimeStates[id] = runtime
        publishState()

        if id == activeExperienceID,
           runtime.successfulLease == lease,
           requestState == nil,
           dwellEndsAt == nil
        {
            await startFreshDwell()
        }

        guard case let .awaiting(request) = requestState,
              request.lease == lease
        else { return }
        if case let .failed(failure) = health {
            await rejectRequestedExperience(
                expectedLease: request.lease,
                failure: failure,
            )
        }
    }

    func isAwaitingPreparation(_ lease: ProjectionActivationLease) -> Bool {
        let id = lease.experienceID
        guard demand.permitsProjection,
              case let .awaiting(request) = requestState,
              request.lease == lease,
              let runtime = runtimeStates[id],
              runtime.isRunning,
              runtime.lease == lease,
              runtime.successfulLease == lease
        else { return false }
        return true
    }

    /// Marks a complete projected frame as ready for the current activation.
    func reportRuntimePrepared(_ lease: ProjectionActivationLease) async -> Bool {
        let id = lease.experienceID
        guard isAwaitingPreparation(lease),
              case let .awaiting(request) = requestState,
              var runtime = runtimeStates[id]
        else { return false }
        runtime.preparedLease = lease
        runtimeStates[id] = runtime

        let now = await clock.now()
        guard demand.permitsProjection,
              case let .awaiting(currentRequest) = requestState,
              currentRequest.lease == request.lease,
              runtimeStates[id]?.lease == lease,
              runtimeStates[id]?.successfulLease == lease,
              runtimeStates[id]?.preparedLease == lease
        else { return false }
        if currentRequest.canTransition(at: now) {
            beginTransitionIfReady()
        }
        return true
    }

    func rejectPreparedTransition(
        lease: ProjectionActivationLease,
        failure: ThrowFailureCategory,
    ) async {
        guard let request = requestState?.request,
              request.lease == lease
        else { return }
        await rejectRequestedExperience(
            expectedLease: request.lease,
            failure: failure,
        )
    }

    /// Cancels a prepared request because its source or observer context changed.
    func invalidatePreparedTransition(lease: ProjectionActivationLease) async {
        guard requestState?.request.lease == lease else { return }
        cancelRequestedRuntime()
        manualSelectionFailure = nil
        publishState()
        await startFreshDwell()
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
        guard demand.permitsProjection,
              playlist.rotatesAutomatically,
              isPaused == false
        else { return }
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
    func commitTransition(to lease: ProjectionActivationLease) -> Bool {
        commitTransitionState(to: lease) != nil
    }

    func commitTransitionState(
        to lease: ProjectionActivationLease,
    ) -> ProjectionExperienceCoordinatorState? {
        let id = lease.experienceID
        guard case let .transitioning(request) = requestState,
              request.lease == lease,
              runtimeStates[id]?.successfulLease == lease,
              runtimeStates[id]?.preparedLease == lease
        else { return nil }
        let oldID = activeExperienceID
        guard playlistState.select(id) else {
            assertionFailure("The transition target must be in the playlist")
            return nil
        }
        requestState = .committed(request)
        manualSelectionFailure = nil
        if let oldID, oldID != id {
            deactivateRuntime(oldID)
        }
        publishState()
        return stateValue()
    }

    /// The caller invokes this only after the committed surface completes its fade-in.
    func completeTransition(to lease: ProjectionActivationLease) async {
        let id = lease.experienceID
        guard activeExperienceID == id,
              case let .committed(request) = requestState,
              request.lease == lease
        else { return }
        clearRequest()
        publishState()
        await startFreshDwell()
    }

    private func activateCurrentIfNeeded() async {
        guard let activeExperienceID else { return }
        if runtimeStates[activeExperienceID]?.isRunning != true {
            _ = activateRuntime(activeExperienceID, role: .active)
        } else if runtimeStates[activeExperienceID]?.successfulLease != nil,
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
              let runtimeLease = runtimeStates[activeExperienceID]?.lease,
              runtimeStates[activeExperienceID]?.successfulLease == runtimeLease,
              let entry = playlist.entry(for: activeExperienceID)
        else {
            dwellEndsAt = nil
            publishState()
            return
        }
        timerGeneration &+= 1
        let timerGeneration = timerGeneration
        let playlistRevision = playlistConfigurationRevision
        let now = await clock.now()
        guard timerGeneration == self.timerGeneration,
              playlistRevision == playlistConfigurationRevision,
              demand.permitsProjection,
              isPaused == false,
              playlist.rotatesAutomatically,
              self.activeExperienceID == activeExperienceID,
              runtimeStates[activeExperienceID]?.lease == runtimeLease,
              runtimeStates[activeExperienceID]?.successfulLease == runtimeLease,
              playlist.entry(for: activeExperienceID) == entry
        else { return }
        let dwellSeconds = entry.dwellDuration.seconds
        dwellEndsAt = now.addingTimeInterval(TimeInterval(dwellSeconds))
        publishState()
        rotationTask = Task(name: "Throw projection experience rotation") {
            [clock, weak self] in
            do {
                try await clock.sleep(
                    for: .seconds(dwellSeconds - Self.prewarmLeadSeconds),
                )
                await self?.beginAutomaticPrewarm(timerGeneration: timerGeneration)
                try await clock.sleep(for: .seconds(Self.prewarmLeadSeconds))
                await self?.reachAutomaticTransitionTime(timerGeneration: timerGeneration)
            } catch is CancellationError {
                return
            } catch {
                await self?.handleRotationClockFailure(timerGeneration: timerGeneration)
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
        let lease = activateRuntime(id, role: role)
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
        let request = ExperienceRequest(lease: lease, timing: timing)
        requestState = .awaiting(request)
        scheduleReadinessDeadline(for: request, now: now)
        publishState()
    }

    private func beginTransitionIfReady() {
        guard case let .awaiting(request) = requestState,
              let from = activeExperienceID,
              let runtime = runtimeStates[request.id],
              runtime.lease == request.lease,
              runtime.successfulLease == request.lease,
              runtime.preparedLease == request.lease
        else { return }
        readinessTask?.cancel()
        readinessTask = nil
        requestState = .transitioning(request)
        emitAction(
            .beginTransition(from: from, to: request.lease),
        )
        publishState()
    }

    private func rejectRequestedExperience(
        expectedLease: ProjectionActivationLease,
        failure: ThrowFailureCategory,
    ) async {
        guard let request = requestState?.request,
              request.lease == expectedLease
        else { return }
        let now = await clock.now()
        guard let currentRequest = requestState?.request,
              currentRequest.lease == expectedLease
        else { return }
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
        if let request = requestState?.request {
            await rejectRequestedExperience(
                expectedLease: request.lease,
                failure: .transport,
            )
        } else {
            cancelRotation()
            publishState()
        }
    }

    private func activateRuntime(
        _ id: ProjectionExperienceID,
        role: ProjectionExperienceActivationRole,
    ) -> ProjectionActivationLease {
        nextGeneration = nextGeneration.successor()
        let lease = ProjectionActivationLease(
            experienceID: id,
            generation: nextGeneration,
        )
        var state = runtimeStates[id] ?? RuntimeState()
        state.lease = lease
        state.successfulLease = nil
        state.preparedLease = nil
        state.health = .loading
        state.isRunning = true
        runtimeStates[id] = state
        emitAction(
            .activate(lease: lease, role: role),
        )
        return lease
    }

    private func deactivateRuntime(_ id: ProjectionExperienceID) {
        guard runtimeStates[id]?.isRunning == true,
              let lease = runtimeStates[id]?.lease
        else { return }
        runtimeStates[id]?.isRunning = false
        runtimeStates[id]?.successfulLease = nil
        runtimeStates[id]?.preparedLease = nil
        runtimeStates[id]?.health = .idle
        emitAction(.deactivate(lease: lease))
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
                await self?.expireReadiness(lease: request.lease)
            } catch is CancellationError {
                return
            } catch {
                await self?.expireReadiness(lease: request.lease)
            }
        }
    }

    private func expireReadiness(lease: ProjectionActivationLease) async {
        guard case let .awaiting(request) = requestState,
              request.lease == lease
        else { return }
        await rejectRequestedExperience(
            expectedLease: request.lease,
            failure: .transport,
        )
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

    private func emitAction(_ action: ProjectionExperienceCoordinatorAction) {
        switch actionContinuation.yield(action) {
            case .enqueued:
                break
            case .dropped:
                preconditionFailure("The unbounded projection action stream dropped a command")
            case .terminated:
                assertionFailure("The projection action stream ended before its coordinator")
            @unknown default:
                assertionFailure("The projection action stream returned an unknown yield result")
        }
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
