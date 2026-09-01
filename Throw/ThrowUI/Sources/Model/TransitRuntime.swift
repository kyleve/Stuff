import Foundation
import ThrowCore

protocol TransitPollingClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemTransitPollingClock: TransitPollingClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct TransitRuntimeUpdate {
    let activationLease: ProjectionActivationLease?
    let successfulActivationLease: ProjectionActivationLease?
    let health: FeedHealth
    let transitFrame: TransitExperienceFrame

    var experienceFrame: ProjectionExperienceFrame {
        .transit(transitFrame)
    }
}

enum TransitRuntimeActivationResult {
    case accepted(TransitRuntimeUpdate)
    case superseded(current: TransitRuntimeUpdate)
}

enum TransitRuntimePollingSuspensionResult {
    case stopped(TransitRuntimeUpdate)
    case alreadyStopped(current: TransitRuntimeUpdate)
    case superseded(current: TransitRuntimeUpdate)
}

/// Owns the static schedule, partitioned realtime polling, and train position state.
actor TransitRuntime {
    private enum PartitionResult {
        case success(TransitPartitionSnapshot)
        case failure(TransitFeedPartitionID)
        case cancelled
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

    private enum PollingDemandLifecycle {
        case none
        case polling(ProjectionDemandGeneration)
        case stopped(ProjectionDemandGeneration)

        var pollingGeneration: ProjectionDemandGeneration? {
            guard case let .polling(generation) = self else { return nil }
            return generation
        }

        mutating func activate(_ generation: ProjectionDemandGeneration) -> Bool {
            switch self {
                case .none:
                    self = .polling(generation)
                    return true
                case let .polling(currentGeneration):
                    guard generation >= currentGeneration else { return false }
                    self = .polling(generation)
                    return true
                case let .stopped(currentGeneration):
                    guard generation > currentGeneration else { return false }
                    self = .polling(generation)
                    return true
            }
        }

        mutating func stop(_ generation: ProjectionDemandGeneration) -> Bool {
            switch self {
                case .none:
                    self = .stopped(generation)
                    return true
                case let .polling(currentGeneration), let .stopped(currentGeneration):
                    guard generation >= currentGeneration else { return false }
                    self = .stopped(generation)
                    return true
            }
        }

        mutating func stopCurrent() {
            guard case let .polling(generation) = self else { return }
            self = .stopped(generation)
        }
    }

    private struct PollingAttempt: Equatable {
        let activationLease: ProjectionActivationLease
        let demandGeneration: ProjectionDemandGeneration
        let lifecycleGeneration: UInt64
    }

    private static let pollInterval: TimeInterval = 30
    private static let scheduleRefreshInterval: TimeInterval = 60 * 60

    private let observationSource: any TransitObservationSource
    private let scheduleSource: any TransitScheduleSource
    private let scheduleStore: any TransitScheduleStore
    private let networkRuntime: TransitNetworkLayerRuntime
    private let vehiclesRuntime: TransitVehiclesLayerRuntime
    private let dateProvider: any DateProvider
    private let clock: any TransitPollingClock
    private let updatesStream: AsyncStream<TransitRuntimeUpdate>
    private let continuation: AsyncStream<TransitRuntimeUpdate>.Continuation

    private var pollTask: Task<Void, Never>?
    private var activationLifecycle = ActivationLifecycle.idle
    private var pollingDemandLifecycle = PollingDemandLifecycle.none
    private var successfulActivationLease: ProjectionActivationLease?
    private var lifecycleGeneration: UInt64 = 0
    private var schedule: TransitSchedule?
    private var snapshots: [TransitFeedPartitionID: TransitPartitionSnapshot] = [:]
    private var estimator = TransitPositionEstimator()
    private var currentEstimates: [TransitVehicleEstimate] = []
    private var labelMode: TransitLabelMode = .routeOnly
    private var networkFrame: ProjectionLayerFrame<TransitNetworkLayerKind>?
    private var vehiclesFrame: ProjectionLayerFrame<TransitVehiclesLayerKind>?
    private var failureStartedAtByPartition: [TransitFeedPartitionID: Date] = [:]
    private var frameGeneration: UInt64 = 0
    private var health: FeedHealth = .idle
    #if DEBUG
        private var beforeStartingPollingForTesting: (@Sendable () async -> Void)?
    #endif

    init(
        observationSource: any TransitObservationSource,
        scheduleSource: any TransitScheduleSource,
        scheduleStore: any TransitScheduleStore,
        networkRuntime: TransitNetworkLayerRuntime,
        vehiclesRuntime: TransitVehiclesLayerRuntime,
        dateProvider: any DateProvider,
        clock: any TransitPollingClock,
    ) {
        self.observationSource = observationSource
        self.scheduleSource = scheduleSource
        self.scheduleStore = scheduleStore
        self.networkRuntime = networkRuntime
        self.vehiclesRuntime = vehiclesRuntime
        self.dateProvider = dateProvider
        self.clock = clock
        let pair = AsyncStream.makeStream(
            of: TransitRuntimeUpdate.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        updatesStream = pair.stream
        continuation = pair.continuation
    }

    deinit {
        pollTask?.cancel()
        continuation.finish()
    }

    func stateUpdates() -> AsyncStream<TransitRuntimeUpdate> {
        publish()
        return updatesStream
    }

    func currentUpdate() -> TransitRuntimeUpdate {
        updateValue()
    }

    func validateConnection() async throws {
        let now = dateProvider.now()
        try await refreshScheduleIfNeeded(at: now, guarding: nil)
        guard let partitionID = observationSource.partitionIDs.first else {
            throw TransitDataError.unavailable
        }
        _ = try await observationSource.snapshot(for: partitionID, fetchedAt: now)
    }

    func activate(
        labelMode: TransitLabelMode,
        lease: ProjectionActivationLease,
        demandGeneration: ProjectionDemandGeneration,
    ) async -> TransitRuntimeActivationResult {
        guard lease.runnableExperienceID == .transit else {
            assertionFailure("Transit received another experience's activation lease")
            return .superseded(current: updateValue())
        }
        let previousLease = activationLifecycle.activeLease
        let previousDemandGeneration = pollingDemandLifecycle.pollingGeneration
        var nextActivationLifecycle = activationLifecycle
        var nextPollingDemandLifecycle = pollingDemandLifecycle
        guard nextActivationLifecycle.activate(lease),
              nextPollingDemandLifecycle.activate(demandGeneration)
        else {
            return .superseded(current: updateValue())
        }
        activationLifecycle = nextActivationLifecycle
        pollingDemandLifecycle = nextPollingDemandLifecycle
        let activationChanged = previousLease != lease
        let demandChanged = previousDemandGeneration != demandGeneration
        let labelsChanged = self.labelMode != labelMode
        self.labelMode = labelMode
        guard activationChanged || demandChanged || pollTask == nil else {
            guard let attempt = currentPollingAttempt(for: lease) else {
                return .superseded(current: updateValue())
            }
            if labelsChanged {
                _ = await rebuild()
                guard isCurrent(attempt) else {
                    return .superseded(current: updateValue())
                }
                publish()
            }
            guard isCurrent(attempt) else { return .superseded(current: updateValue()) }
            return .accepted(updateValue())
        }

        lifecycleGeneration &+= 1
        let attempt = PollingAttempt(
            activationLease: lease,
            demandGeneration: demandGeneration,
            lifecycleGeneration: lifecycleGeneration,
        )
        let previousPollTask = pollTask
        pollTask = nil
        previousPollTask?.cancel()
        await previousPollTask?.value
        #if DEBUG
            await beforeStartingPollingForTesting?()
        #endif
        guard isCurrent(attempt) else {
            return .superseded(current: updateValue())
        }
        successfulActivationLease = nil
        snapshots = [:]
        currentEstimates = []
        networkFrame = nil
        vehiclesFrame = nil
        failureStartedAtByPartition = [:]
        frameGeneration &+= 1
        estimator.reset()
        health = .loading
        publish()
        let pollTask = Task<Void, Never>(name: "Throw poll Transit") { [weak self] in
            guard let self else { return }
            await pollLoop(attempt: attempt)
        }
        self.pollTask = pollTask
        return .accepted(updateValue())
    }

    func suspendPolling(
        lease: ProjectionActivationLease,
        demandGeneration: ProjectionDemandGeneration,
        reporting health: FeedHealth,
    ) async -> TransitRuntimePollingSuspensionResult {
        guard lease.runnableExperienceID == .transit else {
            assertionFailure("Transit received another experience's polling suspension")
            return .superseded(current: updateValue())
        }
        var nextActivationLifecycle = activationLifecycle
        var nextPollingDemandLifecycle = pollingDemandLifecycle
        guard nextActivationLifecycle.activate(lease),
              nextPollingDemandLifecycle.stop(demandGeneration)
        else {
            return .superseded(current: updateValue())
        }
        activationLifecycle = nextActivationLifecycle
        pollingDemandLifecycle = nextPollingDemandLifecycle
        let wasPolling = pollTask != nil
        guard await stopPhysicalPolling(reporting: health) else {
            return .superseded(current: updateValue())
        }
        return wasPolling ? .stopped(updateValue()) : .alreadyStopped(current: updateValue())
    }

    func deactivate(
        lease: ProjectionActivationLease,
        reporting health: FeedHealth,
    ) async {
        guard lease.runnableExperienceID == .transit else {
            assertionFailure("Transit received another experience's deactivation lease")
            return
        }
        guard activationLifecycle.deactivate(upThrough: lease) else { return }
        pollingDemandLifecycle.stopCurrent()
        _ = await stopPhysicalPolling(reporting: health)
    }

    private func stopPhysicalPolling(reporting health: FeedHealth) async -> Bool {
        // Every accepted stop retires an in-flight activation attempt, including
        // the interval after that attempt clears the previous physical task.
        lifecycleGeneration &+= 1
        let lifecycleGeneration = lifecycleGeneration
        successfulActivationLease = nil
        let previousPollTask = pollTask
        pollTask = nil
        previousPollTask?.cancel()
        await previousPollTask?.value
        guard lifecycleGeneration == self.lifecycleGeneration else { return false }
        snapshots = [:]
        currentEstimates = []
        vehiclesFrame = nil
        networkFrame = nil
        failureStartedAtByPartition = [:]
        frameGeneration &+= 1
        estimator.reset()
        self.health = health
        publish()
        return true
    }

    func updateLabelMode(
        _ labelMode: TransitLabelMode,
        lease: ProjectionActivationLease,
    ) async {
        guard activationLifecycle.activeLease == lease else { return }
        guard self.labelMode != labelMode else { return }
        self.labelMode = labelMode
        guard let attempt = currentPollingAttempt(for: lease) else { return }
        _ = await rebuild()
        guard isCurrent(attempt) else { return }
        publish()
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
        func setBeforeStartingPollingForTesting(
            _ action: (@Sendable () async -> Void)?,
        ) {
            beforeStartingPollingForTesting = action
        }
    #endif

    private func pollLoop(attempt: PollingAttempt) async {
        while isCurrent(attempt) {
            await pollOnce(attempt: attempt)
            guard isCurrent(attempt) else { return }
            do {
                try await clock.sleep(for: .seconds(Self.pollInterval))
            } catch {
                return
            }
        }
    }

    private func pollOnce(attempt: PollingAttempt) async {
        let now = dateProvider.now()
        do {
            try await refreshScheduleIfNeeded(at: now, guarding: attempt)
            try Task.checkCancellation()
            guard isCurrent(attempt) else { return }
        } catch is CancellationError {
            return
        } catch {
            await applyCompleteFailure(at: now, guarding: attempt)
            return
        }

        let source = observationSource
        let results = await withTaskGroup(
            of: PartitionResult.self,
            returning: [PartitionResult].self,
        ) { group in
            for partitionID in source.partitionIDs {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        return try await .success(source.snapshot(
                            for: partitionID,
                            fetchedAt: now,
                        ))
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failure(partitionID)
                    }
                }
            }
            var values: [PartitionResult] = []
            for await value in group {
                values.append(value)
            }
            return values
        }
        guard isCurrent(attempt) else { return }

        let successful = results.compactMap { result -> TransitPartitionSnapshot? in
            if case let .success(snapshot) = result { snapshot } else { nil }
        }
        let failed = results.compactMap { result -> TransitFeedPartitionID? in
            if case let .failure(partitionID) = result { partitionID } else { nil }
        }
        guard successful.isEmpty == false else {
            await applyCompleteFailure(at: now, partitionIDs: failed, guarding: attempt)
            return
        }
        for snapshot in successful {
            snapshots[snapshot.partitionID] = snapshot
            failureStartedAtByPartition.removeValue(forKey: snapshot.partitionID)
        }
        for partitionID in failed where failureStartedAtByPartition[partitionID] == nil {
            failureStartedAtByPartition[partitionID] = now
        }
        if let schedule {
            currentEstimates = estimator.estimates(
                snapshots: Array(snapshots.values),
                schedule: schedule,
                at: now,
            )
        }
        guard await rebuild(), isCurrent(attempt) else { return }
        if failed.isEmpty {
            health = .healthy(lastUpdate: now, visibleContentCount: transitVehicleCount)
        } else {
            health = .retrying(
                lastUpdate: now,
                nextRetry: now.addingTimeInterval(Self.pollInterval),
                failure: .transport,
                visibleContentCount: transitVehicleCount,
            )
        }
        successfulActivationLease = attempt.activationLease
        publish()
    }

    private func refreshScheduleIfNeeded(
        at date: Date,
        guarding attempt: PollingAttempt?,
    ) async throws {
        if schedule == nil {
            let storedSchedule = try await scheduleStore.load()
            try requireCurrent(attempt)
            schedule = storedSchedule
        }
        if let schedule,
           date.timeIntervalSince(schedule.fetchedAt) < Self.scheduleRefreshInterval
        {
            if networkFrame == nil {
                let frame = try await networkRuntime.frame(for: schedule)
                try requireCurrent(attempt)
                networkFrame = frame
            }
            return
        }
        let refreshed = try await scheduleSource.schedule(fetchedAt: date)
        try requireCurrent(attempt)
        try await scheduleStore.save(refreshed)
        try requireCurrent(attempt)
        let frame = try await networkRuntime.frame(for: refreshed)
        try requireCurrent(attempt)
        schedule = refreshed
        networkFrame = frame
        estimator.reset()
        currentEstimates = []
    }

    private func rebuild() async -> Bool {
        guard schedule != nil else { return true }
        frameGeneration &+= 1
        let generation = frameGeneration
        let now = dateProvider.now()
        let estimates = currentEstimates
        let labelMode = labelMode
        let failures = failureStartedAtByPartition
        do {
            var marksByID: [
                TransitVehicleMarkElement.ID: ProjectionMark<TransitVehicleMarkElement>
            ] = [:]
            let estimatesByPartition = Dictionary(
                grouping: estimates,
                by: { $0.run.id.partitionID },
            )
            for partitionID in estimatesByPartition.keys.sorted(by: {
                $0.rawValue < $1.rawValue
            }) {
                guard let partitionEstimates = estimatesByPartition[partitionID] else { continue }
                let availability = failures[partitionID]
                    .map(MarkAvailability.transitRetrying) ?? .current
                let frame = try await vehiclesRuntime.frame(for: TransitVehiclesLayerInput(
                    estimates: partitionEstimates,
                    labelMode: labelMode,
                    fetchedAt: now,
                    availability: availability,
                ))
                for mark in frame.marks where marksByID[mark.id] == nil {
                    marksByID[mark.id] = mark
                }
            }
            guard generation == frameGeneration else { return false }
            vehiclesFrame = ProjectionLayerFrame(
                observedAt: now,
                marks: Array(marksByID.values),
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == frameGeneration else { return false }
            vehiclesFrame = nil
            health = .failed(.decoding)
            return false
        }
    }

    private func applyCompleteFailure(
        at date: Date,
        partitionIDs: [TransitFeedPartitionID]? = nil,
        guarding attempt: PollingAttempt,
    ) async {
        guard isCurrent(attempt) else { return }
        let affected = partitionIDs ?? observationSource.partitionIDs
        for partitionID in affected where failureStartedAtByPartition[partitionID] == nil {
            failureStartedAtByPartition[partitionID] = date
        }
        let rebuilt = await rebuild()
        guard isCurrent(attempt) else { return }
        guard rebuilt else {
            publish()
            return
        }
        if snapshots.isEmpty {
            health = .failed(.transport)
        } else {
            health = .retrying(
                lastUpdate: snapshots.values.map(\.fetchedAt).max(),
                nextRetry: date.addingTimeInterval(Self.pollInterval),
                failure: .transport,
                visibleContentCount: transitVehicleCount,
            )
        }
        publish()
    }

    private func isCurrent(_ attempt: PollingAttempt) -> Bool {
        Task.isCancelled == false &&
            lifecycleGeneration == attempt.lifecycleGeneration &&
            activationLifecycle.activeLease == attempt.activationLease &&
            pollingDemandLifecycle.pollingGeneration == attempt.demandGeneration
    }

    private func currentPollingAttempt(
        for lease: ProjectionActivationLease,
    ) -> PollingAttempt? {
        guard activationLifecycle.activeLease == lease,
              let demandGeneration = pollingDemandLifecycle.pollingGeneration
        else { return nil }
        return PollingAttempt(
            activationLease: lease,
            demandGeneration: demandGeneration,
            lifecycleGeneration: lifecycleGeneration,
        )
    }

    private func requireCurrent(_ attempt: PollingAttempt?) throws {
        try Task.checkCancellation()
        guard let attempt else { return }
        guard isCurrent(attempt) else { throw CancellationError() }
    }

    private var transitVehicleCount: Int {
        vehiclesFrame?.marks.count(where: { mark in
            if case .transitVehicle = mark.glyph { true } else { false }
        }) ?? 0
    }

    private func publish() {
        continuation.yield(updateValue())
    }

    private func updateValue() -> TransitRuntimeUpdate {
        TransitRuntimeUpdate(
            activationLease: activationLifecycle.activeLease,
            successfulActivationLease: successfulActivationLease,
            health: health,
            transitFrame: TransitExperienceFrame(
                geography: nil,
                network: networkFrame,
                vehicles: vehiclesFrame,
            ),
        )
    }
}
