import Foundation
import Testing
@testable import WhereCore

struct RecordingDevicePolicyResolverTests {
    private static let currentID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )

    @Test func configurationsKeepCurrentFirstAndExposeOnlyItsLocalChoice() async throws {
        let store = try SwiftDataStore.inMemory()
        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: remoteID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: registeredAt.addingTimeInterval(1),
                registrationGenerationID: .initial,
            ))
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: Self.currentID,
                systemName: "iPhone",
                kind: .phone,
                registeredAt: registeredAt,
                registrationGenerationID: .initial,
            ))
        }

        let configurations = try await RecordingDevicePolicyResolver(
            store: store,
            currentDeviceID: Self.currentID,
        ).configurations(localAutomaticRecordingEnabled: true, includeRemoved: false)

        #expect(configurations.map(\.id) == [Self.currentID, remoteID])
        #expect(configurations.map(\.localAutomaticRecordingEnabled) == [true, nil])
    }

    @Test func revisionOverflowFailsClosed() {
        #expect(throws: RecordingPersistenceError.revisionExhausted(Self.currentID)) {
            try RecordingDevicePolicyResolver.nextRevision(
                after: .max,
                for: Self.currentID,
            )
        }
    }
}
