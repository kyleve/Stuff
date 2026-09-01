import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ProjectionViewportSettingsModelTests {
    @Test func invalidMapRadiusStaysInTheDraftWithoutRuntimeEffects() async throws {
        let preferenceStore = SuspendingThrowPreferenceStore()
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let activeSignature = try PollingSignature(
            configuration: .adsbLol,
            query: session.aircraftQuery(),
        )
        let activationLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let activated = session.airAndSpaceActivation.activate(activationLease)
        #expect(activated)
        await session.airAndSpaceRuntime.activate(
            configuration: .adsbLol,
            query: activeSignature.query,
            labelMode: session.labelMode,
            lease: activationLease,
        )
        session.activePollingSignature = activeSignature
        let demandGeneration = session.demandGeneration
        let model = ProjectionViewportSettingsModel(session: session)

        model.mapRadius = 7
        await Task.yield()

        #expect(model.mapViewportIsValid == false)
        #expect(session.mapRadius == MapViewport.defaultValue.radius.value)
        #expect(session.demandGeneration == demandGeneration)
        #expect(session.activePollingSignature == activeSignature)
        #expect(await preferenceStore.startedSaveCount() == 0)
        #expect(await session.airAndSpaceRuntime.activeSourceKindForTesting() == .adsbLol)

        await session.airAndSpaceRuntime.deactivate(
            lease: activationLease,
            reporting: .idle,
        )
    }

    @Test func validMapRadiusPublishesPersistsAndReconcilesOnce() async {
        let preferenceStore = SuspendingThrowPreferenceStore()
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let demandGeneration = session.demandGeneration
        let model = ProjectionViewportSettingsModel(session: session)

        model.mapRadius = 55
        await preferenceStore.waitForFirstSaveToStart()

        #expect(model.mapViewportIsValid)
        #expect(session.mapRadius == 55)
        #expect(session.demandGeneration == demandGeneration + 1)
        #expect(await preferenceStore.startedSaveCount() == 1)

        await preferenceStore.resumeFirstSave()
        await session.flushPreferencesSave()
        await session.demandTask?.value

        #expect(await preferenceStore.savedMapRadii() == [55])
    }
}
