import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingAuthorityCoordinatorTests {
    @Test func partialHistoryFailsClosedUntilRefreshRepairsIt() async throws {
        let fixture = RecordingAuthorityFixture()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let store = try SwiftDataStore.inMemory()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        _ = try await server.commit(claim)
        let upgrade = try fixture.proposal(
            claim.result,
            .upgrade,
            device: fixture.phone,
            version: .init(rawValue: 2),
        )
        let receipt = try await server.commit(upgrade)
        try await store.perform { try await store.addRecordingAuthorityCommit(receipt) }
        await #expect(throws: RecordingAuthorityError.invalidRecord) {
            try await store.recordingAuthority()
        }
        let coordinator = RecordingAuthorityCoordinator(store: store, transport: server)
        #expect(try await coordinator.refresh() == upgrade.result)
    }

    @Test func generationRotationPreservesAuthorityAndRequirement() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let coordinator = RecordingAuthorityCoordinator(store: store, transport: server)
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        _ = try await coordinator.submit(claim)
        let upgrade = try fixture.proposal(
            claim.result,
            .upgrade,
            device: fixture.phone,
            version: .init(rawValue: 2),
        )
        _ = try await coordinator.submit(upgrade)
        await store.setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: fixture.phone,
                at: Date(),
            )
        }
        #expect(try await coordinator.observed() == upgrade.result)
    }

    @Test func refreshRecoversMissedTransitionsAndNeverRegresses() async throws {
        let fixture = RecordingAuthorityFixture()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let store = try SwiftDataStore.inMemory()
        let coordinator = RecordingAuthorityCoordinator(store: store, transport: server)
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        _ = try await server.commit(claim)
        let recovery = try fixture.proposal(
            claim.result,
            .recover(.excludeAfterReplacement),
            device: fixture.tablet,
        )
        _ = try await server.commit(recovery)
        #expect(try await coordinator.refresh() == recovery.result)
        #expect(try await store.recordingAuthorityCommits().count == 2)
        _ = try await coordinator.submit(claim)
        #expect(try await coordinator.observed() == recovery.result)
        #expect(try await store.recordingAuthorityCommits().count == 2)
    }

    @Test func missingPreviouslyObservedAuthorityFailsClosed() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let coordinator = RecordingAuthorityCoordinator(store: store, transport: server)
        _ = try await coordinator.submit(fixture.proposal(.initial, .claim, device: fixture.phone))
        let emptyServer = LocalRecordingAuthorityTransport(now: { Date() })
        let replacement = RecordingAuthorityCoordinator(store: store, transport: emptyServer)
        await #expect(throws: RecordingAuthorityError.authorityDisappeared) {
            try await replacement.refresh()
        }
    }
}
