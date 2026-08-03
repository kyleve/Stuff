import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingAssignmentFilterTests {
    private static let phone = device("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    private static let tablet = device("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
    private static let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func transferMovesVisibilityAtItsEffectiveDate() throws {
        let initial = Self.change(id: 1, assignedDeviceID: Self.phone)
        let transfer = try RecordingAssignmentChange.appendingCommand(
            to: [initial],
            assignment: .device(Self.tablet),
            issuedAt: Self.start.addingTimeInterval(10),
            issuedByDeviceID: Self.phone,
            effectiveAt: Self.start.addingTimeInterval(10),
            reason: .userCommand,
        )
        let samples = [
            Self.sample(deviceID: Self.phone, offset: 5),
            Self.sample(deviceID: Self.phone, offset: 15),
            Self.sample(deviceID: Self.tablet, offset: 5),
            Self.sample(deviceID: Self.tablet, offset: 15),
        ]

        let visible = RecordingAssignmentFilter.visibleSamples(
            samples,
            assignmentChanges: [initial, transfer],
        )

        #expect(visible.map(\.timestamp) == [samples[0].timestamp, samples[3].timestamp])
    }

    @Test func offAndConflictsFailClosed() {
        let phoneClaim = Self.change(id: 1, assignedDeviceID: Self.phone)
        let tabletClaim = Self.change(id: 2, assignedDeviceID: Self.tablet)
        let gps = Self.sample(deviceID: Self.phone, offset: 5)

        #expect(RecordingAssignmentFilter.visibleSamples(
            [gps],
            assignmentChanges: [Self.change(id: 3, assignedDeviceID: nil)],
        ).isEmpty)
        #expect(RecordingAssignmentFilter.visibleSamples(
            [gps],
            assignmentChanges: [phoneClaim, tabletClaim],
        ).isEmpty)
    }

    @Test func unattributedAndManualSamplesRemainVisible() {
        let unattributed = LocationSample(
            timestamp: Self.start,
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 3,
            source: .gpsVisit,
        )
        let manual = LocationSample(
            timestamp: Self.start,
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 3,
            source: .manual,
            recordingDeviceID: Self.phone,
        )

        #expect(RecordingAssignmentFilter.visibleSamples(
            [unattributed, manual],
            assignmentChanges: [],
        ).count == 2)
    }

    private static func change(
        id: Int,
        assignedDeviceID: RecordingDeviceID?,
    ) -> RecordingAssignmentChange {
        RecordingAssignmentChange(
            id: uuid(id),
            parentIDs: [],
            revision: 0,
            issuedAt: start,
            issuedByDeviceID: phone,
            effectiveAt: start,
            assignedDeviceID: assignedDeviceID,
            reason: .userCommand,
        )
    }

    private static func sample(
        deviceID: RecordingDeviceID,
        offset: TimeInterval,
    ) -> LocationSample {
        LocationSample(
            timestamp: start.addingTimeInterval(offset),
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 3,
            source: .gpsVisit,
            recordingDeviceID: deviceID,
        )
    }

    private static func device(_ value: String) -> RecordingDeviceID {
        RecordingDeviceID(rawValue: UUID(uuidString: value)!)
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
