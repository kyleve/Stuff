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

    @Test func notNowOverridesAnEnabledRestoredCurrentDevicePolicy() async throws {
        let subject = try await makeRestoredPolicySubject(isEnabled: true)
        let scope = try await subject.model.resolveScope()

        try await subject.model.applyOnboardingRecordingChoice(false, in: scope)

        let policies = try await subject.store.recordingPolicyChanges()
        let latest = try #require(policies.max { lhs, rhs in
            lhs.effectiveAt < rhs.effectiveAt
        })
        #expect(policies.count == 2)
        #expect(latest.isEnabled == false)
        #expect(subject.preferences.wantsTracking == false)
        let current = try #require(
            try await subject.services.recording.devices(initialEnabled: false).first,
        )
        #expect(current.isEnabled == false)
        #expect(current.device.status == .off)
        #expect(await subject.services.ingestor.isActive == false)
    }

    @Test func enablingOverridesADisabledRestoredCurrentDevicePolicy() async throws {
        let subject = try await makeRestoredPolicySubject(isEnabled: false)
        let scope = try await subject.model.resolveScope()

        try await subject.model.applyOnboardingRecordingChoice(true, in: scope)

        let policies = try await subject.store.recordingPolicyChanges()
        let latest = try #require(policies.max { lhs, rhs in
            lhs.effectiveAt < rhs.effectiveAt
        })
        #expect(policies.count == 2)
        #expect(latest.isEnabled)
        #expect(subject.preferences.wantsTracking)
        let current = try #require(
            try await subject.services.recording.devices(initialEnabled: true).first,
        )
        #expect(current.isEnabled)
        #expect(current.device.status == .recording)
        #expect(await subject.services.ingestor.isActive)
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

    private struct RestoredPolicySubject {
        let model: WhereModel
        let services: WhereServices
        let store: SwiftDataStore
        let preferences: WherePreferences
    }

    private func makeRestoredPolicySubject(
        isEnabled: Bool,
    ) async throws -> RestoredPolicySubject {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try SwiftDataStore.inMemory()
        let policyID = UUID()
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
                id: CurrentRecordingDevice.preview.id,
                systemName: CurrentRecordingDevice.preview.systemName,
                nickname: nil,
                kind: CurrentRecordingDevice.preview.kind,
                registeredAt: now.addingTimeInterval(-120),
                lastSeenAt: now.addingTimeInterval(-60),
                archivedAt: nil,
                lastAppliedPolicyChangeID: policyID,
                status: isEnabled ? .recording : .off,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: policyID,
                deviceID: CurrentRecordingDevice.preview.id,
                effectiveAt: now.addingTimeInterval(-60),
                isEnabled: isEnabled,
            ))
        }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            now: { now },
        )
        let preferences = makePreferences()
        preferences.wantsTracking = isEnabled
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { ScriptedBootstrap(services: services) },
            logSystem: .isolated(),
        )
        return RestoredPolicySubject(
            model: model,
            services: services,
            store: store,
            preferences: preferences,
        )
    }
}
