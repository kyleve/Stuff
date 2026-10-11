import Foundation
import PeriscopeCore
@_spi(Testing) import WhereCore
@_spi(Testing) import WhereUI

/// A real compatibility control plane over one memory store, with replaceable normal scopes.
@MainActor
final class CompatibilityBootstrap: WhereScopeAssembling {
    let store: SwiftDataStore
    let installation: InMemoryInstallationRecordingContextStore
    let authority: RecordingAuthorityCoordinator
    let recording: RecordingDeviceCoordination
    let compatibility: DataCompatibilityCoordinator
    private(set) var withdrawals = 0
    func withdrawCompatibilityOutputs() async {
        withdrawals += 1
    }

    private(set) var makeServicesCount = 0
    private(set) var lastDomainStore: (any WhereStore)?

    init() throws {
        let store = try SwiftDataStore.inMemory()
        self.store = store
        let installation = InMemoryInstallationRecordingContextStore(context: .init(
            currentDevice: .init(
                id: .init(rawValue: UUID()),
                systemName: "New iPhone",
                kind: .phone,
            ),
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        ))
        self.installation = installation
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        self.authority = authority
        let recording = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        self.recording = recording
        compatibility = DataCompatibilityCoordinator(
            store: store,
            recording: recording,
            installation: installation,
        )
    }

    func prepareLocation() {}
    func prepareCompatibility() async throws -> DataCompatibilityCoordinator? {
        compatibility
    }

    func prepareDeviceCoordination() async throws -> RecordingDeviceCoordination? {
        recording
    }

    func discoverRecordingDevices() async throws -> [RecordingDevice] {
        []
    }

    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }

    func makeServices() async throws -> WhereServices {
        let domain = try await compatibility.openDomainStore()
        makeServicesCount += 1
        lastDomainStore = domain
        return try WhereServices(
            store: domain,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: installation.resolve(),
            recordingAuthority: authority,
            deviceCoordination: recording,
        )
    }
}
