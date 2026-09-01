import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionLocationTests {
    @Test func locationRemainsOnTheCommittedObserverWhilePersistenceIsSuspended() async throws {
        let preferenceStore = ControlledThrowPreferenceStore(saveBehavior: .suspended)
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let originalSetupState = session.setupState
        let originalLocation = try #require(session.confirmedLocation)
        let originalHealth = session.locationHealth
        let originalFrame = session.projectionFrame

        let save = Task {
            await session.saveObserverLocation(
                mode: .manual,
                latitude: 40,
                longitude: -73,
                altitudeFeet: 20,
            )
        }
        await preferenceStore.waitForSaveToStart()

        #expect(session.setupState == originalSetupState)
        #expect(session.confirmedLocation == originalLocation)
        #expect(session.locationHealth == originalHealth)
        #expect(session.projectionFrame == originalFrame)

        await preferenceStore.resumeSave()
        let saved = await save.value
        #expect(saved)
        #expect(session.confirmedLocation != originalLocation)
    }

    @Test func failedLocationPersistencePreservesTheCompleteProjectionContext() async throws {
        let preferenceStore = ControlledThrowPreferenceStore(saveBehavior: .failing)
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let query = try session.aircraftQuery()
        let activationLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let activated = session.airAndSpaceActivation.activate(activationLease)
        #expect(activated)
        await session.airAndSpaceRuntime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: session.labelMode,
            lease: activationLease,
        )
        session.activePollingSignature = try PollingSignature(
            configuration: .adsbLol,
            query: query,
        )
        session.projectionSessionLocationGate = .ready
        let offeredFix = try ThrowSessionLocationTestFixture.fix(
            latitude: 41,
            longitude: -72,
            accuracyMeters: 150,
        )
        session.pendingLocationFix = offeredFix
        let originalSetupState = session.setupState
        let originalHealth = session.locationHealth
        let originalSignature = session.activePollingSignature
        let originalFrame = session.projectionFrame
        let originalExperienceFrame = session.currentExperienceFrame

        let saved = await session.saveObserverLocation(
            mode: .manual,
            latitude: 40,
            longitude: -73,
            altitudeFeet: 20,
        )

        #expect(saved == false)
        #expect(session.setupState == originalSetupState)
        #expect(session.locationHealth == originalHealth)
        #expect(session.activePollingSignature == originalSignature)
        #expect(session.projectionFrame == originalFrame)
        #expect(session.currentExperienceFrame == originalExperienceFrame)
        #expect(session.pendingLocationFix == offeredFix)
        guard case .ready = session.projectionSessionLocationGate else {
            Issue.record("A failed save must preserve the prior location gate")
            return
        }
        #expect(await session.airAndSpaceRuntime.activeSourceKindForTesting() == .adsbLol)
        await session.airAndSpaceRuntime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func firstGPSOutputAcquiresTargetFixBeforePolling() async throws {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        await session.start()
        await session.demandTask?.value
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "gps-startup-target"),
        )

        session.projectionOutputConnected(output)
        await locationSource.waitForStartCount(1)

        #expect(locationSource.requestAuthorizationCount == 1)
        #expect(session.activePollingSignature == nil)
        #expect(session.locationHealth == .locating)

        let fix = try ThrowSessionLocationTestFixture.fix(
            latitude: 37.78,
            longitude: -122.42,
            accuracyMeters: 25,
        )
        let acquisition = try #require(session.locationTask)
        locationSource.send(.fix(fix))
        await acquisition.value
        await session.demandTask?.value

        #expect(session.confirmedLocation?.position == fix.position)
        #expect(session.activePollingSignature != nil)
        guard case .ready = session.projectionSessionLocationGate else {
            Issue.record("The accepted target fix should open the projection-session gate")
            return
        }

        session.projectionOutputDisconnected(output)
        await session.demandTask?.value
    }

    @Test func manualProjectionSessionDoesNotRequestGPS() async throws {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        await session.start()
        await session.demandTask?.value
        _ = await session.saveObserverLocation(
            mode: .manual,
            latitude: 40,
            longitude: -73,
            altitudeFeet: 20,
        )
        await session.demandTask?.value
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "manual-startup"),
        )

        session.projectionOutputConnected(output)
        await session.demandTask?.value

        #expect(locationSource.requestAuthorizationCount == 0)
        #expect(locationSource.startCount == 0)
        #expect(session.observerLocationMode == .manual)
        #expect(session.activePollingSignature != nil)
        guard case let .configured(setup) = session.setupState else {
            Issue.record("Saving a manual location must preserve configured setup")
            return
        }
        let confirmedLocation = try #require(session.confirmedLocation)
        #expect(setup.locationMode == .manual)
        #expect(setup.confirmedLocation == confirmedLocation)

        session.projectionOutputDisconnected(output)
        await session.demandTask?.value
    }

    @Test func disconnectingLastOutputCancelsGPSAcquisitionAndRestoresHealth() async {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        await session.start()
        await session.demandTask?.value
        let previousHealth = session.locationHealth
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "gps-disconnect"),
        )
        session.projectionOutputConnected(output)
        await locationSource.waitForStartCount(1)
        let acquisition = session.locationTask

        session.projectionOutputDisconnected(output)
        await locationSource.waitForStopCount(1)
        await acquisition?.value
        await session.demandTask?.value

        #expect(session.locationHealth == previousHealth)
        #expect(session.activePollingSignature == nil)
        guard case .required = session.projectionSessionLocationGate else {
            Issue.record("A later projection session should require a new GPS acquisition")
            return
        }
    }

    @Test func backgroundCancelsStartupGPSAndForegroundRestartsIt() async throws {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        await session.start()
        await session.demandTask?.value
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "gps-background"),
        )
        session.projectionOutputConnected(output)
        await locationSource.waitForStartCount(1)
        let firstAcquisition = try #require(session.locationTask)

        session.controllerForegroundPresenceDidChange(false)
        session.controllerForegroundPresenceDidChange(true)
        await firstAcquisition.value
        await locationSource.waitForStartCount(2)
        #expect(session.locationHealth == .locating)
        #expect(session.activePollingSignature == nil)
        let secondStartStopCount = try #require(locationSource.stopCountAtEachStart.last)
        #expect(secondStartStopCount >= 2)

        let fix = try ThrowSessionLocationTestFixture.fix(
            latitude: 37.79,
            longitude: -122.41,
            accuracyMeters: 30,
        )
        let acquisition = try #require(session.locationTask)
        locationSource.send(.fix(fix))
        await acquisition.value
        await session.demandTask?.value

        #expect(session.activePollingSignature != nil)

        session.projectionOutputDisconnected(output)
        await session.demandTask?.value
    }

    @Test func failedAcquisitionUsesConfirmedFixOnlyWithStaleHealth() async {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        await session.start()
        await session.demandTask?.value
        let confirmed = session.confirmedLocation
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "gps-stale-fallback"),
        )
        session.projectionOutputConnected(output)
        await locationSource.waitForStartCount(1)
        let acquisition = session.locationTask

        locationSource.send(.failed)
        await acquisition?.value
        await session.demandTask?.value

        #expect(session.confirmedLocation == confirmed)
        guard case .stale = session.locationHealth else {
            Issue.record("The saved GPS fix must remain visibly stale")
            return
        }
        #expect(session.activePollingSignature != nil)

        session.projectionOutputDisconnected(output)
        await session.demandTask?.value
    }

    @Test func supersededRefreshCannotApplyAResolvedFix() async throws {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        let originalLocation = session.confirmedLocation
        session.beforeApplyingLocationResolutionForTesting = { [weak session] in
            guard let session else { return }
            session.locationGeneration &+= 1
            session.locationHealth = .failed
        }
        let refresh = Task { await session.refreshLocation() }
        await locationSource.waitForStartCount(1)
        let replacement = try ThrowSessionLocationTestFixture.fix(
            latitude: 40,
            longitude: -73,
            accuracyMeters: 25,
        )

        locationSource.send(.fix(replacement))
        await refresh.value

        #expect(session.confirmedLocation == originalLocation)
        #expect(session.locationHealth == .failed)
    }

    @Test func matchingTrueHeadingStillConsumesTheOneShotHint() async throws {
        let locationSource = ControlledThrowLocationSource()
        let session = ThrowSession.fixture(locationSource: locationSource)
        session.mayApplyTrueHeadingHint = true
        #expect(session.mayApplyTrueHeadingHint)

        let firstRefresh = Task { await session.refreshLocation() }
        await locationSource.waitForStartCount(1)
        try locationSource.send(.trueHeadingHint(Bearing(degrees: 0)))
        locationSource.send(.failed)
        await firstRefresh.value

        #expect(session.mayApplyTrueHeadingHint == false)
        #expect(session.screenTopBearing == 0)

        let secondRefresh = Task { await session.refreshLocation() }
        await locationSource.waitForStartCount(2)
        try locationSource.send(.trueHeadingHint(Bearing(degrees: 90)))
        locationSource.send(.failed)
        await secondRefresh.value

        #expect(session.screenTopBearing == 0)
    }

    @Test func editableMapCenterOffsetRoundTripsOnTheFiveMileGrid() async throws {
        let session = ThrowSession.fixture()

        try session.updateMapCenterOffset(
            MapCenterOffset(eastNauticalMiles: 5, northNauticalMiles: 10),
        )

        #expect(session.mapCenterEastOffset == 5)
        #expect(session.mapCenterNorthOffset == 10)

        try session.updateMapCenterOffset(
            MapCenterOffset(
                eastNauticalMiles: 15,
                northNauticalMiles: session.mapCenterNorthOffset,
            ),
        )
        await session.flushPreferencesSave()
        await session.demandTask?.value

        #expect(session.mapCenterEastOffset == 15)
        #expect(session.mapCenterNorthOffset == 10)
    }

    @Test func offeredBestFixDoesNotPollUntilExplicitAcceptance() async throws {
        let session = ThrowSession.fixture()
        await session.start()
        await session.demandTask?.value
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "gps-offered-best"),
        )
        let fix = try ThrowSessionLocationTestFixture.fix(
            latitude: 37.8,
            longitude: -122.4,
            accuracyMeters: 180,
        )
        session.outputDemands.insert(output)
        session.pendingLocationFix = fix
        session.locationHealth = .offeredBest(
            accuracyMeters: fix.horizontalAccuracyMeters,
            observedAt: fix.observedAt,
            hasStaleConfirmedLocation: true,
        )
        session.projectionSessionLocationGate = .required

        #expect(session.activePollingSignature == nil)

        await session.acceptOfferedLocation()
        await session.demandTask?.value

        #expect(session.confirmedLocation?.position == fix.position)
        #expect(session.activePollingSignature != nil)

        session.projectionOutputDisconnected(output)
        await session.demandTask?.value
    }
}
