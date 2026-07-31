import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingModelTests {
    @Test func managementOnlyOnboardingDoesNotAdvertiseAutomaticRecording() {
        #expect(OnboardingPage.pages(supportsRecording: false).map(\.id) == ["welcome", "privacy"])
        #expect(
            OnboardingPage.pages(supportsRecording: true).map(\.id)
                == ["welcome", "automatic", "privacy"],
        )
    }

    @Test func hasOnboardedDefaultsFalse() {
        let model = WhereModel(
            preferences: makePreferences(),
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        #expect(!model.hasOnboarded)
    }

    @Test func completeOnboardingPersists() {
        let preferences = makePreferences()
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        model.completeOnboarding()
        #expect(model.hasOnboarded)

        // A fresh model over the same preferences sees onboarding as done.
        let relaunched = WhereModel(
            preferences: preferences,
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        #expect(relaunched.hasOnboarded)
    }

    @Test func joiningExistingDataOpensTheRealScopeWithLocalRecordingDisabled() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
        )
        let bootstrap = ScriptedBootstrap(services: services)
        let preferences = makePreferences()
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { bootstrap },
            logSystem: .isolated(),
        )

        try await model.joinExistingData()

        #expect(model.activeScope != nil)
        #expect(model.hasOnboarded)
        #expect(preferences.wantsTracking == false)
        #expect(bootstrap.makeServicesCount == 1)
        let current = try #require(
            try await services.recording.devices(initialEnabled: false).first,
        )
        #expect(current.isEnabled == false)
        #expect(current.device.status == .off)
        #expect(await services.ingestor.isActive == false)
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func joiningExistingDataOverridesAnEnabledSyncedCurrentDevice() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try SwiftDataStore.inMemory()
        let enabledPolicyID = UUID()
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
                id: CurrentRecordingDevice.preview.id,
                systemName: CurrentRecordingDevice.preview.systemName,
                nickname: nil,
                kind: CurrentRecordingDevice.preview.kind,
                registeredAt: now.addingTimeInterval(-120),
                lastSeenAt: now.addingTimeInterval(-60),
                archivedAt: nil,
                lastAppliedPolicyChangeID: enabledPolicyID,
                status: .recording,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: enabledPolicyID,
                deviceID: CurrentRecordingDevice.preview.id,
                effectiveAt: now.addingTimeInterval(-60),
                isEnabled: true,
            ))
        }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            now: { now },
        )
        let preferences = makePreferences()
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { ScriptedBootstrap(services: services) },
            logSystem: .isolated(),
        )

        try await model.joinExistingData()

        let current = try #require(
            try await services.recording.devices(initialEnabled: false).first,
        )
        #expect(current.id == CurrentRecordingDevice.preview.id)
        #expect(current.isEnabled == false)
        #expect(current.device.status == .off)
        #expect(await services.ingestor.isActive == false)
        #expect(preferences.wantsTracking == false)
        #expect(model.hasOnboarded)
    }

    @Test func failedExistingDataJoinRemainsLoggedOutAndRetryable() async {
        let preferences = makePreferences()
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { FailingBootstrap() },
            logSystem: .isolated(),
        )

        do {
            try await model.joinExistingData()
            Issue.record("Expected joining existing data to fail.")
        } catch is FailingBootstrap.AssemblyFailure {
            // Expected. A later call uses the same still-unconsumed bootstrap,
            // which is the retry path the onboarding alert exposes.
        } catch {
            Issue.record("Unexpected join error: \(error)")
        }

        #expect(model.activeScope == nil)
        #expect(model.hasOnboarded == false)
        #expect(preferences.wantsTracking)
    }

    @Test func introStateCarriesExistingDataJoinProgressAndFailure() {
        let state = OnboardingIntroState()
        state.activity = .joiningExistingData

        #expect(state.isJoiningExistingData)
        #expect(state.failure == nil)

        state.activity = .failed(.init(
            flow: .joinExistingData,
            error: FailingBootstrap.AssemblyFailure(),
        ))

        #expect(state.isJoiningExistingData == false)
        #expect(state.failure?.flow == .joinExistingData)
        #expect(state.isShowingFailure)
    }
}
