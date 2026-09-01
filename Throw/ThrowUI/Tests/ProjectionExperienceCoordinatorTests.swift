import Foundation
import Testing
@_spi(Testing) @testable import ThrowCore
@testable import ThrowUI

struct ProjectionExperienceCoordinatorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func configuringAPlaylistAfterEmptyStateAdoptsItsSelection() async throws {
        let coordinator = ProjectionExperienceCoordinator(
            playlist: ThrowPreferences.defaultValue.playlist,
            clock: ManualProjectionRotationClock(now: start),
        )
        let playlist = try singleExperiencePlaylist(dwellDuration: .defaultValue)

        await coordinator.configure(ProjectionPlaylistConfiguration(
            playlist: playlist,
            revision: .init(rawValue: 1),
        ))

        let state = await coordinator.currentState()
        #expect(state.activeExperienceID == .airAndSpace)
        #expect(state.nextExperienceID == nil)
    }

    @Test func olderPlaylistConfigurationCannotReplaceANewerRevision() async throws {
        let coordinator = ProjectionExperienceCoordinator(
            playlist: ThrowPreferences.defaultValue.playlist,
            clock: ManualProjectionRotationClock(now: start),
        )
        let olderPlaylist = try singleExperiencePlaylist(
            dwellDuration: ProjectionDwellDuration(seconds: 300),
        )
        let newerPlaylist = try singleExperiencePlaylist(
            dwellDuration: ProjectionDwellDuration(seconds: 600),
        )

        await coordinator.configure(ProjectionPlaylistConfiguration(
            playlist: newerPlaylist,
            revision: .init(rawValue: 2),
        ))
        await coordinator.configure(ProjectionPlaylistConfiguration(
            playlist: olderPlaylist,
            revision: .init(rawValue: 1),
        ))

        #expect(await coordinator.currentPlaylist() == newerPlaylist)
    }

    @Test func queuesEveryLifecycleCommandUntilTheRuntimeConsumesIt() async throws {
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: singleExperiencePlaylist(dwellDuration: .defaultValue),
            clock: ManualProjectionRotationClock(now: start),
        )

        for _ in 0 ..< 40 {
            await coordinator.reconcile(demand: projectingDemand)
            await coordinator.reconcile(demand: disconnectedDemand)
        }

        #expect(await coordinator.runningExperienceIDsForTesting().isEmpty)
    }

    @Test func cancelledDwellStartCannotPublishAfterItsClockReadResumes() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await clock.suspendNextNowCall()

        let updateTask = Task {
            await coordinator.reportRuntimeUpdate(
                id: active.id,
                generation: active.generation,
                successfulGeneration: active.generation,
                health: .healthy(lastUpdate: start, visibleContentCount: 0),
            )
        }
        await clock.waitForNowCallToSuspend()
        await coordinator.reconcile(demand: disconnectedDemand)
        #expect(try #require(await actions.next()) == .deactivate(id: .airAndSpace))
        await clock.resumeSuspendedNowCall()
        await updateTask.value

        let state = await coordinator.currentState()
        #expect(state.dwellEndsAt == nil)
        #expect(await coordinator.runningExperienceIDsForTesting().isEmpty)
    }

    @Test func pauseIsIgnoredWithoutProjectionDemand() async throws {
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: ManualProjectionRotationClock(now: start),
        )

        await coordinator.pause()

        #expect(await (coordinator.currentState()).isPaused == false)
    }

    @Test func prewarmsAtFifteenSecondsAndSwitchesOnlyAfterFreshSuccess() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()

        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        #expect(active.id == .airAndSpace)
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await clock.waitForSleeperCount(1)

        await clock.advance(by: 105)
        let prewarm = try activation(#require(await actions.next()))
        #expect(prewarm.id == .transit)
        #expect(prewarm.role == .prewarming)
        #expect(await coordinator.runningExperienceIDsForTesting() == [.airAndSpace, .transit])
        await reportSuccess(coordinator, id: prewarm.id, generation: prewarm.generation)
        #expect(await (coordinator.currentState()).activeExperienceID == .airAndSpace)

        await clock.waitForSleeperCount(2)
        await clock.advance(by: 15)
        let transition = try #require(await actions.next())
        #expect(
            transition == .beginTransition(
                from: .airAndSpace,
                to: .transit,
                generation: prewarm.generation,
            ),
        )
        #expect(await (coordinator.currentState()).activeExperienceID == .airAndSpace)

        #expect(await coordinator.commitTransition(to: .transit, generation: prewarm.generation))
        #expect(try #require(await actions.next()) == .deactivate(id: .airAndSpace))
        #expect(await (coordinator.currentState()).activeExperienceID == .transit)
        #expect(await (coordinator.currentState()).dwellEndsAt == nil)
        await coordinator.completeTransition(to: .transit, generation: prewarm.generation)
        #expect(await (coordinator.currentState()).dwellEndsAt != nil)
    }

    @Test func delayedSuccessWithinGraceTransitionsWithoutBlankingCurrent() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 105)
        let target = try activation(#require(await actions.next()))
        await clock.waitForSleeperCount(2)
        await clock.advance(by: 15)

        #expect(await (coordinator.currentState()).activeExperienceID == .airAndSpace)
        await reportSuccess(coordinator, id: target.id, generation: target.generation)
        #expect(
            try #require(await actions.next()) == .beginTransition(
                from: .airAndSpace,
                to: .transit,
                generation: target.generation,
            ),
        )
    }

    @Test func successfulTargetWaitsForItsProjectedFrameBeforeTransitioning() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await coordinator.select(.transit)
        let target = try activation(#require(await actions.next()))

        await coordinator.reportRuntimeUpdate(
            id: target.id,
            generation: target.generation,
            successfulGeneration: target.generation,
            health: .healthy(lastUpdate: start, visibleContentCount: 0),
        )

        #expect(await (coordinator.currentState()).requestedExperienceID == .transit)
        #expect(await coordinator.reportRuntimePrepared(
            id: target.id,
            generation: target.generation,
        ))
        #expect(
            try #require(await actions.next()) == .beginTransition(
                from: .airAndSpace,
                to: .transit,
                generation: target.generation,
            ),
        )
    }

    @Test func cancelledPreparationCannotCommitAfterItsClockReadResumes() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await coordinator.select(.transit)
        let target = try activation(#require(await actions.next()))
        await coordinator.reportRuntimeUpdate(
            id: target.id,
            generation: target.generation,
            successfulGeneration: target.generation,
            health: .healthy(lastUpdate: start, visibleContentCount: 0),
        )
        await clock.suspendNextNowCall()

        let preparationTask = Task {
            await coordinator.reportRuntimePrepared(
                id: target.id,
                generation: target.generation,
            )
        }
        await clock.waitForNowCallToSuspend()
        await coordinator.reconcile(demand: disconnectedDemand)
        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        #expect(try #require(await actions.next()) == .deactivate(id: .airAndSpace))
        await clock.resumeSuspendedNowCall()

        #expect(await preparationTask.value == false)
        #expect(await (coordinator.currentState()).activeExperienceID == .airAndSpace)
    }

    @Test func readinessTimeoutKeepsCurrentAndStartsAFreshDwell() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 105)
        _ = try activation(#require(await actions.next()))
        await clock.waitForSleeperCount(2)
        await clock.advance(by: 15)
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 30)

        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        await clock.waitForSleeperCount(1)
        let state = await coordinator.currentState()
        #expect(state.activeExperienceID == .airAndSpace)
        #expect(state.requestedExperienceID == nil)
        #expect(state.dwellEndsAt != nil)
    }

    @Test func manualSelectionRequiresFreshGenerationAndReportsFailure() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)

        await coordinator.select(.transit)
        let target = try activation(#require(await actions.next()))
        await coordinator.reportRuntimeUpdate(
            id: target.id,
            generation: target.generation,
            successfulGeneration: nil,
            health: .failed(.sourceNotValidated),
        )
        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        let failed = await coordinator.currentState()
        #expect(failed.activeExperienceID == .airAndSpace)
        #expect(failed.manualSelectionFailure == .sourceNotValidated)

        await coordinator.select(.transit)
        let replacement = try activation(#require(await actions.next()))
        await reportSuccess(
            coordinator,
            id: replacement.id,
            generation: target.generation,
        )
        #expect(await (coordinator.currentState()).requestedExperienceID == .transit)
        await reportSuccess(
            coordinator,
            id: replacement.id,
            generation: replacement.generation,
        )
        #expect(
            try #require(await actions.next()) == .beginTransition(
                from: .airAndSpace,
                to: .transit,
                generation: replacement.generation,
            ),
        )
    }

    @Test func staleRuntimeFailureCannotRejectANewerRequestAfterClockReadResumes() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)

        await coordinator.select(.transit)
        let staleTarget = try activation(#require(await actions.next()))
        await clock.suspendNextNowCall()
        let failureTask = Task {
            await coordinator.reportRuntimeUpdate(
                id: staleTarget.id,
                generation: staleTarget.generation,
                successfulGeneration: nil,
                health: .failed(.transport),
            )
        }
        await clock.waitForNowCallToSuspend()

        await coordinator.select(.transit)
        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        let replacement = try activation(#require(await actions.next()))
        #expect(replacement.generation > staleTarget.generation)
        await clock.resumeSuspendedNowCall()
        await failureTask.value

        let state = await coordinator.currentState()
        #expect(state.requestedExperienceID == .transit)
        #expect(state.manualSelectionFailure == nil)
        #expect(await coordinator.runningExperienceIDsForTesting() == [.airAndSpace, .transit])
        await reportSuccess(
            coordinator,
            id: replacement.id,
            generation: replacement.generation,
        )
        #expect(
            try #require(await actions.next()) == .beginTransition(
                from: .airAndSpace,
                to: .transit,
                generation: replacement.generation,
            ),
        )
    }

    @Test func manualSelectionTimesOutWithoutBlankingTheActiveExperience() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)

        await coordinator.select(.transit)
        _ = try activation(#require(await actions.next()))
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 30)

        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        let state = await coordinator.currentState()
        #expect(state.activeExperienceID == .airAndSpace)
        #expect(state.requestedExperienceID == nil)
        #expect(state.manualSelectionFailure == .transport)
        #expect(await coordinator.runningExperienceIDsForTesting() == [.airAndSpace])
    }

    @Test func pauseAndLifecycleChangesCancelPrewarmingAndResetDwell() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 105)
        _ = try activation(#require(await actions.next()))

        await coordinator.pause()
        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        #expect(await (coordinator.currentState()).isPaused)
        #expect(await (coordinator.currentState()).dwellEndsAt == nil)

        await coordinator.resume()
        #expect(await (coordinator.currentState()).dwellEndsAt != nil)
        await coordinator.reconcile(
            demand: ProjectionExperienceDemand(
                hasOutput: false,
                isForeground: true,
                isQuiet: false,
                isCalibrating: false,
            ),
        )
        #expect(try #require(await actions.next()) == .deactivate(id: .airAndSpace))
        let disconnected = await coordinator.currentState()
        #expect(disconnected.isPaused == false)
        #expect(disconnected.dwellEndsAt == nil)
    }

    @Test func backgroundQuietAndCalibrationStopEveryRuntimeAndTimer() async throws {
        let suspendedDemands = [
            ProjectionExperienceDemand(
                hasOutput: true,
                isForeground: false,
                isQuiet: false,
                isCalibrating: false,
            ),
            ProjectionExperienceDemand(
                hasOutput: true,
                isForeground: true,
                isQuiet: true,
                isCalibrating: false,
            ),
            ProjectionExperienceDemand(
                hasOutput: true,
                isForeground: true,
                isQuiet: false,
                isCalibrating: true,
            ),
        ]

        for demand in suspendedDemands {
            let clock = ManualProjectionRotationClock(now: start)
            let coordinator = try ProjectionExperienceCoordinator(
                playlist: rotatingPlaylist(),
                clock: clock,
            )
            var actions = await coordinator.actions().makeAsyncIterator()
            await coordinator.reconcile(demand: projectingDemand)
            let active = try activation(#require(await actions.next()))
            await reportSuccess(coordinator, id: active.id, generation: active.generation)

            await coordinator.reconcile(demand: demand)

            #expect(try #require(await actions.next()) == .deactivate(id: .airAndSpace))
            #expect(await coordinator.runningExperienceIDsForTesting().isEmpty)
            let state = await coordinator.currentState()
            #expect(state.dwellEndsAt == nil)
            #expect(state.prewarmingExperienceID == nil)
        }
    }

    @Test func terminalPrewarmFailureSkipsToTheNextCandidateWithoutBlanking() async throws {
        let thirdID = try #require(
            ProjectionExperienceID(testingRawValue: "third-snapshot-experience"),
        )
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(thirdExperienceID: thirdID),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 105)
        let failedTarget = try activation(#require(await actions.next()))

        await coordinator.reportRuntimeUpdate(
            id: failedTarget.id,
            generation: failedTarget.generation,
            successfulGeneration: nil,
            health: .failed(.transport),
        )

        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        let replacement = try activation(#require(await actions.next()))
        #expect(replacement.id == thirdID)
        #expect(replacement.role == .prewarming)
        let state = await coordinator.currentState()
        #expect(state.activeExperienceID == .airAndSpace)
        #expect(state.prewarmingExperienceID == thirdID)
        #expect(await coordinator.runningExperienceIDsForTesting() == [.airAndSpace, thirdID])
    }

    @Test func disablingRotationCancelsAnInFlightPrewarm() async throws {
        let clock = ManualProjectionRotationClock(now: start)
        let coordinator = try ProjectionExperienceCoordinator(
            playlist: rotatingPlaylist(),
            clock: clock,
        )
        var actions = await coordinator.actions().makeAsyncIterator()
        await coordinator.reconcile(demand: projectingDemand)
        let active = try activation(#require(await actions.next()))
        await reportSuccess(coordinator, id: active.id, generation: active.generation)
        await clock.waitForSleeperCount(1)
        await clock.advance(by: 105)
        _ = try activation(#require(await actions.next()))

        let rotationDisabled = try twoExperiencePlaylist(automaticRotationEnabled: false)
        await coordinator.configure(ProjectionPlaylistConfiguration(
            playlist: rotationDisabled,
            revision: .init(rawValue: 1),
        ))

        #expect(try #require(await actions.next()) == .deactivate(id: .transit))
        let state = await coordinator.currentState()
        #expect(state.requestedExperienceID == nil)
        #expect(state.prewarmingExperienceID == nil)
        #expect(state.dwellEndsAt == nil)
        #expect(await coordinator.runningExperienceIDsForTesting() == [.airAndSpace])
    }

    private var projectingDemand: ProjectionExperienceDemand {
        ProjectionExperienceDemand(
            hasOutput: true,
            isForeground: true,
            isQuiet: false,
            isCalibrating: false,
        )
    }

    private var disconnectedDemand: ProjectionExperienceDemand {
        ProjectionExperienceDemand(
            hasOutput: false,
            isForeground: true,
            isQuiet: false,
            isCalibrating: false,
        )
    }

    private func rotatingPlaylist() throws -> ProjectionPlaylist {
        try twoExperiencePlaylist(automaticRotationEnabled: true)
    }

    private func singleExperiencePlaylist(
        dwellDuration: ProjectionDwellDuration,
    ) throws -> ProjectionPlaylist {
        try ProjectionPlaylist(
            entries: [
                ProjectionPlaylistEntry(
                    experienceID: .airAndSpace,
                    dwellDuration: dwellDuration,
                ),
            ],
            automaticRotationEnabled: false,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace],
            catalog: .standard,
        )
    }

    private func twoExperiencePlaylist(
        automaticRotationEnabled: Bool,
    ) throws -> ProjectionPlaylist {
        let catalog = ProjectionExperienceCatalog(
            descriptors: [
                ProjectionExperienceDescriptor(
                    id: .airAndSpace,
                    availability: .enabled,
                    supportedModes: [.map, .trueSky],
                    layerIDs: [.geography, .flights],
                    visibleContentKind: .aircraft,
                    zOrder: 0,
                ),
                ProjectionExperienceDescriptor(
                    id: .transit,
                    availability: .enabled,
                    supportedModes: [.map],
                    layerIDs: [.geography, .transitNetwork, .transitVehicles],
                    visibleContentKind: .vehicles,
                    zOrder: 10,
                ),
            ],
            layerCatalog: .standard,
        )
        return try ProjectionPlaylist(
            entries: [
                ProjectionPlaylistEntry(
                    experienceID: .airAndSpace,
                    dwellDuration: .defaultValue,
                ),
                ProjectionPlaylistEntry(
                    experienceID: .transit,
                    dwellDuration: .defaultValue,
                ),
            ],
            automaticRotationEnabled: automaticRotationEnabled,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace, .transit],
            catalog: catalog,
        )
    }

    private func rotatingPlaylist(
        thirdExperienceID: ProjectionExperienceID,
    ) throws -> ProjectionPlaylist {
        let catalog = ProjectionExperienceCatalog(
            descriptors: [
                ProjectionExperienceDescriptor(
                    id: .airAndSpace,
                    availability: .enabled,
                    supportedModes: [.map, .trueSky],
                    layerIDs: [.geography, .flights],
                    visibleContentKind: .aircraft,
                    zOrder: 0,
                ),
                ProjectionExperienceDescriptor(
                    id: .transit,
                    availability: .enabled,
                    supportedModes: [.map],
                    layerIDs: [.geography, .transitNetwork, .transitVehicles],
                    visibleContentKind: .vehicles,
                    zOrder: 10,
                ),
                ProjectionExperienceDescriptor(
                    id: thirdExperienceID,
                    availability: .enabled,
                    supportedModes: [.map],
                    layerIDs: [.geography],
                    visibleContentKind: .objects,
                    zOrder: 20,
                ),
            ],
            layerCatalog: .standard,
        )
        let entries = [.airAndSpace, .transit, thirdExperienceID].map {
            ProjectionPlaylistEntry(
                experienceID: $0,
                dwellDuration: .defaultValue,
            )
        }
        return try ProjectionPlaylist(
            entries: entries,
            automaticRotationEnabled: true,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: Set(entries.map(\.experienceID)),
            catalog: catalog,
        )
    }

    private func reportSuccess(
        _ coordinator: ProjectionExperienceCoordinator,
        id: ProjectionExperienceID,
        generation: UInt64,
    ) async {
        await coordinator.reportRuntimeUpdate(
            id: id,
            generation: generation,
            successfulGeneration: generation,
            health: .healthy(lastUpdate: start, visibleContentCount: 0),
        )
        _ = await coordinator.reportRuntimePrepared(id: id, generation: generation)
    }

    private func activation(
        _ action: ProjectionExperienceCoordinatorAction,
    ) throws
        -> (
            id: ProjectionExperienceID,
            generation: UInt64,
            role: ProjectionExperienceActivationRole
        )
    {
        guard case let .activate(id, generation, role) = action else {
            Issue.record("Expected an activation action")
            throw TestFailure.unexpectedAction
        }
        return (id, generation, role)
    }

    private enum TestFailure: Error {
        case unexpectedAction
    }
}

private actor ManualProjectionRotationClock: ProjectionRotationClock {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var current: Date
    private var sleepers: [UUID: Sleeper] = [:]
    private var countWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var suspendsNextNowCall = false
    private var suspendedNowCall: CheckedContinuation<Date, Never>?
    private var nowSuspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(now: Date) {
        current = now
    }

    func now() async -> Date {
        guard suspendsNextNowCall else { return current }
        suspendsNextNowCall = false
        return await withCheckedContinuation { continuation in
            precondition(suspendedNowCall == nil, "Only one clock read can suspend at a time")
            suspendedNowCall = continuation
            let waiters = nowSuspensionWaiters
            nowSuspensionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func suspendNextNowCall() {
        precondition(suspendedNowCall == nil, "A clock read is already suspended")
        suspendsNextNowCall = true
    }

    func waitForNowCallToSuspend() async {
        guard suspendedNowCall == nil else { return }
        await withCheckedContinuation { continuation in
            nowSuspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedNowCall() {
        guard let suspendedNowCall else {
            Issue.record("Expected a suspended clock read")
            return
        }
        self.suspendedNowCall = nil
        suspendedNowCall.resume(returning: current)
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        let deadline = current.addingTimeInterval(duration.timeInterval)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    resumeCountWaiters()
                }
            }
        }, onCancel: {
            Task { await self.cancel(id: id) }
        })
    }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let ready = sleepers.filter { $0.value.deadline <= current }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
        resumeCountWaiters()
    }

    func waitForSleeperCount(_ count: Int) async {
        guard sleepers.count != count else { return }
        await withCheckedContinuation { continuation in
            countWaiters[count, default: []].append(continuation)
        }
    }

    private func cancel(id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
        resumeCountWaiters()
    }

    private func resumeCountWaiters() {
        let waiters = countWaiters.removeValue(forKey: sleepers.count) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds) +
            TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
