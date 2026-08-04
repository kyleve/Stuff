import Foundation
import Testing
@testable import WhereCore

struct RecordingDeviceRemovalTests {
    @Test func removalRetainsItsIndependentWriterAndTarget() {
        let target = RecordingDeviceID(rawValue: UUID())
        let writer = RecordingDeviceID(rawValue: UUID())
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let removal = RecordingDeviceRemoval(
            id: UUID(),
            deviceID: target,
            removedAt: date,
            removedByDeviceID: writer,
        )

        #expect(removal.deviceID == target)
        #expect(removal.removedByDeviceID == writer)
        #expect(removal.removedAt == date)
    }
}
