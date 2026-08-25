import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionTests {
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

    @Test func retryingVisibleCountReflectsLastGoodProjection() {
        let now = Date(timeIntervalSince1970: 100)
        let health = FeedHealth.retrying(
            lastUpdate: now,
            nextRetry: now.addingTimeInterval(10),
            failure: .transport,
            visibleAircraft: 4,
        )

        #expect(health.visibleAircraft == 4)
    }

    @Test func invalidSourceReconciliationMakesBlankFrameAuthoritative() async {
        let session = ThrowSession.fixture()
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "invalid-source-test"),
        )
        session.hasStarted = true
        session.selectedSourceConfiguration = .adsbLol
        session.validatedSourceConfiguration = nil
        session.outputDemands.insert(output)
        session.projectionOutputCount = 1
        session.demandGeneration = 1

        await session.reconcileDemand(generation: 1)

        #expect(session.projectionFrame.marks.isEmpty)
        #expect(session.currentSnapshot == nil)
        #expect(session.currentLayerFrame == nil)
        #expect(session.renderTask == nil)
        #expect(session.feedHealth == .failed(.sourceNotValidated))
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
