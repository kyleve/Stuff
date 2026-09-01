import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionTests {
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

        session.geographyEnabled = false
        session.geographyIntensityPercent = 12
        let preferences = try session.makePreferences()

        #expect(session.demandGeneration == demandGeneration)
        #expect(preferences.geography.isEnabled == false)
        #expect(preferences.geography.intensityPercent == 12)
    }

    @Test func configuredProjectionChangeUpdatesTheTypedSetup() throws {
        let session = ThrowSession.fixture()

        session.projectionMode = .trueSky

        let preferences = try session.makePreferences()
        #expect(preferences.setupCompleted)
        #expect(preferences.selectedProjectionMode == .trueSky)
    }

    @Test func disablingGeographyImmediatelyRemovesAPublishedStaticFrame() {
        let session = ThrowSession.fixture()

        #expect(session.projectionFrame.geography != nil)
        session.currentLayerFrame = nil
        session.geographyEnabled = false

        #expect(session.projectionFrame.geography == nil)
        #expect(session.projectionFrame.marks.isEmpty == false)
        #expect(session.geographyLayerHealth == .idle)
    }

    @Test func clearingProjectionStateRemovesTheObserverMarkerForQuietBlack() async {
        let session = ThrowSession.fixture()
        session.observerMapPoint = ProjectionPoint(x: 0.5, y: 0.5)

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
        session.hasStarted = true
        session.locationMode = .manual
        session.aircraftSourceSelection = .awaitingValidation(.adsbLol)
        session.outputDemands.insert(output)
        session.projectionOutputCount = 1
        session.demandGeneration = 1

        await session.reconcileDemand(generation: 1)
        let renderTask = session.renderTask
        await renderTask?.value

        #expect(session.projectionFrame.marks.isEmpty)
        #expect(session.projectionFrame.geography != nil)
        #expect(session.currentSnapshot == nil)
        #expect(session.currentLayerFrame == nil)
        #expect(session.renderTask == nil)
        #expect(session.feedHealth == .failed(.sourceNotValidated))
    }

    @Test func geographyCanProjectWhileFlightsAndPollingAreOff() async {
        let session = ThrowSession.fixture()
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "geography-only-test"),
        )
        session.hasStarted = true
        session.locationMode = .manual
        session.isApplyingPreferences = true
        session.flightsEnabled = false
        session.isApplyingPreferences = false
        session.outputDemands.insert(output)
        session.projectionOutputCount = 1
        session.demandGeneration = 1

        await session.reconcileDemand(generation: 1)
        let renderTask = session.renderTask
        await renderTask?.value

        #expect(session.activePollingSignature == nil)
        #expect(session.feedHealth == .idle)
        #expect(session.projectionFrame.geography != nil)
        #expect(session.renderTask == nil)
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
        #expect(session.settingsFailure != nil)
    }

    @Test func refreshingAManualLocationRequiresExplicitAcceptanceBeforeSwitchingToGPS() async {
        let session = ThrowSession.fixture()
        session.locationMode = .manual

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
