import Foundation
import Testing
@testable import WhereCore

struct WhereDataEpochTests {
    private static let deviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 100)

    @Test func noDestructiveChangesResolveToTheImplicitRoot() throws {
        let resolution = try WhereDataEpoch.resolve(in: [])

        #expect(resolution.current == .initial)
        #expect(resolution.realHeads == [.initial])
    }

    @Test func resetBarrierRejectsEarlierRegistrationAndAcceptsLaterRegistration() throws {
        let reset = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let later = Self.epoch(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [reset.id],
            revision: 2,
            changedAt: Self.baseDate.addingTimeInterval(1),
            reason: .backupReplace,
        )

        #expect(try WhereDataEpoch.resetBarrier(for: .initial, in: [reset, later]) == reset
            .changedAt)
        #expect(try WhereDataEpoch.resetBarrier(for: later.id, in: [reset, later]) == nil)
    }

    @Test func concurrentResetOutranksReplaceAtTheSameRevision() throws {
        let replacement = Self.epoch(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Self.baseDate,
            reason: .backupReplace,
        )
        let reset = Self.epoch(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Self.baseDate,
            reason: .accountReset,
        )

        #expect(try WhereDataEpoch.canonicalHead(in: [replacement, reset]) == reset)
    }

    @Test func twoConcurrentResetsResolveToLockedSyntheticEmptyEpoch() throws {
        let first = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let second = Self.reset(
            id: "20000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate.addingTimeInterval(1),
        )

        let resolution = try WhereDataEpoch.resolve(in: [second, first])

        #expect(
            resolution.current.id.rawValue
                == UUID(uuidString: "44DF774E-FC5C-8C4B-8742-04737BFCFED9"),
        )
        #expect(resolution.current.parentIDs == [first.id, second.id])
        #expect(resolution.current.revision == 2)
        #expect(resolution.current.changedAt == second.changedAt)
        #expect(resolution.current.reason == .accountReset)
        #expect(resolution.realHeads == [first, second])
    }

    @Test func anotherConcurrentResetChangesTheSyntheticEpochIdentity() throws {
        let first = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let second = Self.reset(
            id: "20000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate.addingTimeInterval(1),
        )
        let third = Self.reset(
            id: "30000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate.addingTimeInterval(2),
        )

        let twoResetID = try WhereDataEpoch.resolve(in: [first, second]).current.id
        let threeResetID = try WhereDataEpoch.resolve(in: [third, second, first]).current.id

        #expect(twoResetID.rawValue == UUID(
            uuidString: "44DF774E-FC5C-8C4B-8742-04737BFCFED9",
        ))
        #expect(threeResetID.rawValue == UUID(
            uuidString: "E0710538-52EF-8169-8641-12BF823E00AB",
        ))
        #expect(threeResetID != twoResetID)
    }

    @Test func weakerConcurrentReplaceDoesNotChangeTheResetConflictIdentity() throws {
        let first = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let second = Self.reset(
            id: "20000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate.addingTimeInterval(1),
        )
        let replacement = Self.epoch(
            id: "F0000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Self.baseDate.addingTimeInterval(2),
            reason: .backupReplace,
        )

        let before = try WhereDataEpoch.resolve(in: [first, second])
        let after = try WhereDataEpoch.resolve(in: [replacement, second, first])

        #expect(after.current.id == before.current.id)
        #expect(after.current.parentIDs == before.current.parentIDs)
        #expect(after.realHeads == [replacement, first, second])
    }

    @Test func oneMultiParentJoinRetiresEveryObservedRealHead() throws {
        let first = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let second = Self.reset(
            id: "20000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate.addingTimeInterval(1),
        )
        let replacement = Self.epoch(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [second.id, first.id],
            revision: 2,
            changedAt: Self.baseDate.addingTimeInterval(2),
            reason: .backupReplace,
        )

        let resolution = try WhereDataEpoch.resolve(in: [second, replacement, first])

        #expect(resolution.current == replacement)
        #expect(resolution.realHeads == [replacement])
        #expect(try WhereDataEpoch.maximalHeads(in: [replacement, first, second]) == [replacement])
    }

    @Test func missingOneNamedParentFailsClosed() {
        let first = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let missing = Self.id("20000000-0000-0000-0000-000000000000")
        let invalidJoin = Self.epoch(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [first.id, missing],
            revision: 2,
            changedAt: Self.baseDate.addingTimeInterval(1),
            reason: .backupReplace,
        )

        #expect(throws: RecordingPersistenceError.incompleteDataEpochHistory) {
            try WhereDataEpoch.resolve(in: [first, invalidJoin])
        }
    }

    @Test func persistedEpochCannotReuseTheImplicitRootIdentity() {
        let invalid = WhereDataEpoch(
            id: .initial,
            parentIDs: [Self.id("10000000-0000-0000-0000-000000000000")],
            revision: 1,
            changedAt: Self.baseDate,
            changedByDeviceID: Self.deviceID,
            reason: .accountReset,
        )

        #expect(throws: RecordingPersistenceError.incompleteDataEpochHistory) {
            try WhereDataEpoch.canonicalHead(in: [invalid])
        }
    }

    @Test func persistedEventCannotReuseTheSyntheticResetConflictIdentity() {
        let first = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let second = Self.reset(
            id: "20000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate.addingTimeInterval(1),
        )
        let collision = Self.epoch(
            id: "44DF774E-FC5C-8C4B-8742-04737BFCFED9",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Self.baseDate.addingTimeInterval(2),
            reason: .backupReplace,
        )

        #expect(throws: RecordingPersistenceError.incompleteDataEpochHistory) {
            try WhereDataEpoch.resolve(in: [collision, second, first])
        }
    }

    @Test func persistedEventCannotUseAnyUUIDv8SyntheticIdentity() {
        let invalid = Self.epoch(
            id: "DEADBEEF-0000-8000-8000-000000000001",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Self.baseDate,
            reason: .backupReplace,
        )

        #expect(throws: RecordingPersistenceError.incompleteDataEpochHistory) {
            try WhereDataEpoch.resolve(in: [invalid])
        }
    }

    @Test func causalChildCannotMoveTheEraseBoundaryBeforeItsParent() {
        let parent = Self.reset(
            id: "10000000-0000-0000-0000-000000000000",
            changedAt: Self.baseDate,
        )
        let child = Self.epoch(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [parent.id],
            revision: 2,
            changedAt: Self.baseDate.addingTimeInterval(-1),
            reason: .backupReplace,
        )

        #expect(throws: RecordingPersistenceError.incompleteDataEpochHistory) {
            try WhereDataEpoch.canonicalHead(in: [parent, child])
        }
    }

    private static func reset(id: String, changedAt: Date) -> WhereDataEpoch {
        epoch(
            id: id,
            parentIDs: [.initial],
            revision: 1,
            changedAt: changedAt,
            reason: .accountReset,
        )
    }

    private static func epoch(
        id: String,
        parentIDs: [WhereDataEpochID],
        revision: Int64,
        changedAt: Date,
        reason: WhereDataEpochReason,
    ) -> WhereDataEpoch {
        WhereDataEpoch(
            id: self.id(id),
            parentIDs: parentIDs,
            revision: revision,
            changedAt: changedAt,
            changedByDeviceID: deviceID,
            reason: reason,
        )
    }

    private static func id(_ value: String) -> WhereDataEpochID {
        WhereDataEpochID(rawValue: UUID(uuidString: value)!)
    }
}
