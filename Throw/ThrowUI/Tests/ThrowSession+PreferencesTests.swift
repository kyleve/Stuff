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
        while session.preferencePersistence.hasPendingImmediateRequest == false {
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

    @Test func preferenceSaveSuccessKeepsOtherOwnersFailures() async throws {
        let preferenceStore = SwitchableThrowPreferenceStore(failsSave: true)
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )

        #expect(await session.useSource(ValidatedAircraftSourceDraft(source: .adsbLol)) == false)
        #expect(await session.saveObserverLocation(
            mode: .manual,
            latitude: 40,
            longitude: -73,
            altitudeFeet: 20,
        ) == false)
        session.setExperienceDwellDuration(seconds: 31, for: .airAndSpace)

        #expect(session.postLaunchFailureLedger.failure(for: .aircraftSource) != nil)
        #expect(session.postLaunchFailureLedger.failure(for: .location) != nil)
        #expect(session.postLaunchFailureLedger.failure(for: .playlist) != nil)

        await preferenceStore.setFailsSave(false)
        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        await session.flushPreferencesSave()

        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) == nil)
        #expect(session.postLaunchFailureLedger.failure(for: .aircraftSource) != nil)
        #expect(session.postLaunchFailureLedger.failure(for: .location) != nil)
        #expect(session.postLaunchFailureLedger.failure(for: .playlist) != nil)
    }

    @Test func ownerSuccessesKeepPreferencePersistenceFailure() async throws {
        let preferenceStore = SwitchableThrowPreferenceStore(failsSave: true)
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        session.updateReduceMotion(true)

        try session.updateGlobalPreferences(
            session.globalPreferences.replacingIntensityPercent(70),
        )
        await session.flushPreferencesSave()
        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) != nil)

        await preferenceStore.setFailsSave(false)
        #expect(await session.useSource(ValidatedAircraftSourceDraft(source: .adsbLol)))
        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) != nil)

        #expect(await session.saveObserverLocation(
            mode: .manual,
            latitude: 40,
            longitude: -73,
            altitudeFeet: 20,
        ))
        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) != nil)

        session.setExperienceDwellDuration(seconds: 600, for: .airAndSpace)
        await session.flushPreferencesSave()
        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) != nil)
    }

    @Test func deferredMutationSavesRetainEveryRequestOwner() async {
        let preferenceStore = SwitchableThrowPreferenceStore(failsSave: true)
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )

        #expect(session.beginPreferenceMutation())
        session.schedulePreferencesSave(failure: .playlist(nil))
        session.schedulePreferencesSave(failure: .preferencePersistence)
        session.finishPreferenceMutation()
        await session.flushPreferencesSave()

        #expect(session.postLaunchFailureLedger.failure(for: .playlist) != nil)
        #expect(session.postLaunchFailureLedger.failure(for: .preferencePersistence) != nil)
    }

    @Test func flushWaitsForASourceMutationSuspendedInCredentialStorage() async throws {
        let credentialStore = SuspendingAircraftCredentialStore(credentials: [:])
        let session = ThrowSession.fixture(
            preferenceStore: SwitchableThrowPreferenceStore(failsSave: false),
            credentialStore: credentialStore,
        )
        let replacement = try AircraftCredential(secret: "fr24-replacement-1234")
        let sourceMutation = Task {
            await session.useSource(ValidatedAircraftSourceDraft(
                source: .flightradar24(
                    Flightradar24Configuration(pollingInterval: .defaultValue),
                    replacementCredential: replacement,
                ),
            ))
        }
        await credentialStore.waitForSaveToStart()

        let completion = PreferenceFlushCompletionProbe()
        let flush = Task {
            await session.flushPreferencesSave()
            completion.complete()
        }
        while session.preferencePersistence.quiescenceWaiterCount == 0,
              completion.isComplete == false
        {
            await Task.yield()
        }

        #expect(session.preferencePersistence.quiescenceWaiterCount == 1)
        #expect(completion.isComplete == false)
        await credentialStore.resumeSave()
        #expect(await sourceMutation.value)
        await flush.value
        #expect(completion.isComplete)
    }

    @Test func flushWaitsForWorkDeferredBehindALocationMutation() async {
        let preferenceStore = ControlledThrowPreferenceStore(
            saveBehavior: .scripted([.succeed, .suspendThenSucceed]),
        )
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let activationLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let activated = session.airAndSpaceActivation.activate(activationLease)
        #expect(activated)
        let mutationGate = PreferenceMutationGate()
        session.beforeProjectionPreferenceRuntimeDeactivationForTesting = {
            await mutationGate.suspend()
        }
        let locationMutation = Task {
            await session.saveObserverLocation(
                mode: .manual,
                latitude: 40,
                longitude: -73,
                altitudeFeet: 20,
            )
        }
        await mutationGate.waitUntilSuspended()

        session.setExperienceDwellDuration(seconds: 180, for: .airAndSpace)
        let completion = PreferenceFlushCompletionProbe()
        let flush = Task {
            await session.flushPreferencesSave()
            completion.complete()
        }
        while session.preferencePersistence.quiescenceWaiterCount == 0,
              completion.isComplete == false
        {
            await Task.yield()
        }
        #expect(session.preferencePersistence.quiescenceWaiterCount == 1)
        #expect(completion.isComplete == false)

        await mutationGate.resume()
        await preferenceStore.waitForSaveCount(2)
        #expect(completion.isComplete == false)

        await preferenceStore.resumeSave()
        #expect(await locationMutation.value)
        await flush.value
        #expect(completion.isComplete)
        #expect(await preferenceStore.saveAttemptCount() == 2)
        #expect(
            await preferenceStore.persistedPreferences().playlist
                .entry(for: .airAndSpace)?.dwellDuration.seconds == 180,
        )
        session.beforeProjectionPreferenceRuntimeDeactivationForTesting = nil
    }
}
