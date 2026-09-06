import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionOnboardingTests {
    @Test func completionRepersistsAConcurrentTypedPreferenceBeforePublication() async throws {
        let preferenceStore = OnboardingRacePreferenceStore()
        let session = ThrowSession.launchFixture(
            setupCompleted: false,
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let completion = Task {
            await session.completeOnboarding(
                locationMode: .gps,
                latitude: session.observerLatitude,
                longitude: session.observerLongitude,
                observerAltitudeFeet: session.observerAltitudeFeet,
                validatedSourceDraft: ValidatedAircraftSourceDraft(source: .adsbLol),
                projectionMode: .map,
                calibration: .defaultValue,
                quietSchedule: .disabled,
                mapViewport: .defaultValue,
                skyViewport: .defaultValue,
            )
        }
        await preferenceStore.waitForSecondSaveToStart()

        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        await preferenceStore.resumeSecondSave()
        await completion.value

        let persisted = await preferenceStore.persistedPreferences()
        #expect(session.setupCompleted)
        #expect(session.intensityPercent == 70)
        #expect(persisted.setupCompleted)
        #expect(persisted.intensityPercent == 70)
        #expect(await preferenceStore.savedIntensityPercents() == [80, 80, 70])
    }
}
