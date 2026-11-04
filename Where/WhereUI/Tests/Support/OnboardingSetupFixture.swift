import Foundation
import LifecycleKit
import PeriscopeCore
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Exercises onboarding with real services, an isolated store, and a scripted location source.
@MainActor
struct OnboardingSetupFixture {
    let store: SwiftDataStore
    let source: ScriptedLocationSource
    let preferences: WherePreferences
    let model: WhereModel
    let installationStore: any InstallationRecordingContextStoring

    init(
        installationStore: any InstallationRecordingContextStoring,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
    ) throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        self.store = store
        self.source = source
        preferences = makePreferences()
        self.installationStore = installationStore
        model = WhereModel(
            preferences: preferences,
            installationContextStore: installationStore,
            makeBootstrap: { contextStore in
                OnboardingSetupBootstrap(
                    store: store,
                    source: source,
                    installationStore: contextStore,
                    outbox: outbox,
                )
            },
            logSystem: .isolated(),
        )
    }

    func flow() throws -> OnboardingFlowModel {
        try OnboardingFlowModel(
            gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
            installationContext: installationStore.resolve(),
            startsAtRecordingChoice: true,
            initialTheme: .standard,
            preferences: preferences,
        )
    }

    func addDevice(_ deviceID: RecordingDeviceID) async throws {
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: deviceID,
                systemName: "iPhone",
                kind: .phone,
                registeredAt: InstallationRecordingContext.testing.registeredAt,
                registrationGenerationID: .initial,
            ))
        }
    }
}

@MainActor
private struct OnboardingSetupBootstrap: WhereScopeAssembling {
    func sharedEvidenceDraftQueue() -> (any SharedEvidenceDraftQueuing)? {
        nil
    }

    func prepareDataCompatibility() -> DataCompatibilityCoordinator? {
        nil
    }

    func withdrawHistoryOutputs() async {}

    let store: SwiftDataStore
    let source: ScriptedLocationSource
    let installationStore: any InstallationRecordingContextStoring
    let outbox: any LocationOutbox

    func prepareLocation() {}

    func makeServices() async throws -> WhereServices {
        try WhereServices(
            store: store,
            locationSource: source,
            installationContext: installationStore.resolve(),
            locationOutbox: outbox,
            importRecoveryPersistence: installationStore,
        )
    }

    func discoverRecordingDevices() async throws -> [RecordingDevice] {
        try await store.recordingDevices()
    }

    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }
}

/// Holds destructive import cleanup so a test can inspect capture before recovery completes.
actor OnboardingSetupOutbox: LocationOutbox {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasCleared = false

    func load() async throws -> [LocationOutboxEntry] {
        []
    }

    func save(_: [LocationOutboxEntry]) async throws {}

    func clear() async throws {
        guard !hasCleared else { return }
        await withCheckedContinuation { continuation = $0 }
        hasCleared = true
    }

    func waitUntilClearing() async throws {
        struct Timeout: Error {}
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while continuation == nil {
            if ContinuousClock.now >= deadline { throw Timeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
