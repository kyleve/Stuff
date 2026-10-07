import Foundation
@_spi(Testing) import WhereCore

enum DataFeatureAvailabilityTestSupport {
    static let version = DataCompatibilityVersion(rawValue: 2)
    static let now = Date(timeIntervalSince1970: 1000)

    struct World {
        let store: SwiftDataStore
        let services: WhereServices
        let otherDeviceID: RecordingDeviceID
    }

    static func makeWorld() async throws -> World {
        let store = try SwiftDataStore.inMemory()
        await store.setSupportedDataCompatibilityVersionForTesting(version)
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let otherDeviceID = RecordingDeviceID(rawValue: UUID())
        try await register(otherDeviceID, in: store)
        return World(store: store, services: services, otherDeviceID: otherDeviceID)
    }

    static func register(_ deviceID: RecordingDeviceID, in store: SwiftDataStore) async throws {
        try await store.perform {
            try await store.addRecordingDeviceProfile(.init(
                id: deviceID,
                systemName: "iPhone",
                kind: .phone,
                registeredAt: now,
                registrationGenerationID: .initial,
            ))
        }
    }

    static func exportFutureBackup() async throws -> URL {
        let store = try SwiftDataStore.inMemory()
        await store.setSupportedDataCompatibilityVersionForTesting(version)
        try await store.perform { try await store.requireDataCompatibility(version) }
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        return try await services.backup.exportBackup()
    }

    static var ready: DataCompatibilityActivationReview {
        .init(
            requiredVersion: version,
            previousVersion: .initial,
            generationID: .initial,
            affectedDevices: [],
        )
    }
}
