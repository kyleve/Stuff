import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionTests {
    @Test func preferenceLoadFailureIsTypedAndPreservesTheSeedSetup() async throws {
        let storedPreferences = try ThrowSession.fixture().makePreferences()
        let preferenceStore = ThrowSessionLaunchPreferenceStore(
            result: .failure,
            suspendsLoad: false,
        )
        let session = ThrowSession.launchFixture(
            setupCompleted: true,
            preferenceStore: preferenceStore,
            credentialStore: ThrowSessionLaunchCredentialStore(
                failingID: nil,
                states: [:],
            ),
        )
        let seedSetup = session.setupState

        await session.start()

        guard case .failed(.preferences) = session.launchState else {
            Issue.record("A preference error must fail launch at the preference boundary")
            return
        }
        #expect(
            String(localized: ThrowSessionLaunchFailure.preferences.userMessage) ==
                "Throw could not load its settings. Your settings were not changed. Try again.",
        )
        #expect(session.setupState == seedSetup)
        #expect(session.setupState == storedPreferences.setupState)
    }

    @Test func credentialAccessFailureDoesNotLookLikeAMissingCredential() async throws {
        let storedPreferences = try ThrowSession.fixture().makePreferences()
        let preferenceStore = ThrowSessionLaunchPreferenceStore(
            result: .value(storedPreferences),
            suspendsLoad: false,
        )
        let session = ThrowSession.launchFixture(
            setupCompleted: true,
            preferenceStore: preferenceStore,
            credentialStore: ThrowSessionLaunchCredentialStore(
                failingID: .rapidAPI,
                states: [:],
            ),
        )

        await session.start()

        guard case let .failed(.credential(id)) = session.launchState else {
            Issue.record("A credential access error must fail launch at the credential boundary")
            return
        }
        #expect(id == .rapidAPI)
        #expect(
            String(
                localized: ThrowSessionLaunchFailure.credential(id: id).userMessage,
            ) == "Throw could not access its saved aircraft-source credentials. Try again.",
        )
        #expect(session.rapidAPICredentialState == .missing)
    }

    @Test func configuredPreferencesAndMissingCredentialsProduceAReadySession() async throws {
        let storedPreferences = try ThrowSession.fixture().makePreferences()
        let preferenceStore = ThrowSessionLaunchPreferenceStore(
            result: .value(storedPreferences),
            suspendsLoad: false,
        )
        let session = ThrowSession.launchFixture(
            setupCompleted: true,
            preferenceStore: preferenceStore,
            credentialStore: ThrowSessionLaunchCredentialStore(
                failingID: nil,
                states: [:],
            ),
        )

        await session.start()

        guard case let .ready(setup) = session.launchState else {
            Issue.record("Configured preferences must produce a ready session")
            return
        }
        #expect(ThrowSetupState.configured(setup) == storedPreferences.setupState)
        #expect(session.rapidAPICredentialState == .missing)
        #expect(session.flightradar24CredentialState == .missing)
    }

    @Test func incompletePreferencesProduceAnOnboardingSession() async throws {
        let storedPreferences = try ThrowSession.onboardingFixture().makePreferences()
        let preferenceStore = ThrowSessionLaunchPreferenceStore(
            result: .value(storedPreferences),
            suspendsLoad: false,
        )
        let session = ThrowSession.launchFixture(
            setupCompleted: false,
            preferenceStore: preferenceStore,
            credentialStore: ThrowSessionLaunchCredentialStore(
                failingID: nil,
                states: [:],
            ),
        )

        await session.start()

        guard case let .onboarding(setup) = session.launchState else {
            Issue.record("Incomplete preferences must produce an onboarding session")
            return
        }
        #expect(ThrowSetupState.onboarding(setup) == storedPreferences.setupState)
    }

    @Test func cancelledLaunchWaiterDoesNotCancelTheSingleProcessLaunch() async throws {
        let storedPreferences = try ThrowSession.fixture().makePreferences()
        let preferenceStore = ThrowSessionLaunchPreferenceStore(
            result: .value(storedPreferences),
            suspendsLoad: true,
        )
        let session = ThrowSession.launchFixture(
            setupCompleted: true,
            preferenceStore: preferenceStore,
            credentialStore: ThrowSessionLaunchCredentialStore(
                failingID: nil,
                states: [:],
            ),
        )

        let firstWaiter = Task(name: "Throw first launch waiter") {
            await session.start()
        }
        await preferenceStore.waitForLoadToStart()
        let secondWaiter = Task(name: "Throw second launch waiter") {
            await session.start()
        }
        firstWaiter.cancel()
        session.startLaunch()

        let loadCountBeforeResume = await preferenceStore.loadCallCount
        #expect(loadCountBeforeResume == 1)
        await preferenceStore.resumeLoad()
        await secondWaiter.value
        await firstWaiter.value

        guard case .ready = session.launchState else {
            Issue.record("The process launch must survive cancellation of a scene waiter")
            return
        }
        let finalLoadCount = await preferenceStore.loadCallCount
        #expect(finalLoadCount == 1)
    }

    @Test func startKeepsAllRuntimeObserversAttached() async {
        let session = ThrowSession.fixture()

        await session.start()

        #expect(session.airAndSpaceUpdateTask?.isCancelled == false)
        #expect(session.experienceStateTask?.isCancelled == false)
        #expect(session.experienceActionTask?.isCancelled == false)
    }

    @Test func startAdoptsAStoredPlaylistAfterDefaultCoordinatorState() async {
        let session = ThrowSession.fixture()
        await session.configureExperienceCoordinator(with: ThrowPreferences.defaultValue.playlist)

        await session.start()

        let state = await session.experienceCoordinator.currentState()
        #expect(state.activeExperienceID == .airAndSpace)
        #expect(session.projectionPlaylist.selectedExperienceID == .airAndSpace)
    }

    @Test func independentControllerWindowsMaintainDemandUntilBothDisconnect() {
        let session = ThrowSession.fixture()
        let first = ControllerProjectionOutputs()
        let second = ControllerProjectionOutputs()

        session.projectionOutputConnected(.preview(first.preview))
        session.projectionOutputConnected(.preview(second.preview))
        #expect(session.projectionOutputCount == 2)

        session.projectionOutputDisconnected(.preview(first.preview))
        #expect(session.projectionOutputCount == 1)
        #expect(session.hasProjectionOutputDemand)

        session.projectionOutputDisconnected(.preview(second.preview))
        #expect(session.projectionOutputCount == 0)
        #expect(session.hasProjectionOutputDemand == false)
    }

    @Test func calibrationDemandIsSharedWithEveryProjectionSurface() {
        let session = ThrowSession.fixture()
        let outputs = ControllerProjectionOutputs()

        session.projectionOutputConnected(.externalDisplay(.init(rawValue: "external-one")))
        session.projectionOutputConnected(.calibration(outputs.calibration))
        #expect(session.isCalibrating)

        session.projectionOutputDisconnected(.calibration(outputs.calibration))
        #expect(session.isCalibrating == false)
        #expect(session.projectionOutputCount == 1)
    }

    @Test func retryingVisibleContentCountReflectsLastGoodProjection() {
        let now = Date(timeIntervalSince1970: 100)
        let health = FeedHealth.retrying(
            lastUpdate: now,
            nextRetry: now.addingTimeInterval(10),
            failure: .transport,
            visibleContentCount: 4,
        )

        #expect(health.visibleContentCount == 4)
    }

    @Test func geographyDefaultsPersistWithoutRestartingAircraftDemand() throws {
        let session = ThrowSession.fixture()
        let demandGeneration = session.demandGeneration

        #expect(session.geographyEnabled)
        #expect(session.geographyIntensityPercent == 8)

        let geography = try session.airAndSpacePreferences.geography
            .replacingIntensityPercent(12)
            .replacingIsEnabled(false)
        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingGeography(geography),
        )
        let preferences = try session.makePreferences()

        #expect(session.demandGeneration == demandGeneration)
        #expect(preferences.geography.isEnabled == false)
        #expect(preferences.geography.intensityPercent == 12)
    }

    @Test func configuredProjectionChangeUpdatesTheTypedSetup() throws {
        let session = ThrowSession.fixture()

        session.updateProjectionMode(.trueSky)

        let preferences = try session.makePreferences()
        #expect(preferences.setupCompleted)
        #expect(preferences.selectedProjectionMode == .trueSky)
    }

    @Test func disablingGeographyImmediatelyRemovesAPublishedStaticFrame() {
        let session = ThrowSession.fixture()

        #expect(session.projectionFrame.geography != nil)
        session.replacePendingAirAndSpaceFrameForTesting(.empty)
        let geography = session.airAndSpacePreferences.geography
            .replacingIsEnabled(false)
        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingGeography(geography),
        )

        #expect(session.projectionFrame.geography == nil)
        #expect(session.projectionFrame.marks.isEmpty == false)
        #expect(session.geographyLayerHealth == .idle)
    }

    @Test func clearingProjectionStateRemovesTheObserverMarkerForQuietBlack() async {
        let session = ThrowSession.fixture()
        session.replaceProjectionMetadataForTesting(
            observerPoint: ProjectionPoint(x: 0.5, y: 0.5),
            geographyHealth: session.geographyLayerHealth,
        )

        await session.clearProjectionState(restartsGeography: false)

        #expect(session.projectionFrame.layers.isEmpty)
        #expect(session.observerMapPoint == nil)
    }

    @Test func aircraftSourceDiscardPreservesIndependentGeography() async throws {
        let session = ThrowSession.fixture()
        let geography = try #require(session.projectionFrame.geography)
        session.updateReduceMotion(true)

        try await session.discardOldFrame()

        #expect(session.projectionFrame.geography == geography)
        #expect(session.projectionFrame.marks.isEmpty)
    }

    @Test func invalidAircraftSourceKeepsIndependentGeographyRendering() async {
        let session = ThrowSession.fixture()
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "invalid-source-test"),
        )
        session.replaceLocationModeForTesting(.manual)
        session.replaceSourceSelectionForTesting(.awaitingValidation(.adsbLol))
        session.outputDemands.insert(output)
        session.demandGeneration = session.demandGeneration.successor()

        await session.reconcileDemand(generation: session.demandGeneration)
        let renderTask = session.renderTask
        await renderTask?.value

        #expect(session.projectionFrame.marks.isEmpty)
        #expect(session.projectionFrame.geography != nil)
        #expect(session.currentSnapshot == nil)
        #expect(session.pendingAirAndSpaceFrame.flights == nil)
        #expect(session.renderTask == nil)
        #expect(session.feedHealth == .failed(.sourceNotValidated))
    }

    @Test func geographyKeepsItsLeaseWhilePhysicalPollingStopsAndResumes() async throws {
        let session = ThrowSession.fixture()
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "geography-only-test"),
        )
        session.replaceLocationModeForTesting(.manual)
        session.outputDemands.insert(output)
        session.demandGeneration = session.demandGeneration.successor()

        await session.reconcileDemand(generation: session.demandGeneration)
        let renderTask = session.renderTask
        await renderTask?.value

        let experienceLease = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        let firstToken = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )
        let firstPhysicalLease = try #require(
            await session.airAndSpaceRuntime.currentUpdate().physicalPollingLease,
        )
        #expect(
            await session.airAndSpaceRuntime.currentUpdate().activationLease == experienceLease,
        )

        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingFlightsEnabled(false),
        )
        let stopTask = try #require(session.demandTask)
        await stopTask.value

        let stopped = await session.airAndSpaceRuntime.currentUpdate()
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                experienceLease,
        )
        #expect(stopped.activationLease == experienceLease)
        #expect(stopped.activePollingSignature == nil)
        #expect(stopped.snapshot == nil)
        #expect(stopped.flightsFrame == nil)
        #expect(stopped.physicalPollingLease == nil)
        #expect(await session.airAndSpaceRuntime.activePollingActivationForTesting() == nil)
        #expect(session.feedHealth == .idle)
        #expect(session.projectionFrame.geography != nil)

        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingFlightsEnabled(true),
        )
        let resumeTask = try #require(session.demandTask)
        await resumeTask.value

        let resumed = await session.airAndSpaceRuntime.currentUpdate()
        let resumedToken = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                experienceLease,
        )
        #expect(resumed.activationLease == experienceLease)
        #expect(resumed.activePollingSignature != nil)
        #expect(resumed.physicalPollingLease != firstPhysicalLease)
        #expect(resumedToken != firstToken)

        session.outputDemands.remove(output)
        session.scheduleDemandReconciliation()
        await session.demandTask?.value
        #expect(await session.experienceCoordinator.activationLease(for: .airAndSpace) == nil)
        #expect(await session.airAndSpaceRuntime.currentUpdate().activationLease == nil)
    }

    @Test func disablingEveryLayerSuspendsWithoutRetiringTheCoordinatorLease() async throws {
        let session = ThrowSession.fixture()
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "all-layers-disabled-test"),
        )
        session.replaceLocationModeForTesting(.manual)
        session.outputDemands.insert(output)
        session.demandGeneration = session.demandGeneration.successor()
        await session.reconcileDemand(generation: session.demandGeneration)

        let experienceLease = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        let firstToken = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )

        let disabledGeography = GeographyPreferences.defaultValue.replacingIsEnabled(false)
        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences
                .replacingFlightsEnabled(false)
                .replacingGeography(disabledGeography),
        )
        let stopTask = try #require(session.demandTask)
        await stopTask.value

        let stopped = await session.airAndSpaceRuntime.currentUpdate()
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                experienceLease,
        )
        #expect(stopped.activationLease == experienceLease)
        #expect(stopped.physicalPolling == .stopped)
        #expect(await session.airAndSpaceRuntime.currentPollingUpdateForTesting() == .inactive)

        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingFlightsEnabled(true),
        )
        let resumeTask = try #require(session.demandTask)
        await resumeTask.value

        let resumed = await session.airAndSpaceRuntime.currentUpdate()
        let resumedToken = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                experienceLease,
        )
        #expect(resumed.activationLease == experienceLease)
        guard case .active = resumed.physicalPolling else {
            Issue.record("A newer enabled-layer demand must resume physical polling")
            return
        }
        #expect(resumedToken != firstToken)

        session.outputDemands.remove(output)
        session.scheduleDemandReconciliation()
        await session.demandTask?.value
    }

    @Test func nonOperationalLaunchSuspendsWithoutRetiringTheCoordinatorLease() async throws {
        let session = ThrowSession.fixture()
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "non-operational-launch-test"),
        )
        session.replaceLocationModeForTesting(.manual)
        session.outputDemands.insert(output)
        session.demandGeneration = session.demandGeneration.successor()
        await session.reconcileDemand(generation: session.demandGeneration)

        let operationalLaunchState = session.launchState
        let experienceLease = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        let firstToken = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )

        session.launchState = .loading
        session.scheduleDemandReconciliation()
        let stopTask = try #require(session.demandTask)
        await stopTask.value

        let stopped = await session.airAndSpaceRuntime.currentUpdate()
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                experienceLease,
        )
        #expect(stopped.activationLease == experienceLease)
        #expect(stopped.physicalPolling == .stopped)
        #expect(await session.airAndSpaceRuntime.currentPollingUpdateForTesting() == .inactive)

        session.launchState = operationalLaunchState
        session.scheduleDemandReconciliation()
        let resumeTask = try #require(session.demandTask)
        await resumeTask.value

        let resumed = await session.airAndSpaceRuntime.currentUpdate()
        let resumedToken = try #require(
            await session.airAndSpaceRuntime.activePollingActivationForTesting(),
        )
        #expect(
            await session.experienceCoordinator.activationLease(for: .airAndSpace) ==
                experienceLease,
        )
        #expect(resumed.activationLease == experienceLease)
        guard case .active = resumed.physicalPolling else {
            Issue.record("A newer operational demand must resume physical polling")
            return
        }
        #expect(resumedToken != firstToken)

        session.outputDemands.remove(output)
        session.scheduleDemandReconciliation()
        await session.demandTask?.value
    }

    @Test func stoppedDemandRejectsADelayedOlderActivationUnderTheSameLease() async throws {
        let session = ThrowSession.fixture(
            airAndSpacePreferences: ThrowPreferences.defaultValue.airAndSpace
                .replacingFlightsEnabled(false),
        )
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "stopped-demand-tombstone-test"),
        )
        session.replaceLocationModeForTesting(.manual)
        session.outputDemands.insert(output)
        session.demandGeneration = session.demandGeneration.successor()
        await session.reconcileDemand(generation: session.demandGeneration)

        let experienceLease = try #require(
            await session.experienceCoordinator.activationLease(for: .airAndSpace),
        )
        #expect(await session.airAndSpaceRuntime.currentUpdate().physicalPolling == .stopped)

        let activationGate = DemandActivationGate()
        session.beforeAirAndSpaceRuntimeActivationForTesting = {
            await activationGate.hold()
        }
        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingFlightsEnabled(true),
        )
        let delayedActivation = try #require(session.demandTask)
        await activationGate.waitUntilHeld()

        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingFlightsEnabled(false),
        )
        let newerStop = try #require(session.demandTask)
        await newerStop.value

        let stopped = await session.airAndSpaceRuntime.currentUpdate()
        #expect(stopped.activationLease == experienceLease)
        #expect(stopped.physicalPolling == .stopped)
        #expect(await session.airAndSpaceRuntime.activePollingActivationForTesting() == nil)
        #expect(await session.airAndSpaceRuntime.currentPollingUpdateForTesting() == .inactive)

        session.beforeAirAndSpaceRuntimeActivationForTesting = nil
        await activationGate.release()
        await delayedActivation.value

        let afterDelayedActivation = await session.airAndSpaceRuntime.currentUpdate()
        #expect(afterDelayedActivation.activationLease == experienceLease)
        #expect(afterDelayedActivation.successfulActivationLease == nil)
        #expect(afterDelayedActivation.physicalPolling == .stopped)
        #expect(afterDelayedActivation.activePollingSignature == nil)
        #expect(await session.airAndSpaceRuntime.activePollingActivationForTesting() == nil)
        #expect(await session.airAndSpaceRuntime.currentPollingUpdateForTesting() == .inactive)

        session.updateAirAndSpacePreferences(
            session.airAndSpacePreferences.replacingFlightsEnabled(true),
        )
        let replacementActivation = try #require(session.demandTask)
        await replacementActivation.value

        let resumed = await session.airAndSpaceRuntime.currentUpdate()
        #expect(resumed.activationLease == experienceLease)
        guard case .active = resumed.physicalPolling else {
            Issue.record("A newer enabled demand must resume physical polling")
            return
        }
        #expect(await session.airAndSpaceRuntime.activePollingActivationForTesting() != nil)

        session.outputDemands.remove(output)
        session.scheduleDemandReconciliation()
        await session.demandTask?.value
    }

    @Test func GPSAltitudeEditPreservesAcceptedFixAndStaleHealth() async throws {
        let session = ThrowSession.fixture()
        let original = try #require(session.confirmedLocation)
        session.locationHealth = .stale(
            accuracyMeters: original.horizontalAccuracyMeters ?? 0,
            acceptedAt: original.confirmedAt,
        )

        let saved = await session.saveObserverLocation(
            mode: .gps,
            latitude: -45,
            longitude: 100,
            altitudeFeet: 1234,
        )
        let updated = try #require(session.confirmedLocation)

        #expect(saved)
        #expect(updated.position.coordinate == original.position.coordinate)
        #expect(updated.position.altitude.feet == 1234)
        #expect(updated.horizontalAccuracyMeters == original.horizontalAccuracyMeters)
        #expect(updated.confirmedAt == original.confirmedAt)
        #expect(
            session.locationHealth == .stale(
                accuracyMeters: original.horizontalAccuracyMeters ?? 0,
                acceptedAt: original.confirmedAt,
            ),
        )
    }

    @Test func manualLocationCannotSwitchToGPSWithoutAcceptedGPSFix() async throws {
        let session = ThrowSession.fixture()
        let manualSaved = await session.saveObserverLocation(
            mode: .manual,
            latitude: 40,
            longitude: -73,
            altitudeFeet: 20,
        )
        let manual = try #require(session.confirmedLocation)

        let gpsSaved = await session.saveObserverLocation(
            mode: .gps,
            latitude: 41,
            longitude: -74,
            altitudeFeet: 30,
        )

        #expect(manualSaved)
        #expect(gpsSaved == false)
        #expect(session.observerLocationMode == .manual)
        #expect(session.confirmedLocation == manual)
        #expect(
            session.postLaunchFailureLedger.failure(for: .location) ==
                .location(.gpsFixRequired),
        )
    }

    @Test func refreshingAManualLocationRequiresExplicitAcceptanceBeforeSwitchingToGPS() async {
        let session = ThrowSession.fixture()
        session.replaceLocationModeForTesting(.manual)

        await session.refreshLocation()

        #expect(session.observerLocationMode == .manual)
        guard case .offeredBest = session.locationHealth else {
            Issue.record("A GPS fix should be offered while manual mode remains authoritative")
            return
        }

        await session.acceptOfferedLocation()

        #expect(session.observerLocationMode == .gps)
        guard case .confirmed = session.locationHealth else {
            Issue.record("Explicit acceptance should switch to the confirmed GPS fix")
            return
        }
    }
}

private actor DemandActivationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        await withCheckedContinuation { continuation in
            precondition(self.continuation == nil, "Only one activation can wait at the gate")
            self.continuation = continuation
            let waiters = waiters
            self.waiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilHeld() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
