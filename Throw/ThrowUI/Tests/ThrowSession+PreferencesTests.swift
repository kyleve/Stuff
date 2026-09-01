import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionPreferencesTests {
    @Test func adjacentUIChangesCoalesceBehindAnInFlightSave() async throws {
        let preferenceStore = SuspendingThrowPreferenceStore()
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )

        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        await preferenceStore.waitForFirstSaveToStart()
        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(60),
        )
        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(50),
        )

        let savedBeforeResume = await preferenceStore.savedIntensityPercents()
        #expect(savedBeforeResume.isEmpty)

        await preferenceStore.resumeFirstSave()
        await session.flushPreferencesSave()

        #expect(await preferenceStore.savedIntensityPercents() == [70, 50])
    }

    @Test func immediateSaveRemainsAnOrderingBarrierForLaterUIChanges() async throws {
        let preferenceStore = SuspendingThrowPreferenceStore()
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )

        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        await preferenceStore.waitForFirstSaveToStart()
        let immediateSave = Task {
            try await session.savePreferencesImmediately()
        }
        while session.preferenceSaveQueue.contains(where: \.isImmediate) == false {
            await Task.yield()
        }
        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(60),
        )

        await preferenceStore.resumeFirstSave()
        try await immediateSave.value
        await session.flushPreferencesSave()

        #expect(await preferenceStore.savedIntensityPercents() == [70, 70, 60])
    }
}
