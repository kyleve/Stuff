import Foundation
import RegionKit
@_spi(Testing) @testable import WhereCore

enum CompatibilityTestSupport {
    static let nextVersion = DataCompatibilityVersion(rawValue: 2)
    static let now = Date(timeIntervalSince1970: 1000)

    struct World {
        let store: SwiftDataStore
        let phone: RecordingDeviceID
        let secondary: RecordingDeviceID
        let coordinator: DataCompatibilityCoordinator
    }

    static func makeWorld() async throws -> World {
        let store = try SwiftDataStore.inMemory()
        await store.setSupportedDataCompatibilityVersionForTesting(nextVersion)
        let phone = RecordingDeviceID(rawValue: UUID())
        let secondary = RecordingDeviceID(rawValue: UUID())
        try await store.perform {
            try await store.addRecordingDeviceProfile(.init(
                id: phone,
                systemName: "iPhone",
                kind: .phone,
                registeredAt: now,
                registrationGenerationID: .initial,
            ))
            try await store.addRecordingDeviceProfile(.init(
                id: secondary,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: now,
                registrationGenerationID: .initial,
            ))
        }
        return World(
            store: store,
            phone: phone,
            secondary: secondary,
            coordinator: DataCompatibilityCoordinator(store: store, currentDeviceID: secondary),
        )
    }

    static var sample: LocationSample {
        LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }
}
