import Foundation
import Testing
@testable import WhereCore

struct RecordingAssignmentChangeTests {
    private static let phone = device("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    private static let tablet = device("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
    private static let writer = device("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
    private static let date = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func emptyHistoryIsUnconfigured() {
        #expect(RecordingAssignmentChange.resolve([]) == .unconfigured)
    }

    @Test func concurrentAssignmentsToTheSameDeviceCoalesce() {
        let first = Self.change(id: 1, assignedDeviceID: Self.phone)
        let second = Self.change(id: 2, assignedDeviceID: Self.phone)

        #expect(
            RecordingAssignmentChange.resolve([first, second])
                == .resolved(.device(Self.phone)),
        )
    }

    @Test func concurrentAssignmentsToDifferentDevicesFailClosed() {
        let first = Self.change(id: 1, assignedDeviceID: Self.phone)
        let second = Self.change(id: 2, assignedDeviceID: Self.tablet)

        #expect(
            RecordingAssignmentChange.resolve([first, second])
                == .conflict([Self.phone, Self.tablet]),
        )
        #expect(RecordingAssignmentChange.resolve([first, second])
            .permitsRecording(on: Self.phone) == false)
        #expect(RecordingAssignmentChange.resolve([first, second])
            .permitsRecording(on: Self.tablet) == false)
    }

    @Test func concurrentOffWinsAnAssignment() {
        let assigned = Self.change(id: 1, assignedDeviceID: Self.phone)
        let off = Self.change(id: 2, assignedDeviceID: nil)

        #expect(RecordingAssignmentChange.resolve([assigned, off]) == .resolved(.off))
    }

    @Test func commandJoinsEveryObservedHeadAndUsesTheLatestCutoff() throws {
        let first = Self.change(id: 1, effectiveAt: Self.date, assignedDeviceID: Self.phone)
        let second = Self.change(
            id: 2,
            effectiveAt: Self.date.addingTimeInterval(10),
            assignedDeviceID: Self.tablet,
        )

        let command = try RecordingAssignmentChange.appendingCommand(
            to: [first, second],
            assignment: .device(Self.phone),
            issuedAt: Self.date.addingTimeInterval(20),
            issuedByDeviceID: Self.writer,
            effectiveAt: Self.date.addingTimeInterval(5),
            reason: .userCommand,
        )

        #expect(command.parentIDs == [first.id, second.id])
        #expect(command.revision == 1)
        #expect(command.effectiveAt == second.effectiveAt)
        #expect(RecordingAssignmentChange
            .resolve([first, second, command]) == .resolved(.device(Self.phone)))
    }

    @Test func historicalResolutionUsesTheAssignmentAtTheSampleTime() throws {
        let root = Self.change(id: 1, assignedDeviceID: Self.phone)
        let transfer = try RecordingAssignmentChange.appendingCommand(
            to: [root],
            assignment: .device(Self.tablet),
            issuedAt: Self.date.addingTimeInterval(10),
            issuedByDeviceID: Self.writer,
            effectiveAt: Self.date.addingTimeInterval(10),
            reason: .userCommand,
        )

        #expect(
            RecordingAssignmentChange.resolve([root, transfer], at: Self.date.addingTimeInterval(5))
                == .resolved(.device(Self.phone)),
        )
        #expect(
            RecordingAssignmentChange.resolve(
                [root, transfer],
                at: Self.date.addingTimeInterval(10),
            )
                == .resolved(.device(Self.tablet)),
        )
    }

    @Test func aMissingParentInvalidatesTheWholeGraph() {
        let invalid = RecordingAssignmentChange(
            id: Self.uuid(2),
            parentIDs: [Self.uuid(1)],
            revision: 1,
            issuedAt: Self.date,
            issuedByDeviceID: Self.writer,
            effectiveAt: Self.date,
            assignedDeviceID: Self.phone,
            reason: .userCommand,
        )

        #expect(RecordingAssignmentChange.resolve([invalid]) == .invalid)
    }

    private static func change(
        id: Int,
        effectiveAt: Date = date,
        assignedDeviceID: RecordingDeviceID?,
    ) -> RecordingAssignmentChange {
        RecordingAssignmentChange(
            id: uuid(id),
            parentIDs: [],
            revision: 0,
            issuedAt: effectiveAt,
            issuedByDeviceID: writer,
            effectiveAt: effectiveAt,
            assignedDeviceID: assignedDeviceID,
            reason: .userCommand,
        )
    }

    private static func device(_ value: String) -> RecordingDeviceID {
        RecordingDeviceID(rawValue: UUID(uuidString: value)!)
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
