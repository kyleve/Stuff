import Foundation
import Testing
@testable import WhereCore

struct RecordingDeviceArchiveTests {
    @Test func archiveRetainsItsIndependentWriterAndTarget() {
        let target = RecordingDeviceID(rawValue: UUID())
        let writer = RecordingDeviceID(rawValue: UUID())
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let archive = RecordingDeviceArchive(
            id: UUID(),
            deviceID: target,
            archivedAt: date,
            archivedByDeviceID: writer,
        )

        #expect(archive.deviceID == target)
        #expect(archive.archivedByDeviceID == writer)
        #expect(archive.archivedAt == date)
    }
}
