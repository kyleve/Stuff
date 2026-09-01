import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionAircraftTests {
    @Test func rendererKeepsTheLastCompletePublicationWhileANewerRequestSuspends() async throws {
        let preferences = ThrowPreferences.defaultValue.airAndSpace.replacingGeography(
            .defaultValue.replacingIsEnabled(false),
        )
        let session = ThrowSession.fixture(airAndSpacePreferences: preferences)
        let firstObserver = try #require(session.confirmedLocation?.position)
        let secondObserver = try projectionTestObserver(latitude: 38, longitude: -121)
        let secondLocation = try ConfirmedObserverLocation(
            position: secondObserver,
            horizontalAccuracyMeters: 10,
            confirmedAt: session.dateProvider.now(),
        )
        let firstFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let secondFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 200),
        )
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        _ = session.airAndSpaceActivation.activate(lease)
        session.outputDemands.insert(.preview(ProjectionOutputID(rawValue: "atomic-render")))
        session.replacePendingAirAndSpaceFrameForTesting(firstFrame)
        let gate = ProjectionPublicationGate()
        session.beforePublishingProjectionForTesting = {
            await gate.suspendPublication()
        }

        session.restartRenderer()
        await gate.waitForSuspensionCount(1)
        await gate.releaseNext()
        await gate.waitForSuspensionCount(2)

        let firstPublication = session.visibleProjection
        #expect(firstPublication.semanticFrame == .airAndSpace(firstFrame))
        #expect(firstPublication.request?.context.observer == firstObserver)
        #expect(firstPublication.frame.generatedAt == firstPublication.request?.generatedAt)
        #expect(session.projectionFrame == firstPublication.frame)
        #expect(session.observerMapPoint == firstPublication.observerPoint)

        session.replaceConfirmedLocationForTesting(secondLocation)
        session.replacePendingAirAndSpaceFrameForTesting(secondFrame)
        session.restartRenderer()
        await gate.waitForSuspensionCount(3)

        #expect(session.visibleProjection == firstPublication)
        #expect(session.pendingAirAndSpaceFrame == secondFrame)
        #expect(session.confirmedLocation?.position == secondObserver)
        #expect(session.projectionFrame == firstPublication.frame)
        #expect(session.observerMapPoint == firstPublication.observerPoint)

        await gate.releaseAll()
        await gate.waitForSuspensionCount(4)

        let secondPublication = session.visibleProjection
        #expect(secondPublication.semanticFrame == .airAndSpace(secondFrame))
        #expect(secondPublication.request?.context.observer == secondObserver)
        #expect(secondPublication.request?.revision != firstPublication.request?.revision)
        #expect(secondPublication.frame.generatedAt == secondPublication.request?.generatedAt)
        #expect(session.projectionFrame == secondPublication.frame)
        #expect(session.observerMapPoint == secondPublication.observerPoint)

        session.stopRenderer()
        session.beforePublishingProjectionForTesting = nil
        await gate.releaseAll()
    }

    @Test func sourceInvalidationRejectsAPendingRenderAndRepeatedLease() async throws {
        let preferences = ThrowPreferences.defaultValue.airAndSpace.replacingGeography(
            .defaultValue.replacingIsEnabled(false),
        )
        let session = ThrowSession.fixture(airAndSpacePreferences: preferences)
        let semanticFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        session.outputDemands.insert(.preview(ProjectionOutputID(rawValue: "source-invalidation")))
        await session.reconcileExperienceDemand(isQuiet: false)
        let lease = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        #expect(session.airAndSpaceActivation.activeLease == lease)
        session.replacePendingAirAndSpaceFrameForTesting(semanticFrame)
        let publicationGate = ProjectionPublicationGate()
        let deactivationGate = ProjectionPublicationGate()
        session.beforePublishingProjectionForTesting = {
            await publicationGate.suspendPublication()
        }
        session.beforeProjectionPreferenceRuntimeDeactivationForTesting = {
            await deactivationGate.suspendPublication()
        }

        session.restartRenderer()
        let staleRenderTask = try #require(session.renderTask)
        await publicationGate.waitForSuspensionCount(1)

        let sourceChange = Task {
            await session.useSource(ValidatedAircraftSourceDraft(source: .adsbLol))
        }
        await deactivationGate.waitForSuspensionCount(1)

        #expect(session.airAndSpaceActivation.activeLease == nil)
        await session.applyExperienceCoordinatorAction(.activate(lease: lease, role: .active))
        #expect(session.airAndSpaceActivation.activeLease == nil)
        session.restartRenderer()
        #expect(session.renderTask == nil)

        await publicationGate.releaseAll()
        await staleRenderTask.value
        #expect(session.visibleProjection.request == nil)
        #expect(session.visibleProjection.semanticFrame == .airAndSpace(.empty))

        session.beforePublishingProjectionForTesting = nil
        session.outputDemands.removeAll()
        await deactivationGate.releaseAll()
        #expect(await sourceChange.value)
        await session.demandTask?.value
        session.stopRenderer()
        session.beforeProjectionPreferenceRuntimeDeactivationForTesting = nil
    }

    @Test func samePermitSourceReconfigurationRenewsLeaseAndPhysicalPoller() async throws {
        let preferences = ThrowPreferences.defaultValue.airAndSpace.replacingGeography(
            .defaultValue.replacingIsEnabled(false),
        )
        let session = ThrowSession.fixture(airAndSpacePreferences: preferences)
        session.outputDemands.insert(.preview(.init(rawValue: "source-reconfiguration")))
        session.projectionSessionLocationGate = .ready
        await session.reconcileExperienceDemand(isQuiet: false)
        let originalLease = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        #expect(session.airAndSpaceActivation.activeLease == originalLease)
        let originalActivation = try await session.airAndSpaceRuntime.activate(
            configuration: .adsbLol,
            query: session.aircraftQuery(),
            labelMode: session.labelMode,
            lease: originalLease,
        )
        guard case let .accepted(originalUpdate) = originalActivation else {
            Issue.record("The original coordinator lease must start its physical poller")
            return
        }
        let originalPollingActivation = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )
        #expect(originalUpdate.activationLease == originalLease)
        #expect(originalUpdate.activePollingSignature?.configuration == .adsbLol)

        let replacementURL = try #require(
            URL(string: "http://readsb.local/tar1090/data/aircraft.json"),
        )
        let replacementConfiguration = try AircraftSourceConfiguration.readsb(
            ReadsbConfiguration(aircraftJSONURL: replacementURL),
        )
        let invalidation = session.prepareProjectionPreferencePublication(.aircraftSource)
        #expect(session.airAndSpaceActivation.activeLease == nil)
        let renewal = try #require(
            await session.finishProjectionPreferenceInvalidation(invalidation),
        )
        guard case let .replaced(from, replacementLease) = renewal else {
            Issue.record("The active View must receive a replacement coordinator lease")
            return
        }
        #expect(from == originalLease)
        #expect(replacementLease.generation > originalLease.generation)
        #expect(await session.airAndSpaceRuntime.currentUpdate().activationLease == nil)

        session.replaceSourceSelectionForTesting(.configured(replacementConfiguration))
        await session.configureExperienceCoordinator(with: session.projectionPlaylist)
        #expect(session.airAndSpaceActivation.activeLease == replacementLease)
        session.completeProjectionPreferenceInvalidation(invalidation)

        // The direct coordinator read can overtake these queued commands.
        await session.applyExperienceCoordinatorAction(.deactivate(lease: originalLease))
        await session.applyExperienceCoordinatorAction(.activate(
            lease: originalLease,
            role: .active,
        ))
        #expect(session.airAndSpaceActivation.activeLease == replacementLease)
        let authoritativeReplacement = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        #expect(authoritativeReplacement == replacementLease)
        #expect(session.outputDemands.isEmpty == false)
        #expect(session.hasForegroundControllerSceneForTesting)
        #expect(session.isQuietNow == false)
        #expect(session.isCalibrating == false)
        await session.reconcileExperienceDemand(isQuiet: session.isQuietNow)
        #expect(session.airAndSpaceActivation.activeLease == replacementLease)

        await session.reconcileDemand(generation: session.demandGeneration)
        let replacementUpdate = await session.airAndSpaceRuntime.currentUpdate()
        let replacementPollingActivation = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                replacementLease,
        )
        #expect(replacementUpdate.activationLease == replacementLease)
        #expect(replacementUpdate.activePollingSignature?.configuration == replacementConfiguration)
        #expect(replacementPollingActivation != originalPollingActivation)

        await session.applyExperienceCoordinatorAction(.deactivate(lease: originalLease))
        #expect(await session.airAndSpaceRuntime.currentUpdate()
            .activationLease == replacementLease)
        #expect(
            await session.airAndSpaceRuntime.activePollingActivationForTesting() ==
                replacementPollingActivation,
        )

        session.stopRenderer()
        await session.airAndSpaceRuntime.deactivate(
            lease: replacementLease,
            reporting: .idle,
        )
    }

    @Test func staleRuntimeUpdateCannotReplaceTheCurrentActivationState() async {
        let session = ThrowSession.fixture()
        let currentLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 2),
        )
        _ = session.airAndSpaceActivation.activate(currentLease)
        let previousHealth = session.feedHealth

        await session.applyAirAndSpaceUpdate(AirAndSpaceRuntimeUpdate(
            activationLease: ProjectionActivationLease(
                experienceID: .airAndSpace,
                generation: .init(rawValue: 1),
            ),
            successfulActivationLease: ProjectionActivationLease(
                experienceID: .airAndSpace,
                generation: .init(rawValue: 1),
            ),
            health: .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 99,
            ),
            flightsFrame: nil,
            snapshot: nil,
            activePollingSignature: nil,
            semanticPreparationState: .ready,
        ))

        #expect(session.airAndSpaceActivation.activeLease == currentLease)
        #expect(session.feedHealth == previousHealth)
    }

    @Test func failedSourcePersistenceKeepsTheOldSourceAndCredentialLive() async throws {
        let preferenceStore = FailableThrowPreferenceStore(failsSave: true)
        let credentialStore = FailableAircraftCredentialStore(credentials: [:])
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: credentialStore,
        )
        let previousHealth = session.feedHealth
        let query = try session.aircraftQuery()
        let activationLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        _ = session.airAndSpaceActivation.activate(activationLease)
        _ = await session.airAndSpaceRuntime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: session.labelMode,
            lease: activationLease,
        )
        session.publishPostLaunchFailure(.flightradar24Credential)
        let replacement = try AircraftCredential(secret: "fr24-replacement-1234")

        let applied = await session.useSource(ValidatedAircraftSourceDraft(
            source: .flightradar24(
                Flightradar24Configuration(pollingInterval: .defaultValue),
                replacementCredential: replacement,
            ),
        ))

        #expect(applied == false)
        #expect(session.sourceChoice == .adsbLol)
        #expect(
            await session.airAndSpaceRuntime.currentUpdate().activePollingSignature?
                .configuration == .adsbLol,
        )
        #expect(session.feedHealth == previousHealth)
        #expect(session.flightradar24CredentialState == .missing)
        #expect(await credentialStore.credential(for: .flightradar24) == nil)
        #expect(
            session.postLaunchFailureLedger.failure(for: .flightradar24Credential) ==
                .flightradar24Credential,
        )
        #expect(await session.airAndSpaceRuntime.activeSourceKindForTesting() == .adsbLol)
        await session.airAndSpaceRuntime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func sourceCommitRepersistsConcurrentTypedPreferences() async throws {
        let preferenceStore = ControlledThrowPreferenceStore(saveBehavior: .suspended)
        let credentialStore = MemoryAircraftCredentialStore(credentials: [:])
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: credentialStore,
        )
        let replacement = try AircraftCredential(secret: "fr24-replacement-1234")
        let apply = Task {
            await session.useSource(ValidatedAircraftSourceDraft(
                source: .flightradar24(
                    Flightradar24Configuration(pollingInterval: .defaultValue),
                    replacementCredential: replacement,
                ),
            ))
        }
        await preferenceStore.waitForSaveToStart()

        session.updateProjectionMode(.trueSky)
        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        session.setExperienceDwellDuration(seconds: 180, for: .airAndSpace)

        await preferenceStore.resumeSave()
        #expect(await apply.value)

        let persisted = await preferenceStore.persistedPreferences()
        #expect(session.sourceChoice == .flightradar24)
        #expect(session.projectionMode == .trueSky)
        #expect(session.intensityPercent == 70)
        #expect(
            session.projectionPlaylist.entry(for: .airAndSpace)?.dwellDuration.seconds == 180,
        )
        #expect(ThrowPreferenceSnapshot(persisted) == session.preferenceSnapshot)
        #expect(await credentialStore.credential(for: .flightradar24) == replacement)
        #expect(session.flightradar24CredentialState == .saved(lastFour: "1234"))
        #expect(await preferenceStore.successfulSaves().count == 2)
    }

    @Test(arguments: ReconciledPreferenceRetryInterruption.allCases)
    func committedSourceSurvivesRetryInterruption(
        _ interruption: ReconciledPreferenceRetryInterruption,
    ) async throws {
        let preferenceStore = ControlledThrowPreferenceStore(
            saveBehavior: .scripted(interruption.saveSteps),
        )
        let credentialStore = MemoryAircraftCredentialStore(credentials: [:])
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: credentialStore,
        )
        let replacement = try AircraftCredential(secret: "fr24-replacement-1234")
        let apply = Task {
            await session.useSource(ValidatedAircraftSourceDraft(
                source: .flightradar24(
                    Flightradar24Configuration(pollingInterval: .defaultValue),
                    replacementCredential: replacement,
                ),
            ))
        }
        await preferenceStore.waitForSaveToStart()

        session.updateProjectionMode(.trueSky)
        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        session.setExperienceDwellDuration(seconds: 180, for: .airAndSpace)

        await preferenceStore.resumeSave()
        #expect(await apply.value)
        await session.flushPreferencesSave()

        let persisted = await preferenceStore.persistedPreferences()
        #expect(session.sourceChoice == .flightradar24)
        #expect(session.projectionMode == .trueSky)
        #expect(session.intensityPercent == 70)
        #expect(
            session.projectionPlaylist.entry(for: .airAndSpace)?.dwellDuration.seconds == 180,
        )
        #expect(persisted.setupState == session.setupState)
        #expect(persisted.global == session.globalPreferences)
        #expect(persisted.playlist == session.projectionPlaylist)
        #expect(await credentialStore.credential(for: .flightradar24) == replacement)
        #expect(await preferenceStore.successfulSaves().count == 2)
        #expect(await preferenceStore.saveAttemptCount() == 3)
        #expect(session.postLaunchFailureLedger.failure(for: .aircraftSource) == nil)
        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) == nil)
    }

    @Test func failedCredentialDeletionKeepsTheActiveSourceRunning() async throws {
        let credential = try AircraftCredential(secret: "fr24-existing-1234")
        let credentialStore = FailableAircraftCredentialStore(
            credentials: [.flightradar24: credential],
            failsDelete: true,
        )
        let session = ThrowSession.fixture(
            preferenceStore: FailableThrowPreferenceStore(failsSave: false),
            credentialStore: credentialStore,
        )
        let configuration = AircraftSourceConfiguration.flightradar24(
            Flightradar24Configuration(
                pollingInterval: .defaultValue,
            ),
        )
        session.replaceSourceSelectionForTesting(.configured(configuration))
        session.flightradar24CredentialState = .saved(lastFour: "1234")
        let activationLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let activated = session.airAndSpaceActivation.activate(activationLease)
        #expect(activated)
        _ = try await session.airAndSpaceRuntime.activate(
            configuration: configuration,
            query: session.aircraftQuery(),
            labelMode: session.labelMode,
            lease: activationLease,
        )
        let previousHealth = session.feedHealth

        let deleted = await session.deleteFlightradar24Credential()

        #expect(deleted == false)
        #expect(session.sourceChoice == .flightradar24)
        let runtime = await session.airAndSpaceRuntime.currentUpdate()
        #expect(runtime.activationLease == activationLease)
        #expect(runtime.activePollingSignature?.configuration == configuration)
        #expect(session.feedHealth == previousHealth)
        #expect(session.flightradar24CredentialState == .saved(lastFour: "1234"))
        #expect(await credentialStore.credential(for: .flightradar24) == credential)
        await session.airAndSpaceRuntime.deactivate(lease: activationLease, reporting: .idle)
    }
}

private actor ProjectionPublicationGate {
    private struct CountWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var suspensionCount = 0
    private var suspendedPublications: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [CountWaiter] = []

    func suspendPublication() async {
        suspensionCount += 1
        resumeCountWaiters()
        await withCheckedContinuation { continuation in
            suspendedPublications.append(continuation)
        }
    }

    func waitForSuspensionCount(_ count: Int) async {
        guard suspensionCount < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append(CountWaiter(count: count, continuation: continuation))
        }
    }

    func releaseNext() {
        guard suspendedPublications.isEmpty == false else { return }
        suspendedPublications.removeFirst().resume()
    }

    func releaseAll() {
        let publications = suspendedPublications
        suspendedPublications.removeAll()
        publications.forEach { $0.resume() }
    }

    private func resumeCountWaiters() {
        let ready = countWaiters.filter { $0.count <= suspensionCount }
        countWaiters.removeAll { $0.count <= suspensionCount }
        ready.forEach { $0.continuation.resume() }
    }
}

private enum SourceMutationStoreFailure: Error {
    case save
    case delete
}

private actor FailableThrowPreferenceStore: ThrowPreferenceStore {
    private let failsSave: Bool
    private var preferences = ThrowPreferences.defaultValue

    init(failsSave: Bool) {
        self.failsSave = failsSave
    }

    func load() -> ThrowPreferences {
        preferences
    }

    func save(_ preferences: ThrowPreferences) throws {
        if failsSave { throw SourceMutationStoreFailure.save }
        self.preferences = preferences
    }
}

private actor FailableAircraftCredentialStore: AircraftCredentialStore {
    private var credentials: [AircraftCredentialID: AircraftCredential]
    private let failsDelete: Bool

    init(
        credentials: [AircraftCredentialID: AircraftCredential],
        failsDelete: Bool = false,
    ) {
        self.credentials = credentials
        self.failsDelete = failsDelete
    }

    func state(for id: AircraftCredentialID) -> CredentialState {
        guard let credential = credentials[id] else { return .missing }
        return .saved(lastFour: credential.lastFour)
    }

    func credential(for id: AircraftCredentialID) -> AircraftCredential? {
        credentials[id]
    }

    func save(_ credential: AircraftCredential, for id: AircraftCredentialID) {
        credentials[id] = credential
    }

    func delete(_ id: AircraftCredentialID) throws {
        if failsDelete { throw SourceMutationStoreFailure.delete }
        credentials[id] = nil
    }
}
