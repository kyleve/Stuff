import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionExperiencesTests {
    @Test func blackCommitKeepsPreparedIdentityAndRevisionAheadOfBufferedInput() throws {
        let session = ThrowSession.fixture()
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let preparedFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let bufferedFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 200),
        )
        let output = try projectionTestAirOutput(
            semanticFrame: preparedFrame,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 150),
            revision: 11,
            observerPoint: ProjectionPoint(x: 0.25, y: 0.75),
        )
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 4),
        )
        session.projectionPresentationState = .initial(
            coordinator: projectionTestCoordinator(activeExperienceID: .transit),
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: Date(timeIntervalSince1970: 50),
        )
        let prepared = try #require(PreparedProjectionPresentation.rendered(
            contextGeneration: session.projectionContextGeneration,
            activationLease: lease,
            output: output,
        ))
        session.replacePendingAirAndSpaceFrameForTesting(bufferedFrame)
        let bufferedUpdate = AirAndSpaceRuntimeUpdate(
            activationLease: lease,
            successfulActivationLease: lease,
            health: .healthy(
                lastUpdate: Date(timeIntervalSince1970: 200),
                visibleContentCount: 0,
            ),
            flightsFrame: bufferedFrame.flights,
            snapshot: nil,
            physicalPolling: .stopped,
            semanticPreparationState: .ready,
        )
        session.projectionPresentationStaging = .fadingOut(
            prepared: prepared,
            bufferedTargetUpdate: bufferedUpdate,
        )
        let preferenceProducer = try #require(
            session.beginPreferenceProducer(.experienceTransition),
        )
        defer { session.finishPreferenceProducer(preferenceProducer) }

        let committed = session.commitPreparedProjectionAtBlack(
            coordinator: projectionTestCoordinator(activeExperienceID: .airAndSpace),
            preferenceProducer: preferenceProducer,
        )

        #expect(committed)
        #expect(session.activeExperienceID == .airAndSpace)
        #expect(session.visibleProjection.activationLease == lease)
        #expect(session.visibleProjection.semanticFrame == .airAndSpace(preparedFrame))
        #expect(session.visibleProjection.request?.revision.rawValue == 11)
        #expect(session.visibleProjection.request?.context.observer == observer)
        #expect(session.projectionFrame.generatedAt == Date(timeIntervalSince1970: 150))
        #expect(session.pendingAirAndSpaceFrame == bufferedFrame)
        #expect(session.projectionPresentationStaging?.bufferedTargetUpdate?.flightsFrame ==
            bufferedFrame.flights)
        #expect(session.projectionPresentationStaging?.preparedProjection == prepared)
    }

    @Test func coordinatorStateCallbackCannotPublishAPreferenceSelection() {
        let session = ThrowSession.fixture()
        let coordinator = projectionTestCoordinator(activeExperienceID: .transit)
        session.projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: session.dateProvider.now(),
        )
        let update = coordinator.updatingHealth(
            .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 4,
            ),
            for: .transit,
        )

        session.applyExperienceCoordinatorState(update)

        #expect(session.activeExperienceID == .transit)
        #expect(session.activeExperienceHealth.visibleContentCount == 4)
        #expect(session.projectionPlaylist.selectedExperienceID == .airAndSpace)
        #expect(session.postLaunchFailureLedger.failure(for: .playlist) == nil)
    }

    @Test func finalBackgroundFlushWaitsForAnAdmittedCoordinatorActionCallback() async throws {
        let session = ThrowSession.fixture()
        session.startLaunch()
        await session.waitForLaunchForTesting()
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 9),
        )
        let activated = session.airAndSpaceActivation.activate(lease)
        #expect(activated)
        session.projectionPresentationStaging = try .prepared(
            preparedAirAndSpaceProjection(for: session, lease: lease),
        )
        let fadeGate = ProjectionTransitionGate()
        session.waitForProjectionFadeOutForTesting = {
            await fadeGate.suspend()
        }

        await session.experienceCoordinator.emitActionForTesting(.beginTransition(
            from: .transit,
            to: lease,
        ))
        await fadeGate.waitForSuspension()
        #expect(session.preferencePersistence.activeProducerCount == 1)
        session.controllerForegroundPresenceDidChange(false)

        let registration = PreferenceFlushCompletionProbe()
        let completion = PreferenceFlushCompletionProbe()
        session.preferenceFlushDidRegisterForTesting = {
            registration.complete()
        }
        let flush = Task {
            await session.flushPreferencesSave()
            completion.complete()
        }
        await registration.waitForCompletion()

        #expect(session.preferencePersistence.quiescenceWaiterCount == 1)
        #expect(completion.isComplete == false)
        await fadeGate.resume()
        await flush.value
        #expect(completion.isComplete)
        #expect(session.preferencePersistence.activeProducerCount == 0)
    }

    @Test func closedAdmissionReconcilesAQueuedCoordinatorTransition() async throws {
        let session = ThrowSession.fixture()
        var actions = await session.experienceCoordinator.actions().makeAsyncIterator()
        try await configureAirAndSpaceRequestFromTransit(on: session)
        let transitActivation = try #require(await actions.next())
        guard case let .activate(transitLease, _) = transitActivation else {
            Issue.record("Expected the Transit activation")
            return
        }
        await session.experienceCoordinator.reportRuntimeUpdate(
            lease: transitLease,
            successfulLease: transitLease,
            health: .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 1,
            ),
        )
        await session.experienceCoordinator.select(.airAndSpace)
        let airAndSpaceActivation = try #require(await actions.next())
        guard case let .activate(airAndSpaceLease, _) = airAndSpaceActivation else {
            Issue.record("Expected the Air & Space activation")
            return
        }
        await session.experienceCoordinator.reportRuntimeUpdate(
            lease: airAndSpaceLease,
            successfulLease: airAndSpaceLease,
            health: .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 1,
            ),
        )
        #expect(await session.experienceCoordinator.reportRuntimePrepared(airAndSpaceLease))
        let transition = try #require(await actions.next())
        guard case .beginTransition = transition else {
            Issue.record("Expected a prepared transition")
            return
        }
        #expect(await session.experienceCoordinator.currentState().requestedExperienceID ==
            .airAndSpace)
        session.controllerForegroundPresenceDidChange(false)

        await session.applyExperienceCoordinatorAction(transition)

        let reconciled = await session.experienceCoordinator.currentState()
        #expect(reconciled.requestedExperienceID == nil)
        #expect(reconciled.prewarmingExperienceID == nil)
    }

    @Test(arguments: [
        ProjectionPreferenceChange.aircraftSource,
        ProjectionPreferenceChange.observerLocation,
    ])
    func contextInvalidationWhileRuntimePreparationSuspendsRejectsThePreparedOutput(
        _ change: ProjectionPreferenceChange,
    ) async throws {
        let clock = SuspendingProjectionRotationClock(
            now: Date(timeIntervalSince1970: 1_800_000_000),
        )
        let session = ThrowSession.fixture(rotationClock: clock)
        session.airAndSpacePreferences = session.airAndSpacePreferences.replacingGeography(
            .defaultValue.replacingIsEnabled(false),
        )
        var actions = await session.experienceCoordinator.actions().makeAsyncIterator()
        try await configureAirAndSpaceRequestFromTransit(on: session)
        _ = try #require(await actions.next())
        await session.experienceCoordinator.select(.airAndSpace)
        let activation = try #require(await actions.next())
        guard case let .activate(lease, _) = activation else {
            Issue.record("Expected the Air & Space activation")
            return
        }
        let activated = session.airAndSpaceActivation.activate(lease)
        #expect(activated)
        let coordinator = await session.experienceCoordinator.currentState()
        session.projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: session.dateProvider.now(),
        )
        let semanticFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let update = AirAndSpaceRuntimeUpdate(
            activationLease: lease,
            successfulActivationLease: lease,
            health: .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 1,
            ),
            flightsFrame: semanticFrame.flights,
            snapshot: nil,
            physicalPolling: .stopped,
            semanticPreparationState: .ready,
        )
        await clock.suspendNextNowCall()

        let preparation = Task { await session.applyAirAndSpaceUpdate(update) }
        await clock.waitForNowCallToSuspend()
        let previousGeneration = session.projectionContextGeneration

        let invalidation = session.prepareProjectionPreferencePublication(change)

        #expect(invalidation.contextGeneration == previousGeneration.successor())
        #expect(session.projectionContextGeneration == invalidation.contextGeneration)
        #expect(session.projectionPresentationStaging?.targetLease == nil)
        await clock.resumeSuspendedNowCall()
        await preparation.value

        let staleTransition = try #require(await actions.next())
        guard case let .beginTransition(_, targetLease) = staleTransition else {
            Issue.record("Expected the stale prepared transition")
            return
        }
        #expect(targetLease == lease)
        await session.applyExperienceCoordinatorAction(staleTransition)
        #expect(session.projectionPresentationStaging?.targetLease == nil)
        #expect(session.visibleProjection.experienceID == .transit)

        _ = await session.finishProjectionPreferenceInvalidation(invalidation)
        session.completeProjectionPreferenceInvalidation(invalidation)
    }

    @Test(arguments: [
        ProjectionPreferenceChange.aircraftSource,
        ProjectionPreferenceChange.observerLocation,
    ])
    func contextInvalidationDuringFadeRevokesTheBlackCommit(
        _ change: ProjectionPreferenceChange,
    ) async throws {
        let session = ThrowSession.fixture()
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 9),
        )
        let activated = session.airAndSpaceActivation.activate(lease)
        #expect(activated)
        session.projectionPresentationState = .initial(
            coordinator: projectionTestCoordinator(activeExperienceID: .transit),
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: session.dateProvider.now(),
        )
        let prepared = try preparedAirAndSpaceProjection(for: session, lease: lease)
        session.projectionPresentationStaging = .prepared(prepared)
        let fadeGate = ProjectionTransitionGate()
        session.waitForProjectionFadeOutForTesting = {
            await fadeGate.suspend()
        }

        let transition = Task {
            await session.applyExperienceCoordinatorAction(.beginTransition(
                from: .transit,
                to: lease,
            ))
        }
        await fadeGate.waitForSuspension()
        #expect(session.projectionSurfaceOpacity == 0)
        let previousGeneration = session.projectionContextGeneration

        let invalidation = session.prepareProjectionPreferencePublication(change)

        #expect(invalidation.contextGeneration == previousGeneration.successor())
        #expect(session.projectionPresentationStaging?.targetLease == nil)
        #expect(session.projectionSurfaceOpacity == 1)
        await fadeGate.resume()
        await transition.value
        #expect(session.projectionPresentationStaging?.targetLease == nil)
        #expect(session.activeExperienceID == .transit)
        #expect(session.visibleProjection.experienceID == .transit)

        session.waitForProjectionFadeOutForTesting = nil
        _ = await session.finishProjectionPreferenceInvalidation(invalidation)
        session.completeProjectionPreferenceInvalidation(invalidation)
    }

    @Test func oneConfiguredViewKeepsAutomaticRotationDormant() {
        let session = ThrowSession.fixture()

        session.setAutomaticExperienceRotationEnabled(true)

        #expect(session.projectionPlaylist.automaticRotationEnabled)
        #expect(session.projectionPlaylist.rotatesAutomatically == false)
        #expect(session.experienceRotationHasControls == false)
    }

    @Test func dwellChangesStayWithinTheValidatedPlaylist() {
        let session = ThrowSession.fixture()

        session.setExperienceDwellDuration(seconds: 300, for: .airAndSpace)

        #expect(session.projectionPlaylist.entry(for: .airAndSpace)?.dwellDuration.seconds == 300)
    }

    @Test func rapidPlaylistChangesConvergeOnTheNewestCoordinatorValue() async {
        let session = ThrowSession.fixture()

        session.setExperienceDwellDuration(seconds: 300, for: .airAndSpace)
        let olderTask = session.playlistConfigurationTask
        session.setExperienceDwellDuration(seconds: 600, for: .airAndSpace)
        let latestTask = session.playlistConfigurationTask
        await latestTask?.value
        await olderTask?.value

        let coordinatorPlaylist = await session.experienceCoordinator.currentPlaylist()
        #expect(coordinatorPlaylist.entry(for: .airAndSpace)?.dwellDuration.seconds == 600)
        #expect(session.projectionPlaylist == coordinatorPlaylist)
    }

    @Test func staleDeactivationCannotReleaseANewerSessionLease() async {
        let session = ThrowSession.fixture()
        session.isReconcilingDemand = true
        let oldLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let replacementLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 2),
        )

        await session.applyExperienceCoordinatorAction(.activate(
            lease: oldLease,
            role: .active,
        ))
        await session.applyExperienceCoordinatorAction(.activate(
            lease: replacementLease,
            role: .active,
        ))
        await session.applyExperienceCoordinatorAction(.deactivate(lease: oldLease))

        #expect(session.airAndSpaceActivation.activeLease == replacementLease)
    }

    @Test func delayedEqualDeactivationStillStopsRuntimeAfterDirectNilSync() async throws {
        let session = ThrowSession.fixture()
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let activated = session.airAndSpaceActivation.activate(lease)
        #expect(activated)
        let activation = try await session.airAndSpaceRuntime.activate(
            configuration: .adsbLol,
            query: session.aircraftQuery(),
            labelMode: session.labelMode,
            lease: lease,
            demandGeneration: session.demandGeneration,
        )
        guard case .accepted = activation else {
            Issue.record("The physical runtime must accept the coordinator lease")
            return
        }

        session.airAndSpaceActivation.synchronize(with: nil)
        #expect(session.airAndSpaceActivation.activeLease == nil)
        #expect(await session.airAndSpaceRuntime.currentUpdate().activationLease == lease)

        await session.applyExperienceCoordinatorAction(.deactivate(lease: lease))

        let runtime = await session.airAndSpaceRuntime.currentUpdate()
        #expect(runtime.activationLease == nil)
        #expect(runtime.activePollingSignature == nil)
        #expect(await session.airAndSpaceRuntime.activePollingActivationForTesting() == nil)
    }

    @Test func stoppedCoordinatorLeaseCannotReappearAfterItsDeactivationAction() async throws {
        let session = ThrowSession.fixture()
        session.isReconcilingDemand = true
        var actions = await session.experienceCoordinator.actions().makeAsyncIterator()
        let projectingDemand = ProjectionExperienceDemand(
            hasOutput: true,
            isForeground: true,
            isQuiet: false,
            isCalibrating: false,
        )
        let quietDemand = ProjectionExperienceDemand(
            hasOutput: true,
            isForeground: true,
            isQuiet: true,
            isCalibrating: false,
        )
        session.outputDemands.insert(.preview(.init(rawValue: "lease-race-preview")))

        await session.experienceCoordinator.reconcile(demand: projectingDemand)
        let activation = try #require(await actions.next())
        guard case let .activate(lease, _) = activation else {
            Issue.record("Projection demand must activate the current View")
            return
        }
        await session.applyExperienceCoordinatorAction(activation)
        #expect(session.airAndSpaceActivation.activeLease == lease)

        await session.experienceCoordinator.reconcile(demand: quietDemand)
        let deactivation = try #require(await actions.next())
        #expect(deactivation == .deactivate(lease: lease))
        await session.applyExperienceCoordinatorAction(deactivation)
        #expect(session.airAndSpaceActivation.activeLease == nil)

        // Hold the action before the direct lease read that follows demand reconciliation.
        await session.reconcileExperienceDemand(isQuiet: true)

        #expect(await session.experienceCoordinator.activationLease(for: .airAndSpace) == nil)
        #expect(await session.experienceCoordinator.runningExperienceIDsForTesting().isEmpty)
        #expect(session.airAndSpaceActivation.activeLease == nil)
    }

    @Test func runtimeUpdateWaitsForThePreparedFrameToFinishFadingIn() async throws {
        let session = ThrowSession.fixture()
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        _ = session.airAndSpaceActivation.activate(lease)
        session.replacePendingAirAndSpaceFrameForTesting(.empty)
        session.currentSnapshot = nil
        let observer = try #require(session.confirmedLocation?.position)
        let semanticFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let output = try projectionTestAirOutput(
            semanticFrame: semanticFrame,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 150),
            revision: 1,
            observerPoint: ProjectionPoint(x: 0.5, y: 0.5),
        )
        let prepared = try #require(PreparedProjectionPresentation.rendered(
            contextGeneration: session.projectionContextGeneration,
            activationLease: lease,
            output: output,
        ))
        session.projectionPresentationStaging = .fadingIn(
            prepared: prepared,
            bufferedTargetUpdate: nil,
        )
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: session.dateProvider.now(),
            observations: [],
            decodingDiagnostics: .none,
        )
        let update = AirAndSpaceRuntimeUpdate(
            activationLease: lease,
            successfulActivationLease: lease,
            health: .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 1,
            ),
            flightsFrame: nil,
            snapshot: snapshot,
            physicalPolling: .stopped,
            semanticPreparationState: .ready,
        )

        await session.applyAirAndSpaceUpdate(update)

        #expect(session.currentSnapshot == nil)
        let bufferedSnapshot = session.projectionPresentationStaging?
            .bufferedTargetUpdate?.snapshot
        #expect(bufferedSnapshot == snapshot)

        await session.finishProjectionPresentationTransition(to: lease)

        #expect(session.currentSnapshot == snapshot)
        #expect(session.projectionPresentationStaging?.targetLease == nil)
    }

    @Test func projectionAccessibilityUsesTheActiveExperienceCountMeaning() {
        let session = ThrowSession.fixture()
        let coordinator = ProjectionExperienceCoordinatorState(
            activeExperienceID: .transit,
            requestedExperienceID: nil,
            prewarmingExperienceID: nil,
            isPaused: false,
            dwellEndsAt: nil,
            nextExperienceID: .airAndSpace,
            healthByExperience: [
                .transit: .healthy(
                    lastUpdate: session.dateProvider.now(),
                    visibleContentCount: 7,
                ),
            ],
            manualSelectionFailure: nil,
        )
        session.projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: session.dateProvider.now(),
        )

        #expect(session.projectionAccessibilitySummary.contains("Transit"))
        #expect(session.projectionAccessibilitySummary.contains("7 Vehicles visible"))
        #expect(session.projectionAccessibilitySummary.contains("Aircraft visible") == false)
    }

    private func configureAirAndSpaceRequestFromTransit(
        on session: ThrowSession,
    ) async throws {
        let transitOnly = try projectionPlaylist(entries: [.transit])
        let both = try projectionPlaylist(entries: [.transit, .airAndSpace])
        await session.experienceCoordinator.configure(ProjectionPlaylistConfiguration(
            playlist: transitOnly,
            revision: .init(rawValue: 1),
        ))
        await session.experienceCoordinator.configure(ProjectionPlaylistConfiguration(
            playlist: both,
            revision: .init(rawValue: 2),
        ))
        await session.experienceCoordinator.reconcile(demand: ProjectionExperienceDemand(
            hasOutput: true,
            isForeground: true,
            isQuiet: false,
            isCalibrating: false,
        ))
    }

    private func projectionPlaylist(
        entries: [ProjectionExperienceID],
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
            entries: entries.map {
                ProjectionPlaylistEntry(
                    experienceID: $0,
                    dwellDuration: .defaultValue,
                )
            },
            automaticRotationEnabled: false,
            selectedExperienceID: entries.first,
            configuredExperienceIDs: Set(entries),
            catalog: catalog,
        )
    }

    private func preparedAirAndSpaceProjection(
        for session: ThrowSession,
        lease: ProjectionActivationLease,
    ) throws -> PreparedProjectionPresentation {
        let observer = try #require(session.confirmedLocation?.position)
        let semanticFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let output = try projectionTestAirOutput(
            semanticFrame: semanticFrame,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 150),
            revision: 1,
            observerPoint: ProjectionPoint(x: 0.5, y: 0.5),
        )
        return try #require(PreparedProjectionPresentation.rendered(
            contextGeneration: session.projectionContextGeneration,
            activationLease: lease,
            output: output,
        ))
    }
}

private actor ProjectionTransitionGate {
    private var suspension: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            precondition(suspension == nil, "Only one fade can suspend at a time")
            suspension = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitForSuspension() async {
        guard suspension == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        guard let suspension else {
            Issue.record("Expected a suspended projection fade")
            return
        }
        self.suspension = nil
        suspension.resume()
    }
}

private actor SuspendingProjectionRotationClock: ProjectionRotationClock {
    private let current: Date
    private var suspendsNextNowCall = false
    private var suspendedNowCall: CheckedContinuation<Date, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(now: Date) {
        current = now
    }

    func now() async -> Date {
        guard suspendsNextNowCall else { return current }
        suspendsNextNowCall = false
        return await withCheckedContinuation { continuation in
            precondition(suspendedNowCall == nil, "Only one clock read can suspend at a time")
            suspendedNowCall = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    func suspendNextNowCall() {
        precondition(suspendedNowCall == nil, "A clock read is already suspended")
        suspendsNextNowCall = true
    }

    func waitForNowCallToSuspend() async {
        guard suspendedNowCall == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedNowCall() {
        guard let suspendedNowCall else {
            Issue.record("Expected a suspended projection clock read")
            return
        }
        self.suspendedNowCall = nil
        suspendedNowCall.resume(returning: current)
    }
}
