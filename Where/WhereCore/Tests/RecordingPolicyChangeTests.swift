import Foundation
import Testing
@testable import WhereCore

struct RecordingPolicyChangeTests {
    private static let deviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )
    private static let writerID = RecordingDeviceID(
        rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    )
    private static let date = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func laterOffFromThePreviouslyLosingSiblingRemainsAuthoritative() throws {
        let history = Self.historyWithRestrictiveDescendant(
            descendantID: "00000000-0000-0000-0000-000000000004",
            state: .off,
            reason: .userCommand,
        )

        #expect(RecordingPolicyChange.formValidPersistedTimelines(history))
        let canonical = try #require(RecordingPolicyChange.canonicalTimeline(in: history))
        #expect(canonical.map(\.id) == [history[0].id, history[2].id, history[3].id])
        #expect(canonical.last?.state == .off)
    }

    @Test func laterArchiveFromThePreviouslyLosingSiblingRemainsAuthoritative() throws {
        let history = Self.historyWithRestrictiveDescendant(
            descendantID: "00000000-0000-0000-0000-000000000005",
            state: .archived,
            reason: .archive,
        )

        #expect(RecordingPolicyChange.formValidPersistedTimelines(history))
        let canonical = try #require(RecordingPolicyChange.canonicalTimeline(in: history))
        #expect(canonical.map(\.id) == [history[0].id, history[2].id, history[3].id])
        #expect(canonical.last?.state == .archived)
    }

    @Test func oneAppendingCommandJoinsAndClearsEveryObservedHead() throws {
        let root = Self.change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            effectiveAt: Self.date,
            state: .on,
            reason: .initialRegistration,
        )
        let first = Self.change(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(1),
            state: .on,
            reason: .userCommand,
        )
        let second = Self.change(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(2),
            state: .off,
            reason: .userCommand,
        )
        let observed = [second, root, first]

        let command = try RecordingPolicyChange.appendingCommand(
            to: observed,
            deviceID: Self.deviceID,
            issuedAt: Self.date.addingTimeInterval(3),
            issuedByDeviceID: Self.writerID,
            effectiveAt: Self.date.addingTimeInterval(1),
            state: .on,
            reason: .userCommand,
        )
        let joined = observed + [command]

        #expect(command.parentIDs == [first.id, second.id])
        #expect(command.revision == 2)
        #expect(command.effectiveAt == second.effectiveAt)
        #expect(joined.count(where: { $0.revision == 2 }) == 1)
        #expect(RecordingPolicyChange.maximalHeads(in: joined) == [command])
        #expect(RecordingPolicyChange.canonicalHead(in: joined) == command)
    }

    @Test func incompleteMultiParentCommandFailsClosed() {
        let root = Self.change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            state: .on,
            reason: .initialRegistration,
        )
        let orphanedJoin = Self.change(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [
                root.id,
                Self.id("20000000-0000-0000-0000-000000000000"),
            ],
            revision: 1,
            state: .off,
            reason: .userCommand,
        )

        #expect(
            RecordingPolicyChange.formValidPersistedTimelines([root, orphanedJoin]) == false,
        )
        #expect(RecordingPolicyChange.canonicalTimeline(in: [root, orphanedJoin]) == nil)
        #expect(RecordingPolicyChange.maximalHeads(in: [root, orphanedJoin]) == nil)
    }

    @Test func historicalAuthorityResolvesTheEligibleInducedDAG() {
        let root = Self.change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            effectiveAt: Self.date,
            state: .on,
            reason: .initialRegistration,
        )
        let off = Self.change(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(10),
            state: .off,
            reason: .userCommand,
        )
        let concurrentOn = Self.change(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(20),
            state: .on,
            reason: .userCommand,
        )
        let joinedOn = Self.change(
            id: "40000000-0000-0000-0000-000000000000",
            parentIDs: [off.id, concurrentOn.id],
            revision: 2,
            effectiveAt: Self.date.addingTimeInterval(30),
            state: .on,
            reason: .userCommand,
        )
        let history = [joinedOn, concurrentOn, root, off]

        #expect(RecordingPolicyChange.effectiveHead(
            in: history,
            at: Self.date.addingTimeInterval(5),
        ) == root)
        #expect(RecordingPolicyChange.effectiveHead(
            in: history,
            at: Self.date.addingTimeInterval(15),
        ) == off)
        #expect(RecordingPolicyChange.effectiveHead(
            in: history,
            at: Self.date.addingTimeInterval(25),
        ) == off)
        #expect(RecordingPolicyChange.effectiveHead(
            in: history,
            at: Self.date.addingTimeInterval(35),
        ) == joinedOn)
    }

    @Test func concurrentDestructiveBarrierChangesTheCleanupTokenEvenWhenItsUUIDLoses() throws {
        let root = Self.change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            state: .on,
            reason: .initialRegistration,
        )
        let previousUUIDWinner = Self.change(
            id: "F0000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(1),
            state: .off,
            reason: .accountReset,
        )
        let newLowerUUIDBarrier = Self.change(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(1),
            state: .off,
            reason: .accountReset,
        )
        let prior = try #require(RecordingPolicyChange.destructiveCleanupToken(
            in: [root, previousUUIDWinner],
        ))
        let joined = try #require(RecordingPolicyChange.destructiveCleanupToken(
            in: [newLowerUUIDBarrier, root, previousUUIDWinner],
        ))

        #expect(prior.rawValue == previousUUIDWinner.id)
        #expect(joined != prior)
        #expect(RecordingPolicyChange.destructiveCleanupToken(
            in: [previousUUIDWinner, newLowerUUIDBarrier, root],
        ) == joined)
    }

    @Test func concurrentResetFloorJoinsLatestCutoffUntilADescendantReplace() {
        let root = Self.change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            state: .on,
            reason: .initialRegistration,
        )
        let earlierReset = Self.change(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(10),
            state: .off,
            reason: .accountReset,
        )
        let laterReset = Self.change(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(20),
            state: .off,
            reason: .accountReset,
        )
        let reenabled = Self.change(
            id: "40000000-0000-0000-0000-000000000000",
            parentIDs: [earlierReset.id, laterReset.id],
            revision: 2,
            effectiveAt: Self.date.addingTimeInterval(30),
            state: .on,
            reason: .userCommand,
        )
        let replacement = Self.change(
            id: "50000000-0000-0000-0000-000000000000",
            parentIDs: [reenabled.id],
            revision: 3,
            effectiveAt: Self.date.addingTimeInterval(40),
            state: .off,
            reason: .backupReplace,
        )
        let throughReenable = [laterReset, root, reenabled, earlierReset]

        #expect(
            RecordingPolicyChange.activeAccountResetFloor(in: throughReenable)
                == laterReset.effectiveAt,
        )
        #expect(RecordingPolicyChange.activeAccountResetFloor(
            in: throughReenable + [replacement],
        ) == nil)
    }

    @Test func childCannotMoveItsHistoricalCutoffBeforeItsParent() {
        let root = Self.change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            effectiveAt: Self.date,
            state: .on,
            reason: .initialRegistration,
        )
        let off = Self.change(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: Self.date.addingTimeInterval(2),
            state: .off,
            reason: .userCommand,
        )
        let backdatedEnable = Self.change(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [off.id],
            revision: 2,
            effectiveAt: Self.date.addingTimeInterval(1),
            state: .on,
            reason: .userCommand,
        )
        let history = [root, off, backdatedEnable]

        #expect(RecordingPolicyChange.formValidPersistedTimelines(history) == false)
        #expect(RecordingPolicyChange.canonicalTimeline(in: history) == nil)
    }

    @Test func backupMergeCanPreserveEveryCompleteAuthorityState() {
        let ids = [
            "10000000-0000-0000-0000-000000000000",
            "20000000-0000-0000-0000-000000000000",
            "30000000-0000-0000-0000-000000000000",
        ]
        for (id, state) in zip(ids, [
            RecordingPolicyState.on,
            .off,
            .archived,
        ]) {
            let barrier = Self.change(
                id: id,
                parentIDs: [],
                revision: 0,
                state: state,
                reason: .backupMerge,
            )
            #expect(barrier.hasValidReasonAndState)
            #expect(barrier.reason.discardsPendingSamples == false)
        }
    }

    private static func historyWithRestrictiveDescendant(
        descendantID: String,
        state: RecordingPolicyState,
        reason: RecordingPolicyReason,
    ) -> [RecordingPolicyChange] {
        let root = change(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [],
            revision: 0,
            state: .on,
            reason: .initialRegistration,
        )
        let previousWinner = change(
            id: "F0000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: date.addingTimeInterval(1),
            state: .on,
            reason: .userCommand,
        )
        let previousLoser = change(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [root.id],
            revision: 1,
            effectiveAt: date.addingTimeInterval(1),
            state: .on,
            reason: .userCommand,
        )
        let restrictiveDescendant = change(
            id: descendantID,
            parentIDs: [previousLoser.id],
            revision: 2,
            effectiveAt: date.addingTimeInterval(2),
            state: state,
            reason: reason,
        )
        return [root, previousWinner, previousLoser, restrictiveDescendant]
    }

    private static func change(
        id: String,
        parentIDs: [UUID],
        revision: Int64,
        effectiveAt: Date = date,
        state: RecordingPolicyState,
        reason: RecordingPolicyReason,
    ) -> RecordingPolicyChange {
        RecordingPolicyChange(
            id: self.id(id),
            deviceID: deviceID,
            parentIDs: parentIDs,
            revision: revision,
            issuedAt: date,
            issuedByDeviceID: writerID,
            effectiveAt: effectiveAt,
            state: state,
            reason: reason,
        )
    }

    private static func id(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
